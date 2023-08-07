## Single VM under private net accessed by VPN client in Azure


This is a step-by-step tutorial to create a single VM under a private network
that is accessed via a VPN client, in our case a macos VPN client.

All the steps are based on Azure CLI, and therefore can be fully automated. The
following tutorial is based on IKEv2 protocol and built-in macos VPN client. The
only part that is manual is the setup of the macos vpn client, in which it is
necessary to have a few clicks to enable vpn.


**FILES**
- [create_vpn.sh](create_vpn.sh): automates all these steps and has some useful functions
- [create_selfsigncertificate.sh](create_selfsigncertificate.sh): automate certificate generation


*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>

---


#### Create basic components (resource group, vnet and subnet)

Create resource group:

```
az group create --name rgnetto1 \
                --location EastUS
```

See the resource groups of your subscription:

```
az group list -o table
```

To delete the resource group, in case you want to give up now :)! You can use
the command below to delete everything once you are done with the tutorial.

```
az group delete -g rgnetto1
```

Create a VNET. The default address space is: "10.0.0.0/16":

```
az network vnet create -g rgnetto1 \
                       -n rgnetto1vnet1\
                       --address-prefix 10.0.0.0/16
```

And its subnet:

```
az network vnet subnet create -n rgnetto1subnet1 \
                              -g rgnetto1 \
                              --vnet-name rgnetto1vnet1 \
                              --address-prefixes 10.0.0.0/24
```

#### Set up the gateway

Create gateway subnet, which has to be the name "GatewaySubnet":

```
az network vnet subnet create -g rgnetto1 \
                              -n GatewaySubnet \
                              --vnet-name rgnetto1vnet1 \
                              --address-prefix 10.0.1.0/24
```

And show the two subnets:

```
az network vnet subnet list -o table \
                            -g rgnetto1 \
                            --vnet-name rgnetto1vnet1
```

Create public ip for the gateway:

```
az network public-ip create -g rgnetto1 \
                            -n rgnetto1vnet1gwpip \
                            --allocation-method Dynamic
```

And finally, THE vpn gateway! Please note that the command below may take
several minutes to complete.


```
az network vnet-gateway create -g rgnetto1 \
                               -n rgnetto1vnet1gw \
                               --public-ip-address rgnetto1vnet1gwpip \
                               --vnet rgnetto1vnet1 \
                               --gateway-type Vpn \
                               --sku VpnGw1 \
                               --vpn-type RouteBased \
                               --client-protocol "IkeV2"
```

You can always update your gateway. For instance, if you forgot to specify the
client protocol at gateway creation time, type:

```
az network vnet-gateway update -g rgnetto1 \
                               -n rgnetto1vnet1gw \
                               --client-protocol "IkeV2"
```

SKU for vpn gateway can be found here:

https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways


To see the created gateway
```
az network vnet-gateway show -g rgnetto1 \
                             -n rgnetto1vnet1gw \
                             -o table
```

To see the public ip of the gateway
```
az network public-ip show -n rgnetto1vnet1gwpip \
                          -g rgnetto1
```

Once the gateway is provision we need to add the VPN client address pool, which
should NOT overlap with the network from which you are connnecting the VPN from
nor with the VNet that you want to connect to.

```
az network vnet-gateway update -g rgnetto1 \
                               -n rgnetto1vnet1gw \
                               --address-prefixes 172.20.100.0/26
```


#### create a self sign certificate

```
brew install strongswan
```

Generate the CA certificate

```
ipsec pki --gen --outform pem > caKey.pem
ipsec pki --self --in caKey.pem --dn "CN=VPN CA" --ca --outform pem > caCert.pem
```

```
/usr/bin/openssl x509 -in caCert.pem -outform der | base64 > tmp_cert_base64
ROOT_CERTIFICATE_PATH=tmp_cert_base64
# ROOT_CERTIFICATE_DATA=$(openssl x509 -in caCert.pem  -outform der | base64 -w0 ; echo)

```

#### generate p12 file
```
export PASSWORD="password"
export USERNAME="client"
# in zsh USERNAME change may have no effect, so just leave it as is
```

```
ipsec pki --gen --outform pem > "${USERNAME}Key.pem"
ipsec pki --pub --in "${USERNAME}Key.pem" | ipsec pki --issue \
          --cacert caCert.pem \
          --cakey caKey.pem \
          --dn "CN=${USERNAME}" \
          --san "${USERNAME}" \
          --flag clientAuth \
          --outform pem > "${USERNAME}Cert.pem"
```

Create a p12 bundle, which is basically the certificate from the pem files.

IMPORTANT: be careful with the openssl version used. Last reference of this tutorial has a discussion
on using -legacy flag after -export, because "OpenSSL 3.x changed the default algorithm and it's not compatible with macOS SSL libraries". To be sure, use /usr/bin/openssl, which will be the one provided by apple (not from brew).

```
/usr/bin/openssl pkcs12 -in "${USERNAME}Cert.pem" \
               -inkey "${USERNAME}Key.pem" \
               -certfile caCert.pem \
               -export -legacy -out "${USERNAME}.p12" \
               -password "pass:${PASSWORD}"
```

#### add certificate and 'tunnel type' definition to the gateway and download client

##### Alternative (1): azure portal

Go to virtual network gateway created previously and go to point-to-site
configuration (left). Select IKEv2 in 'tunnel type' and authentication type
'azure certificate'

name: mnetto-p2s-cert
public certicate data:  content of tmp_cert_base64 above

Download the VPN client in azure portal and keep the zip file... we will get to
that soon.

##### Alternative (2): cli

```
ROOT_CERT_NAME=rootcertificate
az network vnet-gateway root-cert create --resource-group mnettohpc2 \
                                         --gateway-name  mnettohpc2vnet1gw \
                                         --name $ROOT_CERT_NAME  \
                                         --public-cert-data tmp_cert_base64  \
                                         --output none
```

```
VPN_CLIENT=$(az network vnet-gateway vpn-client generate \
    --resource-group rgnetto1 \
    --name rgnetto1vnet1gw \
    --authentication-method EAPTLS | tr -d '"')
curl $VPN_CLIENT --output vpnClient.zip
```


##### Zip file: let's get some relevant info from the zip file
```
unzip ./vpnClient.zip
```

```
VPN_SERVER=$(xmllint --xpath "string(/VpnProfile/VpnServer)" Generic/VpnSettings.xml)
VPN_TYPE=$(xmllint --xpath "string(/VpnProfile/VpnType)" Generic/VpnSettings.xml | tr '[:upper:]' '[:lower:]')
ROUTES=$(xmllint --xpath "string(/VpnProfile/Routes)" Generic/VpnSettings.xml)
```


### Configure VPN client

```
double-click on the p12 file, and you will be prompted for the password (macos
and certificate password)
```

#### Alternative (1): Manual

Go to network settings of macos and from the zip file access Generic/VpnSettings.xml. There you will find VpnServer. Get that info and use in two fields: Server address and Remote ID. For local ID use the USERNAME specified in above steps (which is the name of the p12 bundle certificate). The certificate is the one call USERNAME that will be in a list of other imported certificates.



#### Provision VM

Provision your VM, with no public ip address, in the same vnet of VPN gateway, download the ssh key
and once the VPN client is connected, have fun!

```
az vm create -n vm01 \
             -g rgnetto1 \
             --image UbuntuLTS \
             --size Standard_DS1_v2 \
             --vnet-name rgnetto1vnet1 \
             --subnet rgnetto1subnet1 \
             --public-ip-address "" \
             --generate-ssh-keys

```

```
ssh -i ~/.ssh/id_rsa marco@10.0.0.5
```


To delete the vm:

```
az vm delete \
    --resource-group mnettohpc2 \
    --name vm1 \
    --force-deletion none --yes
```

Double check the list of vms in the resource group:
```
az vm list -otable -g rgnetto1

```

## Problems

##### VPN connection is no longer working
It may be a good idea to reboot your machine if you tried several things :)

If you have issues importing the p12 file, take a look a the last reference of
this tutorial.

## References

- https://medium.com/@rafavinnce/configure-a-point-to-site-connection-to-a-vnet-using-native-azure-certificate-authentication-224a676468a3

- https://learn.microsoft.com/en-us/azure/vpn-gateway/openvpn-azure-ad-client-mac

- https://learn.microsoft.com/en-us/azure/vpn-gateway/openvpn-azure-ad-tenant

- https://learn.microsoft.com/en-us/answers/questions/1187824/do-i-need-to-create-certs-when-using-azure-ad-auth

- generate certificate linux:
https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-certificates-point-to-site-linux

- macos steps:
https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-vpn-client-cert-mac#openvpn-macos-steps

- https://babarmunir.wordpress.com/2018/12/29/configure-point-to-site-p2s-vpn-using-azure-cli/

- https://community.microstrategy.com/s/article/Set-up-point-to-site-VPN-in-Azure-for-Mac?language=en_US

- https://learn.microsoft.com/en-us/azure/storage/files/storage-files-configure-p2s-vpn-linux

- https://learn.microsoft.com/en-us/azure/virtual-machines/linux/mac-create-ssh-keys

- problem import p12 certificate on mac: https://discussions.apple.com/thread/254518218
