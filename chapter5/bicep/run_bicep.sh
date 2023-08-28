#!/usr/bin/env bash

RG=demo4vmss1
REGION=eastus
SKU=Standard_DS1_v2
STORAGECONTAINER=maincontainer1
STORAGEACCOUNT="$RG"storage1
VMSSNAME=myScaleSet
VMSSADMINUSER=azureuser
VNETADDRESS=10.39.0.0

STORAGEMOUNTPOINT="/applicationdata"
STORAGEADMINUSERFOLDER="$VMSSADMINUSER"data
APPFOLDER=$STORAGEMOUNTPOINT/$STORAGEADMINUSERFOLDER

JUMPBOXRG=myjumpboxrg
JUMPBOXVNET=myjumpboxvnet

VMSSVNETNAME="$VMSSNAME"VNET
VMSSSUBNETNAME="$VMSSNAME"SUBNET


BICEPPARAMFILE=vmssnfs.bicepparam
CLOUDINITFILE=cloud-init.txt
SSHKEYFILE=mysshkeyfile.pub


function generate_bicepparam(){

    cat << EOF > $BICEPPARAMFILE
using 'main.bicep'
param vnetName = '$VMSSVNETNAME'
param resourceGroupName = '$RG'
param location = '$REGION'
param vnetAddressPrefix = '$VNETADDRESS/16'
param subnetName = '$VMSSSUBNETNAME'
param subnetAddressPrefix = '$VNETADDRESS/24'
param storageAccountName = '$STORAGEACCOUNT'
param storageContainerName = '$STORAGECONTAINER'
param cloudInitScript = '$CLOUDINITFILE'
param vmssName = '$VMSSNAME'
param vmssAdminUserName = '$VMSSADMINUSER'
param vmssVnetName = '$VMSSVNETNAME'
param vmssSubnetName = '$VMSSSUBNETNAME'
param sku = '$SKU'
param sshKeyFile ='$SSHKEYFILE'
EOF
}


function generate_cloud_init(){

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
}

generate_bicepparam

generate_cloud_init

az deployment sub create --location $REGION --template-file main.bicep --parameters vmssnfs.bicepparam --verbose
