#!/usr/bin/env bash

##############################################################################
# Default variable definitions
##############################################################################
: "${RG:=mydemo}"
: "${REGION:=eastus}"

: "${VMNAME=${RG}vm}"
: "${SKU:=Standard_B2ms}"
: "${VMIMAGE:=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101}"
: "${ADMINUSER:=azureuser}"

: "${STORAGEACCOUNT:=${RG}sa}"
: "${KEYVAULT=${RG}kv}"

: "${VNETADDRESS:=10.38.0.0}"
: "${VMVNETNAME:=${RG}VNET}"
: "${VMSUBNETNAME:=${RG}SUBNET}"

# - We need only if we want to check the status of cyclecloud provisioning
# and the cluster scheduler provisioning
# - So, no VPN for peering means, no testing available
#
#: "${VPNRG:=myvpnrg}"
#: "${VPNVNET:=myvpnvnet}"


##############################################################################
# Definitions that are not recommended to be changed
##############################################################################
CLOUDINITFILE=cloudinit.file
AZURESUBSCRIPTIONFILE=azure_subscription.json
CYCLECLOUDACCOUNTFILE=cyclecloud_account.json
CLUSTERPARAMETERFILE=cluster_parameters.json
CREATECLUSTERFILE=/tmp/createcluster.sh
CLUSTERNAME=mycluster
CREATE_CLUSTER=false

LOGFILE=cyclecloud_cli_$(date "+%Y_%m_%d_%H%M").log

##############################################################################
# Variable that should not be changed as it is handled by this script
##############################################################################
VPNVNETPEERED=false

##############################################################################
# Log related functions
##############################################################################
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

function log_on(){
    exec 3>&1 >> $LOGFILE 2>&1
}

function showprogress(){
    echo -n "." | tee /dev/fd/3
}
function shownewline(){
    echo "" | tee /dev/fd/3
}

function showmsg(){

    tag=$1
    msg=$2

    echo "$1: $2"

    if [[ $tag == "done" ]]; then
        echo -en "${GREEN}[DONE]: " >&3
    elif  [[ $tag == "failed" ]]; then
        echo -en "${RED}[FAILED]: " >&3
    fi

    echo -e "${YELLOW}$msg${RESET}" >&3
}

##############################################################################
# Support functions for acquiring user password and public ssh key
##############################################################################
function return_typed_password(){

    password=""
    echo -n "Enter password: " >&2
    while IFS= read -p "$prompt" -r -s -n 1 char
    do
        if [[ $char == $'\0' ]] ; then
            break
        fi
        if [[ $char == $'\177' ]] ; then
            prompt=$'\b \b'
            password="${password%?}"
        else
            prompt='*'
            password+="$char"
        fi
    done
    echo $password
    echo "" >&2
}

function get_password_manually(){

    unset CCPASSWORD

    while true; do

        password1=$(return_typed_password)
        password2=$(return_typed_password)

        if [[ ${password1} != ${password2} ]]; then
            echo "Passwords do not match. Try again."
        else
            break
        fi
    done
    CCPASSWORD=$password1
}

function validate_secret_availability(){

    # assume user will use the existing ssh key from home directory

    if [ -z ${CCPASSWORD+x} ] ; then
        echo "CCPASSWORD: must be set and non-empty"
        echo "Control-C to cancel and set CCPASSWORD as environment variable"
        get_password_manually
    else
        echo "Got CCPASSWORD from environment variable"
    fi

    if [ -z ${CCPUBKEY+x} ] ; then
        echo "CCPUBKEY: must be set and non-empty"
        PUBKEYFILE="$HOME/.ssh/id_rsa.pub"
        if [ -f "$PUBKEYFILE" ]; then
            read -p "[$PUBKEYFILE] Can I get the pub key from here [Y|n]? " yn
            if [ -z "$yn" ] || [ "$yn" == "Y" ] || [ "$yn" == "y" ]; then
                CCPUBKEY=$(cat $PUBKEYFILE)
            else
                echo "Okay, set CCPUBKEY environment variable with your key and try again..."
                exit
            fi
        fi
    else
        echo "Got CCPUBKEY from environment variable"
    fi

}
##############################################################################
# Core functions
##############################################################################
function create_resource_group(){

    az group create --location $REGION \
                    --name $RG
    showmsg "done" "Created resource group: $RG"
}

function create_vnet_subnet(){

    az network vnet create -g $RG \
                           -n $VMVNETNAME \
                           --address-prefix "$VNETADDRESS"/16 \
                           --subnet-name $VMSUBNETNAME \
                           --subnet-prefixes "$VNETADDRESS"/24
    showmsg "done" "Created VNET and VSUBNET: $VMVNETNAME $VMSUBNETNAME"
}

function create_keyvault(){

    az keyvault create --resource-group $RG \
                   --name $KEYVAULT \
                   --location "$REGION" \
                   --enabled-for-deployment true \
                   --enabled-for-disk-encryption true \
                   --enabled-for-template-deployment true

    showmsg "done" "Created keyvault: $KEYVAULT"
}

function create_cluster_cloudinit_commands(){

    [[ ${CREATE_CLUSTER} = false ]] && return

cat << EOF
    - bash $CREATECLUSTERFILE

EOF

}

function create_cluster_cloudinit_files(){

    [[ ${CREATE_CLUSTER} = false ]] && return

    cyclecloud_subscription_name=$1

cat << EOF

    - path: /tmp/$CLUSTERPARAMETERFILE
      content: |
        {
          "Credentials": "${cyclecloud_subscription_name}",
          "SubnetId": "${RG}/${VMVNETNAME}/${VMSUBNETNAME}",
          "ReturnProxy": false,
          "UsePublicNetwork": false,
          "ExecuteNodesPublic": false,
          "Region": "${REGION}",
          "AdditionalNFSExportPath": null,
          "AdditionalNFSMountPoint": null,
          "DynamicSpotMaxPrice": null
        }

    - path: $CREATECLUSTERFILE
      permissions: '0755'
      content: |
         #!/bin/bash

         echo "Setting up the slurm cluster!"
         SLURMTEMPLATE=\$(runuser -l $ADMINUSER -c 'cyclecloud show_cluster  -t' | grep  'slurm.*template' | awk '{print \$1}' )
         echo "SLURMTEMPLATE=\$SLURMTEMPLATE"
         runuser -l $ADMINUSER -c 'cyclecloud show_cluster  -t' | grep  'slurm.*template'  | awk '{print \$1}'
         SLURMTEMPLATE=\$(runuser -l $ADMINUSER -c 'cyclecloud show_cluster  -t' | grep  "slurm.*template" | cut -d':' -f1)
         runuser -l $ADMINUSER -c "cyclecloud create_cluster \$SLURMTEMPLATE $CLUSTERNAME -p /tmp/$CLUSTERPARAMETERFILE"
         runuser -l $ADMINUSER -c "cyclecloud start_cluster $CLUSTERNAME"

         echo "Waiting for scheduler to be up-and-running..."
         max_provisioning_time=120
         max_retries=20
         wait_time=20
         get_state(){ runuser -l $ADMINUSER -c "cyclecloud show_nodes scheduler -c $CLUSTERNAME --states='Started' --output='%(Status)s'" ; }

         for (( r=1; r<=max_retries; r++ )); do

            schedulerstate=\$(get_state)
            echo \$schedulerstate
            if [ "\$schedulerstate" == "Failed" ]; then
                    runuser -l $ADMINUSER -c "cyclecloud retry $CLUSTERNAME"
                    sleep \$wait_time
            elif [ "\$schedulerstate" == "Ready" ]; then
                    echo "Scheduler provisioned"
                    break
            elif [ "\$schedulerstate" == "Off" ]; then
                    echo "Scheduler provisioning has not started yet"
                    sleep \$wait_time
            elif [ "\$schedulerstate" == "Acquiring" ] || [ "\$schedulerstate" == "Preparing" ] ; then
                start_time=\$(date +%s)
                while true; do
                    echo -n "."
                    sleep \$wait_time
                    current_time=\$(date +%s)
                    elapsed_time=\$((current_time - start_time))

                    if [ \$elapsed_time -ge \$max_provisioning_time ]; then
                            break
                    fi
                    schedulerstate=\$(get_state)
                    if [ "\$schedulerstate" != "Acquiring" ] && [ "\$schedulerstate" != "Preparing" ]  ; then
                            break
                    fi
                done
            fi

         done
         echo "Final scheduler state = \$schedulerstate"
EOF

}

function create_cloud_init(){

    account_info=$(az account show)

    azure_subscription_id=$(echo $account_info | jq -r '.id')
    azure_tenant_id=$(echo $account_info | jq -r '.tenantId')
    cyclecloud_subscription_name=$(echo $account_info | jq -r '.name')
    cyclecloud_admin_name=$ADMINUSER
    cyclecloud_storage_account=$STORAGEACCOUNT
    cyclecloud_storage_container=cyclecloud
    cyclecloud_location=$REGION
    cyclecloud_rg=$RG

cat << EOF > $CLOUDINITFILE
#cloud-config

runcmd:
    - apt-get -y install gnupg2
    - wget -qO - https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    - echo 'deb https://packages.microsoft.com/repos/cyclecloud bionic main' > /etc/apt/sources.list.d/cyclecloud.list
    - apt-get update
    - apt-get install -yq openjdk-8-jdk
    - update-java-alternatives -s java-1.8.0-openjdk-amd64
    - apt-get install -yq python3-venv
    - echo "Install Azure CLI"
    - curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    - which az
    - az login --identity --allow-no-subscriptions
    - CCPASSWORD=\$(az keyvault secret show --name ccpassword --vault-name $KEYVAULT --query 'value' -o tsv)
    - CCPUBKEY=\$(az keyvault secret show --name ccpubkey --vault-name $KEYVAULT --query 'value' -o tsv)
    - apt-get install -yq cyclecloud8=8.4.0-3122
    - escaped_CCPASSWORD=\$(printf '%s\n' "\$CCPASSWORD" | sed -e 's/[]\/\$*.^[]/\\\&/g')
    - escaped_CCPUBKEY=\$(printf '%s\n' "\$CCPUBKEY" | sed -e 's/[]\/\$*.^[]/\\\&/g')
    - sed -i "s/CCPASSWORD/\$escaped_CCPASSWORD/g" /tmp/cyclecloud_account.json
    - sed -i "s/CCPUBKEY/\$escaped_CCPUBKEY/g" /tmp/cyclecloud_account.json
    - mv /tmp/$CYCLECLOUDACCOUNTFILE /opt/cycle_server/config/data/
    - /opt/cycle_server/cycle_server await_startup
    - unzip /opt/cycle_server/tools/cyclecloud-cli.zip -d /tmp
    - python3 /tmp/cyclecloud-cli-installer/install.py -y --installdir /home/${cyclecloud_admin_name}/.cycle --system
    - cmd="/usr/local/bin/cyclecloud initialize --loglevel=debug --batch --url=http://localhost:8080 --verify-ssl=false --username=${cyclecloud_admin_name} --password='\$CCPASSWORD'"
    - runuser -l ${cyclecloud_admin_name} -c "\$cmd"
    - mv /tmp/$AZURESUBSCRIPTIONFILE /opt/cycle_server/
    - runuser -l ${cyclecloud_admin_name} -c '/usr/local/bin/cyclecloud account create -f /opt/cycle_server/$AZURESUBSCRIPTIONFILE'
    - rm -f /opt/cycle_server/config/data/${CYCLECLOUDACCOUNTFILE}.imported
$(create_cluster_cloudinit_commands)

write_files:

    - path: /tmp/$CYCLECLOUDACCOUNTFILE
      content: |
        [
          {
            "AdType": "Application.Setting",
            "Name": "cycleserver.installation.initial_user",
            "Value": "${cyclecloud_admin_name}"
          },
          {
            "AdType": "AuthenticatedUser",
            "Name": "${cyclecloud_admin_name}",
            "RawPassword": "CCPASSWORD",
            "Superuser": true
          },
          {
            "AdType": "Credential",
            "CredentialType": "PublicKey",
            "Name": "${cyclecloud_admin_name}/public",
            "PublicKey": "CCPUBKEY"
          },
          {
            "AdType": "Application.Setting",
            "Name": "cycleserver.installation.complete",
            "Value": true
          }
        ]

    - path: /tmp/$AZURESUBSCRIPTIONFILE
      content: |
        {
          "Environment": "public",
          "AzureRMUseManagedIdentity": true,
          "AzureResourceGroup": "${cyclecloud_rg}",
          "AzureRMApplicationId": " ",
          "AzureRMApplicationSecret": " ",
          "AzureRMSubscriptionId": "${azure_subscription_id}",
          "AzureRMTenantId": " ${azure_tenant_id}",
          "DefaultAccount": true,
          "Location": "${cyclecloud_location}",
          "Name": "${cyclecloud_subscription_name}",
          "Provider": "azure",
          "ProviderId": "${azure_subscription_id}",
          "RMStorageAccount": "${cyclecloud_storage_account}",
          "RMStorageContainer": "${cyclecloud_storage_container}",
          "AcceptMarketplaceTerms": true
        }
$(create_cluster_cloudinit_files $cyclecloud_subscription_name)

EOF
}

function create_vm() {

    showmsg "done" "Start provisioning request"

    az vm create -n $VMNAME \
        -g $RG \
        --image $VMIMAGE \
        --size $SKU \
        --vnet-name $VMVNETNAME \
        --subnet $VMSUBNETNAME \
        --public-ip-address "" \
        --admin-username $ADMINUSER \
        --assign-identity \
        --generate-ssh-keys \
        --custom-data $CLOUDINITFILE

    showmsg "done" "Requested VM provisioning"
}

function peer_vpn(){


    if [ -z $VPNRG ] || [ -z $VPNVNET ]; then
        showmsg "failed" "VPNRG and VPNVNET are required for VPN peering and testing cyclecloud access"
        return 1
    fi

    echo "Peering vpn with created vnet"

    curl https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh  -O 2&>1 /dev/null

    bash ./create_peering_vpn.sh $VPNRG $VPNVNET $RG $VMVNETNAME
    tag="done"

    if [[ $? -ne 0 ]]; then
        tag="failed"
    else
       VPNVNETPEERED=true
    fi

    showmsg $tag "Created VPN peering"
    rm -f create_peering_vpn.sh
}

function get_subnetid(){

    subnetid=`az network vnet subnet show \
          --resource-group $RG\
          --vnet-name $VMVNETNAME \
          --name $VMSUBNETNAME \
          --query "id" -o tsv `

    echo "$subnetid"
}

function create_storage_account(){

    az storage account create \
          -n $STORAGEACCOUNT \
          -g $RG \
          --sku Standard_LRS

    showmsg "done" "Created storage account"
}

function add_vm_permission_subscription(){

    account_info=$(az account show)
    subscription=$(echo $account_info | jq -r '.id')

    VMPrincipalID=$(az vm show \
                             -g $RG \
                             -n "$VMNAME" \
                             --query "identity.principalId" \
                             -o tsv)

    az role assignment create \
          --assignee-principal-type ServicePrincipal \
          --assignee-object-id ${VMPrincipalID} \
          --role "Contributor" \
          --scope "/subscriptions/${subscription}"

    az role assignment list --assignee ${VMPrincipalID}

    showmsg "done" "Add VM principal ID permission to subscription: $subscription"
}

function add_vm_permission_keyvault(){

    VMPrincipalID=$(az vm show \
                         -g $RG \
                         -n "$VMNAME" \
                         --query "identity.principalId" \
                         -o tsv)

    echo $VMPrincipalID

    az keyvault set-policy --resource-group $RG \
                       --name $KEYVAULT \
                       --object-id $VMPrincipalID \
                       --key-permissions all \
                       --secret-permissions all

    showmsg "done" "Add VM principal ID permission to keyvault: $KEYVAULT"
}

function show_vm_access() {

    ipaddress=$(az vm show -g $RG -n $VMNAME --query privateIps -d --out tsv)

    showmsg "done" "Cloud-init will run in BACKGROUND and take some time to start cyclecloud (and cluster)"
    showmsg "done" "CycleCloud VM SSH access: ssh [-i <privatesshkey>] $ADMINUSER@$ipaddress"
    showmsg "done" "CycleCloud VM WEB access: http://$ipaddress:8080"
}


function set_keyvault_secrets(){

    az keyvault secret set --name ccpassword --vault-name $KEYVAULT --value "$CCPASSWORD" > /dev/null
    az keyvault secret set --name ccpubkey --vault-name $KEYVAULT --value "$CCPUBKEY" > /dev/null

    showmsg "done" "Set keyvault secrets"
}

function wait_cluster_provision(){

    if [ "$VPNVNETPEERED" == false ]; then
        showmsg "failed" "Cannot test cyclecloud/cluster access as no VPN peer was established"
        return 1
    fi

    pollingdelay=10
    showmsg "done" "Start polling cyclecloud VM (VPN access required). You can control-c at any time..."

    SSHCMD="ssh -o StrictHostKeychecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null"
    ipaddress=$(az vm show -g $RG -n $VMNAME --query privateIps -d --out tsv 2>&1)

    waited=false
    while true; do
       gotaccess=$($SSHCMD $ADMINUSER@$ipaddress hostname > /dev/null 2>/dev/null)
       error=$?
       [[ "$error" == 0 ]] && break
       sleep $pollingdelay
       showprogress
       waited=true
    done

    [[ "$waited" == true ]] && shownewline

    showmsg "done" "Got cyclecloud VM access"
    showmsg "done" "Start polling cluster scheduler. This may take a while..."

    waited=false
    while true; do
       schedulerstatus=$( $SSHCMD $ADMINUSER@$ipaddress 'cyclecloud show_nodes scheduler -c "$CLUSTERNAME" --states="Started" --output="%(Status)s" 2> /dev/null' )
       [[ "$schedulerstatus" == "Ready" ]] && break
       echo "schedulerstatus=$schedulerstatus"
       sleep $pollingdelay
       showprogress
       waited=true
   done

   [[ $waited == true ]] && shownewline

   if [[ "$schedulerstatus" == "Ready" ]]; then
      showmsg "done" "Cluster ready for submission"
       schedulerip=$( $SSHCMD $ADMINUSER@$ipaddress 'cyclecloud show_nodes scheduler -c "$CLUSTERNAME" --states="Started" --output="%(PrivateIp)s" 2> /dev/null' )
       showmsg "done" "Scheduler SSH access: ssh [-i <privatesshkey>] $ADMINUSER@$schedulerip"
   else
      showmsg "failed" "Cannot access cluster"
   fi
}

##############################################################################
# Main function calls
##############################################################################
echo "=============================================="
echo "Logfile of execution: $LOGFILE"

if [ $# == 1 ]; then
    CLUSTERNAME=$1
    echo "Cluster creation enabled: $CLUSTERNAME"
    CREATE_CLUSTER=true
fi

validate_secret_availability

echo "=============================================="
echo "Start provisioning process"
log_on

create_resource_group
create_vnet_subnet

peer_vpn
create_storage_account
create_keyvault

create_cloud_init
set_keyvault_secrets
create_vm
add_vm_permission_subscription
add_vm_permission_keyvault
show_vm_access

if [ $CREATE_CLUSTER == true ];  then
    wait_cluster_provision
fi
