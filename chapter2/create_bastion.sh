#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

: ${RG:=mybastionrg}
: ${REGION:=eastus}

: ${VMNAME:=${RG}vm}
: ${SKU:=Standard_B2ms}
: ${VMIMAGE:=Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest}
: ${ADMINUSER:=azureuser}

: ${VNETADDRESS:=10.38.0.0}
: ${VNETNAME:=${RG}VNET}
: ${VMSUBNETNAME:=${RG}SUBNET}
: ${CREATEJUMPBOX:=true}

# required bastion subnet name
SUBNETBASTIONNAME=AzureBastionSubnet
BASTIONNAME=${VNETNAME}bastion
BASTIONPIP=${BASTIONNAME}pip

CIDRVNETADDRESS="$VNETADDRESS/20"
CIDRSUBVMVNETADDRESS="$VNETADDRESS/24"
CIDRSUBBASTIONVNETADDRESS=$(IFS='.' read -r a b c d <<< "$VNETADDRESS" ; echo "$a.$b.$((c+1)).$d/26")


LOGFILE=bastion_$(date "+%Y_%m_%d_%H%M").log
JUMPBOXACCESS=jumpboxaccess.sh

PRIVATEKEY="$HOME/.ssh/id_rsa"

##############################################################################
# Log related functions
##############################################################################
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
RESET=$'\e[0m'

log_on(){ exec 3>&1 >> $LOGFILE 2>&1 ; }

showmsg(){ msg=$1 ; printf "${YELLOW}%-70s${RESET}" ${msg} >&3 ; }

showmsginfo(){ msg=$1 ; printf "${YELLOW}%-70s%s\n" ${msg} "${CYAN}[info]${RESET}" >&3 ; }

showstatusmsg(){
    statusmsg=$1
    [[ $statusmsg == "done" ]] && printf "%s\n" "${GREEN}[done]${RESET}" >&3
    [[ $statusmsg == "failed" ]] && printf "%s\n" "${RED}[failed]${RESET}" >&3
    [[ $statusmsg == "warning" ]] && printf "%s\n" "${CYAN}[warning]${RESET}" >&3

    return 0
}

##############################################################################
# azure related functions
##############################################################################
create_jumpbox() {

   showmsg "Create jumpbox vm: $VMNAME"

   az vm create -n $VMNAME \
                -g $RG \
                --image $VMIMAGE \
                --size $SKU \
                --vnet-name $VNETNAME \
                --subnet $VMSUBNETNAME \
                --public-ip-address "" \
                --admin-username $ADMINUSER \
                --generate-ssh-keys

   showstatusmsg "done"

   VMIP=$(az vm show -g $RG -n $VMNAME --query privateIps -d --out tsv)

   VMID=`az vm show --name $VMNAME \
                 --resource-group $RG \
                 --query 'id'  \
                 --output tsv`


cat << EOF > $JUMPBOXACCESS

sshjumpbox(){

   az network bastion ssh --name $BASTIONNAME \\
                       --resource-group $RG \\
                       --target-resource-id $VMID \\
                       --auth-type ssh-key \\
                       --username $ADMINUSER \\
                       --ssh-key $PRIVATEKEY
}

EOF

    showmsginfo "type: source ./$JUMPBOXACCESS"
    showmsginfo "then: sshjumpbox"
}

create_resourcegroup(){

    showmsg "Create resource group: $RG"

    az group create --name $RG \
                    --location $REGION

    showstatusmsg "done"
}

create_vnet(){

    showmsg "Create vnet: $VNETNAME"

    az network vnet create -g $RG \
                           -n $VNETNAME \
                           --address-prefix ${CIDRVNETADDRESS} \
                           --tags 'NRMSBastion=true'
    showstatusmsg "done"

}

create_subnets(){

    showmsg "Create subnets: $VMSUBNETNAME,$SUBNETBASTIONNAME"

    az network vnet subnet create -g $RG \
                                  -n $VMSUBNETNAME \
                                  --vnet-name $VNETNAME \
                                  --address-prefixes $CIDRSUBVMVNETADDRESS

    az network vnet subnet create -g $RG \
                                  -n $SUBNETBASTIONNAME \
                                  --vnet-name $VNETNAME \
                                  --address-prefix $CIDRSUBBASTIONVNETADDRESS
    showstatusmsg "done"
}

create_pubip(){

    showmsg "Create public ip: $BASTIONPIP"

    az network public-ip create -g $RG \
                                -n $BASTIONPIP \
                                --sku Standard \
                                --location $REGION
    showstatusmsg "done"
}

create_bastion(){

    showmsg "Create bastion: $BASTIONPIP"

    az network bastion create --name $BASTIONNAME \
                              --public-ip-address $BASTIONPIP \
                              --resource-group $RG \
                              --vnet-name $VNETNAME \
                              --location $REGION \
                              --enable-tunneling

    # Enable tunneling in case you see this message when using bastion ssh: “Bastion Host SKU must be Standard and Native Client must be enabled”
    #az network bastion update --name $BASTIONNAME \
    #                      --resource-group $RG \
    #                      --enable-tunneling

    showstatusmsg "done"
}

##############################################################################
# main function calls
##############################################################################

[[ "$*" =~ -h|--help|-help ]] && echo "Usage: ./$0" && exit 0

[[ ! -f $PRIVATEKEY ]] && echo "$PRIVATEKEY unavailable" && exit

echo ">> Logfile: $LOGFILE"

log_on

create_resourcegroup
create_vnet
create_subnets
create_pubip
create_bastion

[[ ${CREATEJUMPBOX} == true ]] && create_jumpbox

