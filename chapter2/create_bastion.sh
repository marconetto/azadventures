#!/usr/bin/env bash

create_vm() {

   echo "creating vm01 for testing"

   VMNAME=vm01
   ADMINUSER=azureuser
   az vm create -n $VMNAME \
             -g $RESOURCEGROUP \
             --image UbuntuLTS \
             --size Standard_DS1_v2 \
             --vnet-name $VNETNAME \
             --subnet $SUBNET1NAME \
             --public-ip-address "" \
             --admin-username $ADMINUSER \
             --generate-ssh-keys
   VMIP=$(az vm show -g $RESOURCEGROUP -n $VMNAME --query privateIps -d --out tsv)


   VMID=`az vm show --name $VMNAME \
                 --resource-group $RESOURCEGROUP \
                 --query 'id'  \
                 --output tsv`

   echo "az network bastion ssh --name $BASTIONNAME \\
                       --resource-group $RESOURCEGROUP \\
                       --target-resource-id $VMID \\
                       --auth-type ssh-key \\
                       --username $ADMINUSER \\
                       --ssh-key ~/.ssh/id_rsa"

   #echo "ssh -i ~/.ssh/id_rsa ${ADMINUSER}@${VMIP}"
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
VNETADDRESS=10.201.0.0/20
SUBNET1ADDRESS=10.201.2.0/24
SUBNETBASTIONADDRESS=10.201.0.0/26
REGION="eastus"


if [ ! -z "${a}" ] ; then
   VNETADDRESS=${a}
fi
if [ ! -z "${r}" ] ; then
   REGION=${r}
fi

VNETNAME=${RESOURCEGROUP}vnet1
SUBNET1NAME=${RESOURCEGROUP}subnet1
# it has to be this name
SUBNETBASTIONNAME=AzureBastionSubnet
BASTIONNAME=${VNETNAME}bastion
BASTIONPIP=${BASTIONNAME}pip

echo "RESOURCEGROUP=$RESOURCEGROUP"
echo "VNETADDRESS=$VNETADDRESS"
echo "REGION=$REGION"
echo "VNETNAME=$VNETNAME"
echo "SUBNET1NAME=$SUBNET1NAME"
echo "SUBNET1ADDRESS=$SUBNET1ADDRESS"
echo "SUBNETBASTIONNAME=$SUBNETBASTIONNAME"
echo "SUBNETBASTIONADDRESS=$SUBNETBASTIONADDRESS"
echo "BASTIONNAME=$BASTIONNAME"
echo "BASTIONPIP=$BASTIONPIP"


set -x
create_vm
exit
az group create --name $RESOURCEGROUP \
                --location $REGION

az network vnet create -g $RESOURCEGROUP \
                       -n $VNETNAME \
                       --address-prefix $VNETADDRESS \
                       --tags 'NRMSBastion=true'

az network vnet subnet create -n $SUBNET1NAME \
                              -g $RESOURCEGROUP \
                              --vnet-name $VNETNAME \
                              --address-prefixes $SUBNET1ADDRESS

az network vnet subnet create -g $RESOURCEGROUP \
                              -n $SUBNETBASTIONNAME \
                              --vnet-name $VNETNAME \
                              --address-prefix $SUBNETBASTIONADDRESS

az network public-ip create -g $RESOURCEGROUP \
                            -n $BASTIONPIP \
                            --sku Standard \
                            --location $REGION

set +
echo "bastion creation may take a while..."
set -

az network bastion create --name $BASTIONNAME \
                          --public-ip-address $BASTIONPIP \
                          --resource-group $RESOURCEGROUP \
                          --vnet-name $VNETNAME \
                          --location $REGION \
                          --enable-tunneling

if [ $CREATE_VM = true ]; then
  create_vm
fi
