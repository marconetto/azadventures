#!/usr/bin/env bash

create_vm() {

   echo "creating vm01 for testing"

   VMNAME=vm01
   az vm create -n $VMNAME \
             -g $RESOURCEGROUP \
             --image UbuntuLTS \
             --size Standard_DS1_v2 \
             --vnet-name $VNETNAME \
             --subnet $SUBNET1NAME \
             --public-ip-address "" \
             --generate-ssh-keys
   VMIP=$(az vm show -g $RESOURCEGROUP -n $VMNAME --query privateIps -d --out tsv)

   echo "ssh -i ~/.ssh/id_rsa marco@${VMIP}"
}




usage() { echo "Usage: $0 -g <resourcegroup> [ -r <region> ] [-a <vnetaddress>] [-c]" 1>&2; exit 1; }


CREATE_VM=false
while getopts ":g:a:r:c" o; do
    case "${o}" in
        g)
            g=${OPTARG}
            ;;
        a)
            a=${OPTARG}
            ;;
        r)
            r=${OPTARG}
            ;;
        c)
            CREATE_VM=true
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${g}" ] ; then
    usage
fi

RESOURCEGROUP=${g}
VNETADDRESS=10.0.0.0/16
SUBNET1ADDRESS=10.0.0.0/24
SUBNETGWADDRESS=10.0.1.0/24
REGION="eastus"
GWADDRESS="172.20.100.0/26"

CERTDIR="cert1/"
ROOT_CERT_NAME="rootcertificate"


if [ ! -z "${a}" ] ; then
   VNETADDRESS=${a}
fi
if [ ! -z "${r}" ] ; then
   REGION=${r}
fi

VNETNAME=${RESOURCEGROUP}vnet1
SUBNET1NAME=${RESOURCEGROUP}subnet1
# it has to be this name
SUBNETGWNAME=GatewaySubnet
GWNAME=${VNETNAME}gw
GWPIP=${GWNAME}pip

VPNCLIENTDIR="vpn2"

echo "RESOURCEGROUP=$RESOURCEGROUP"
echo "VNETADDRESS=$VNETADDRESS"
echo "REGION=$REGION"
echo "VNETNAME=$VNETNAME"
echo "SUBNET1NAME=$SUBNET1NAME"
echo "SUBNET1ADDRESS=$SUBNET1ADDRESS"
echo "SUBNETGWNAME=$SUBNETGWNAME"
echo "SUBNETGWADDRESS=$SUBNETGWADDRESS"
echo "GWNAME=$GWNAME"
echo "GWPIP=$GWPIP"
echo "GWADDRESS=$GWADDRESS"


set -x
az group create --name $RESOURCEGROUP \
                --location $REGION

az network vnet create -g $RESOURCEGROUP \
                       -n $VNETNAME \
                       --address-prefix $VNETADDRESS

az network vnet subnet create -n $SUBNET1NAME \
                              -g $RESOURCEGROUP \
                              --vnet-name $VNETNAME \
                              --address-prefixes $SUBNET1ADDRESS

az network vnet subnet create -g $RESOURCEGROUP \
                              -n $SUBNETGWNAME \
                              --vnet-name $VNETNAME \
                              --address-prefix $SUBNETGWADDRESS

az network public-ip create -g $RESOURCEGROUP \
                             -n $GWPIP \
                             --allocation-method Dynamic

set +
echo "vpn-gateway create may take a while..."
set -
az network vnet-gateway create -g $RESOURCEGROUP \
                               -n $GWNAME \
                               --public-ip-address $GWPIP \
                               --vnet $VNETNAME \
                               --gateway-type Vpn \
                               --sku VpnGw1 \
                               --vpn-type RouteBased \
                               --client-protocol "IkeV2"

az network vnet-gateway update -g $RESOURCEGROUP \
                               -n $GWNAME \
                               --address-prefixes $GWADDRESS



ROOT_CERTIFICATE_PATH=$CERTDIR/tmp_cert_base64
echo $ROOT_CERTIFICATE_PATH


az network vnet-gateway root-cert create --resource-group $RESOURCEGROUP \
                                         --gateway-name  $GWNAME \
                                         --name $ROOT_CERT_NAME  \
                                         --public-cert-data $ROOT_CERTIFICATE_PATH  \
                                         --output none

VPN_CLIENT=$(az network vnet-gateway vpn-client generate \
    --resource-group $RESOURCEGROUP \
    --name $GWNAME \
    --authentication-method EAPTLS | tr -d '"')

curl $VPN_CLIENT --create-dirs  --output $VPNCLIENTDIR/vpnClient.zip 

unzip $VPNCLIENTDIR/vpnClient.zip -d $VPNCLIENTDIR


VPN_SERVER=$(xmllint --xpath "string(/VpnProfile/VpnServer)" $VPNCLIENTDIR/Generic/VpnSettings.xml)

echo $VPN_SERVER

if [ $CREATE_VM = true ]; then
   create_vm
fi
