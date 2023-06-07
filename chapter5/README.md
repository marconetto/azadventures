## VM Scale Sets with a blob-based Network File System (NFS)

The goal of this tutorial is to provision VMs using VM Scale Sets (VMSSs) that
can have access to a shared network file system to write and read application
related data. VM instances can be created and destroyed (scale-out / scale-in)
and the data will remain in the storage account. This tutorial is based on
UbuntuLTS Linux operating system.

In a high level, this is what the instructions will allow you to do:
1. Provision a blob storage account that supports NFS (Network File System)
2. Provision a VMSS (Virtual Machine Scale Set) with two instances that will
  mount a storage container as a directory in the instances
3. Login into one of the VMs to check connection and see the storage there


In more details these are the major steps:
1. Create resource group, VNET, and SUBNET
2. Provision storage account
3. Set storage account access network rules
4. Create storage container
5. Generate cloud-init file to automate storage auto mount
6. Provision VMSS with two instances
7. Show VM instance names and private IP addresses
8. Login into one VM instance to see the storage directory


All these steps can be executed from your personal Linux machine OR in a linux jumpbox
VM inside azure.

**FILE:** Check out ``vmss_nfs.sh`` in this folder that automates all these steps.

*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>

---

<br>

Before we start, make sure you have azure cli installed and you are using the
right subscription:

```
az account set -n <mysubscription>
```

### Define a few variables

RG=demo1vmss1
SKU=Standard_DS1_v2


```
RG=demo4vmss1
SKU=Standard_DS1_v2
STORAGECONTAINER=maincontainer1
VMSSNAME=myScaleSet
REGION=eastus
VMSSADMINUSER=azureuser
VNETADDRESS=10.39.0.0

STORAGEMOUNTPOINT="/applicationdata"
STORAGEADMINUSERFOLDER="$VMSSADMINUSER"data
APPFOLDER=$STORAGEMOUNTPOINT/$STORAGEADMINUSERFOLDER

ADDMYPUBIPACCESS=true
# if you don't have a jumpbox, you don't need the three following lines
JUMPBOXRG=mnettobastion1
JUMPBOXVNET=mnettobastion1vnet1
JUMPBOXSUBNET=mnettobastion1subnet1

VMSSVNETNAME="$VMSSNAME"VNET
VMSSSUBNETNAME="$VMSSNAME"SUBNET
STORAGEACCOUNT="$RG"storage1
```


### 1. Create resource group, VNET, and SUBNET

#### Create resource group
```
az group create --location $REGION \
                --name $RG
```


#### Create VNET and SUBNET


```
az network vnet create -g $RG \
                       -n $VMSSVNETNAME \
                       --address-prefix "$VNETADDRESS"/16 \
                       --subnet-name $VMSSSUBNETNAME \
                       --subnet-prefixes "$VNETADDRESS"/24
```


### 2. Provision storage account


```
az storage account create --name $STORAGEACCOUNT \
                          --resource-group $RG \
                          --kind BlockBlobStorage \
                          --sku Premium_LRS \
                          --enable-hierarchical-namespace true \
                          --enable-nfs-v3 true \
                          --default-action deny \
                          --https-only false
```

Note that that https has to be set to false to enable NFS. We also set
default-action to deny so we allow access to storage account from specific
subnets/ips as defined below.


### 3. Set storage account access network rules

Enable the Azure Storage service endpoint on specified vnet

```
az network vnet subnet update --resource-group $RG \
                          --vnet-name $VMSSVNETNAME \
                          --name "$VMSSNAME"Subnet \
                          --service-endpoints Microsoft.Storage
```

Add a network rule for specified vnet + subnet. So, for sure we want VMSS subnet
to be able to access the storage account.


```
az storage account network-rule add --resource-group $RG \
                                --account-name $STORAGEACCOUNT \
                                --vnet-name "$VMSSNAME"VNET \
                                --subnet "$VMSSNAME"Subnet
```

You may want to add public ip address of your machine as well.

```
 if [ $ADDMYPUBIPACCESS = true ] ; then
   MYPUBLICIP=`curl ifconfig.me`
   az storage account network-rule add --resource-group $RG \
                                --account-name $STORAGEACCOUNT \
                                --ip-address $MYPUBLICIP
fi
```

Or add your jumpbox subnet access to the storage account in case you are
provisioning from the jump box. You can keep both the jump box and your public
ip.


```
  if [ ! -z ${JUMPBOXRG} ] ; then
    subnetId=$(az network vnet subnet show --name $JUMPBOXSUBNET \
                                           --vnet-name $JUMPBOXVNET \
                                           --resource-group $JUMPBOXRG \
                                           --query "id" \
                                           --output tsv)
     az network vnet subnet update --ids $subnetId \
                                  --service-endpoints Microsoft.Storage \
                                  --resource-group $RG
     az storage account network-rule add --resource-group $RG \
                                        --account-name $STORAGEACCOUNT \
                                        --subnet $subnetId
fi
```



Here we will see the network rule, it may take a few seconds to have effect,
that is why this sleep may help.

```
sleep 10
az storage account network-rule list --resource-group $RG \
                                 --account-name $STORAGEACCOUNT \
                                 --query virtualNetworkRules
```

### 4. Create storage container

```
az storage container create --name $STORAGECONTAINER \
                            --account-name $STORAGEACCOUNT \
                            --auth-mode login
```

This is the container in the storage account, which will represent the
application data folder in NFS. If you have any network issues to create the
container, in the last case, you can temporarily allow all networks to access it.

```
az storage account update --resource-group $RG \
                          --name $STORAGEACCOUNT \
                          --default-action Allow

az storage container create --name $STORAGECONTAINER \
                            --account-name $STORAGEACCOUNT \
                            --auth-mode login

az storage account update --resource-group $RG  \
                          --name $STORAGEACCOUNT \
                          --default-action Deny
```


### 5. Generate cloud-init file to automate storage auto mount


The following code will generate ``cloud-init.txt``. This file defines a set of
instructions to be executed when VM instances are created. This is where we link
the storage account to NFS for the VM instaces created by VMSS.

Further reading on cloud init can be found in references section of this
tutorial.


```
cat << EOF > cloud-init.txt
#cloud-config
package_upgrade: true
packages:
  - nfs-common

mounts:
 - [ '$STORAGEACCOUNT.blob.core.windows.net:/$STORAGEACCOUNT/$STORAGECONTAINER',
     $STORAGEMOUNTPOINT, 
     "nfs",
     "defaults,sec=sys,vers=3,nolock,proto=tcp,nofail", "0", "0" ]

runcmd:
  - 'mkdir $STORAGEMOUNTPOINT'
  - 'chmod o+rx $STORAGEMOUNTPOINT'
  - 'mount -a'
  - |
set -x
if [ ! -f $APPFOLDER ] ; then
    echo "creating $APPFOLDER folder"
    chmod o+rx $STORAGEMOUNTPOINT
    mkdir $APPFOLDER
    chown $VMSSADMINUSER.$VMSSADMINUSER $APPFOLDER
    install -o $VMSSADMINUSER -g $VMSSADMINUSER /dev/null "$APPFOLDER/$VMSSADMINUSER"_files_here
fi
EOF
```

### 6. Provision VMSS with two instances


```
az vmss create \
  --resource-group $RG \
  --name $VMSSNAME \
  --image UbuntuLTS \
  --orchestration-mode Uniform \
  --instance-count 2 \
  --admin-username $VMSSADMINUSER \
  --generate-ssh-keys \
  --vnet-name $VMSSVNETNAME \
  --subnet $VMSSSUBNETNAME \
  --vm-sku $SKU \
  --public-ip-address "" \
  --custom-data cloud-init.txt
```


### 7. Show VM instance names and private IP addresses

Here is how to get the VM instance private IP addresses:

```
VMS=$(az vmss list-instances \
  --resource-group $RG \
  --name $VMSSNAME \
  --query "[].{name:name}" --output tsv)

IPS=$(az vmss nic list --resource-group $RG \
     --vmss-nam $VMSSNAME --query "[].ipConfigurations[].privateIPAddress" --output tsv)
ARRAY_VMS=($VMS)
ARRAY_IPS=($IPS)

for i in "${!ARRAY_VMS[@]}"; do
    printf "%s has private ip %s\n" "${ARRAY_VMS[i]}" "${ARRAY_IPS[i]}"
done
```

You will see something like:

```
myScaleSet_313ad377 10.39.0.5
myScaleSet_d8bbc097 10.39.0.4
```


### 8. Login into one VM instance to see the storage directory


If you are doing this in the jumpbox/bastion VM, you may want to do some network
peering between the jumpbox and the VMSS vnet. If that is the case, please
checkout the following url:

https://github.com/marconetto/azadventures/tree/main/chapter3/

You will basically do:

```
curl
https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_bastion.sh  -O

bash ./create_peering_bastion.sh $JUMPBOXRG $JUMPBOXVNET $RG $VMSSVNETNAME
```

You will then be able to ssh into a VM instance of the VMSS

```
ssh 10.39.0.5
```

If you type ``df`` in the VM instance you may see something like:  
```
Filesystem                                                                      1K-blocks    Used     Available Use% Mounted on
udev                                                                              1736572       0       1736572   0% /dev
tmpfs                                                                              351072     740        350332   1% /run
/dev/sda1                                                                        30298176 3328996      26952796  11% /
tmpfs                                                                             1755340       0       1755340   0% /dev/shm
tmpfs                                                                                5120       0          5120   0% /run/lock
tmpfs                                                                             1755340       0       1755340   0% /sys/fs/cgroup
/dev/sda15                                                                         106858    5325        101534   5% /boot/efi
/dev/sdb1                                                                         7125020      28       6741712   1% /mnt
demo4vmss1storage1.blob.core.windows.net:/demo4vmss1storage1/maincontainer1 5497558138880       0 5497558138880   0% /applicationdata
tmpfs
```

You can create files in the folder of the admin user:

```
touch /applicationdata/azureuserdata/mynewfile
ls -l /applicationdata/azureuserdata/
-rw-r--r-- 1 root      azureuser 0 May 27 01:19 azureuser_files_here
-rw-rw-r-- 1 azureuser azureuser 0 May 27 01:31 mynewfile
```

### You can delete everything! :)

```
az group delete -g $RG
```


## References

- azure cli: https://learn.microsoft.com/en-us/cli/azure/
- https://learn.microsoft.com/en-us/azure/storage/common/storage-introduction
- https://learn.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to
- https://learn.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support
- disable secure transfer: https://learn.microsoft.com/en-us/azure/storage/common/storage-require-secure-transfer
- mount nfs: https://learn.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to
- cloud init: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/tutorial-automate-vm-deployment
- cloud init: https://cloud-init.io/



## Appendix
#### SKU list

If you want to know the list of available SKUs, you can use the following
command:

```
az vm list-skus --location eastus --output table
```
