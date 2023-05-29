#!/usr/bin/env bash


RG=demo7vmss1
SKU=Standard_DS1_v2
STORAGECONTAINER=maincontainer1
VMSSNAME=myScaleSet
REGION=eastus
VMSSADMINUSER=azureuser
VNETADDRESS=10.42.0.0

STORAGEMOUNTPOINT="/applicationdata"
STORAGEADMINUSERFOLDER="$VMSSADMINUSER"data
APPFOLDER=$STORAGEMOUNTPOINT/$STORAGEADMINUSERFOLDER


ADDMYPUBIPACCESS=true
JUMPBOXRG=mnettobastion1
JUMPBOXVNET=mnettobastion1vnet1
JUMPBOXSUBNET=mnettobastion1subnet1

VMSSVNETNAME="$VMSSNAME"VNET
VMSSSUBNETNAME="$VMSSNAME"SUBNET
STORAGEACCOUNT="$RG"storage1

function showinstances(){

    set +x
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

    set -x
}


function create_resource_group(){

    az group create --location $REGION \
                    --name $RG
}

function create_vnet_subnet(){

     az network vnet create -g $RG \
                            -n $VMSSVNETNAME \
                            --address-prefix "$VNETADDRESS"/16 \
                            --subnet-name $VMSSSUBNETNAME \
                            --subnet-prefixes "$VNETADDRESS"/24
}


function provision_storage_account(){

    az storage account create --name $STORAGEACCOUNT \
                              --resource-group $RG \
                              --kind BlockBlobStorage \
                              --sku Premium_LRS \
                              --enable-hierarchical-namespace true \
                              --enable-nfs-v3 true \
                              --default-action deny \
                              --https-only false
}


function set_storage_account_access(){

    # enable the Azure Storage service endpoint on specified vnet
    az network vnet subnet update --resource-group $RG \
                              --vnet-name $VMSSVNETNAME \
                              --name "$VMSSNAME"Subnet \
                              --service-endpoints Microsoft.Storage

    # add a network rule for specified vnet + subnet
    az storage account network-rule add --resource-group $RG \
                                    --account-name $STORAGEACCOUNT \
                                    --vnet-name "$VMSSNAME"VNET \
                                    --subnet "$VMSSNAME"Subnet

    if [ $ADDMYPUBIPACCESS = true ] ; then
       MYPUBLICIP=`curl ifconfig.me`
        echo "adding my public ip $MYPUBLICIP access to the storage account"
       az storage account network-rule add --resource-group $RG \
                                    --account-name $STORAGEACCOUNT \
                                    --ip-address $MYPUBLICIP
    fi


    if [ ! -z ${JUMPBOXRG} ] ; then
        echo "adding jumpbox subnet access to the storage account"
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

    # may take some time to update
    sleep 10
    az storage account network-rule list --resource-group $RG \
                                     --account-name $STORAGEACCOUNT \
                                     --query virtualNetworkRules
}


function provision_storage_container(){

    # update network permission access (Deny->Allow) in case you are having issues to create
    # the storage container

    # az storage account update --resource-group $RG --name $STORAGEACCOUNT --default-action Allow
    az storage container create --name $STORAGECONTAINER \
                                --account-name $STORAGEACCOUNT \
                                --auth-mode login
    # az storage account update --resource-group $RG --name $STORAGEACCOUNT --default-action Deny

}



function generate_cloudinit(){

    echo "Generating cloud-init file"

    cat << EOF > cloud-init.txt
#cloud-config
package_upgrade: true
packages:
  - nfs-common

mounts:
 - [ '$STORAGEACCOUNT.blob.core.windows.net:/$STORAGEACCOUNT/$STORAGECONTAINER', $STORAGEMOUNTPOINT, "nfs", "defaults,sec=sys,vers=3,nolock,proto=tcp,nofail", "0", "0" ]

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

function provision_vmss(){

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
}

create_resource_group
create_vnet_subnet
provision_storage_account
set_storage_account_access
provision_storage_container
generate_cloudinit
provision_vmss
showinstances
