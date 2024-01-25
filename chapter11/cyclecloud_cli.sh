#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
##############################################################################
# Default variable definitions
##############################################################################
: ${RG:=mydemo}
: ${REGION:=eastus}

: ${VMNAME:=${RG}vm}
: ${SKU:=Standard_B2ms}
: ${VMIMAGE:=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101}
: ${ADMINUSER:=azureuser}

: ${STORAGEACCOUNT:=${RG}sa}
: ${KEYVAULT:=${RG}kv}

: ${VNETADDRESS:=10.38.0.0}
: ${VMVNETNAME:=${RG}VNET}
: ${VMSUBNETNAME:=${RG}SUBNET}

# Checking status for cyclecloud provisioning is not mandatory
: ${VPNRG:=}
: ${VPNVNET:=}

# /21 will give you 2k IP addresses
CIDRVNETADDRESS="$VNETADDRESS"/16
CIDRSUBVNETADDRESS="$VNETADDRESS"/21

##############################################################################
# Definitions that are not recommended to be changed
##############################################################################
CLOUDINITFILE=cloudinit.file
AZURESUBSCRIPTIONFILE=azure_subscription.json
CYCLECLOUDACCOUNTFILE=cyclecloud_account.json
CLUSTERPARAMETERFILE=cluster_parameters.json
CREATECLUSTERFILE=/tmp/createcluster.sh

# used for slurm compute nodes and scheduler
CLUSTERIMAGE=almalinux8

##############################################################################
# Variables that should not be changed
##############################################################################
LOGFILE=cyclecloud_cli_$(date "+%Y_%m_%d_%H%M").log
VPNVNETPEERED=false
SSHCMD="ssh -o StrictHostKeychecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null"

##############################################################################
# Log related functions
##############################################################################
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
RESET=$'\e[0m'

log_on() { exec 3>&1 >>"$LOGFILE" 2>&1; }

showmsg() {
  msg=$1
  printf "${YELLOW}%-70s${RESET}" "${msg}" >&3
}

showmsginfo() {
  msg=$1
  printf "${YELLOW}%-70s%s\n" "${msg}" "${CYAN}[info]${RESET}" >&3
}

showstatusmsg() {
  statusmsg=$1
  [[ $statusmsg == "done" ]] && printf "%s\n" "${GREEN}[done]${RESET}" >&3
  [[ $statusmsg == "failed" ]] && printf "%s\n" "${RED}[failed]${RESET}" >&3
  [[ $statusmsg == "warning" ]] && printf "%s\n" "${CYAN}[warning]${RESET}" >&3

  return 0
}

sp='/-\|'
spinanim() {
  printf '\b%.1s' "$sp" >&3
  sp=${sp#?}${sp%???}
}
##############################################################################
# Support functions for acquiring user password and public ssh key
##############################################################################
function return_typed_password() {

  set +u
  password=""
  echo -n ">> Enter password: " >&2
  while IFS= read -p "$prompt" -r -s -n 1 char; do
    if [[ $char == $'\0' ]]; then
      break
    fi
    if [[ $char == $'\177' ]]; then
      prompt=$'\b \b'
      password="${password%?}"
    else
      prompt='*'
      password+="$char"
    fi
  done
  echo "$password"
  echo "" >&2
  set -u
}

function get_password_manually() {

  unset CCPASSWORD

  while true; do
    password1=$(return_typed_password)
    password2=$(return_typed_password)

    if [[ ${password1} != ${password2} ]]; then
      echo ">> Passwords do not match. Try again."
    else
      break
    fi
  done
  CCPASSWORD=$password1
}

function validate_secret_availability() {

  # assume user will use the existing ssh key from home directory
  if [[ -z ${CCPASSWORD-} ]]; then
    echo ">> You can control-c and set CCPASSWORD as environment variable"
    get_password_manually
  else
    echo ">> Got CCPASSWORD from environment variable"
  fi

  if [ -z "${CCPUBKEY-}" ]; then
    PUBKEYFILE="$HOME/.ssh/id_rsa.pub"
    if [ -f "$PUBKEYFILE" ]; then
      read -p ">> [$PUBKEYFILE] Can I get the pub key from here [Y|n]? " yn
      if [ -z "$yn" ] || [ "$yn" == "Y" ] || [ "$yn" == "y" ]; then
        CCPUBKEY=$(cat "$PUBKEYFILE")
      else
        echo ">> Set CCPUBKEY environment variable with your key and try again..."
        exit
      fi
    fi
  else
    echo ">> Got CCPUBKEY from environment variable"
  fi
}

##############################################################################
# Core functions
##############################################################################
function create_resource_group() {

  set -x
  showmsg "Create resource group: $RG"

  if [[ -z ${AZURETAGS-} ]]; then
    cmd="az group create --location '$REGION' --name '$RG'"
  else
    cmd="az group create --location '$REGION' \\
         --name '$RG' \\
         --tags ${AZURETAGS}"
  fi

  echo "$cmd"
  eval "${cmd}"

  showstatusmsg "done"
}

function create_vnet_subnet() {

  showmsg "Create VNET/VSUBNET: $VMVNETNAME/$VMSUBNETNAME"
  az network vnet create -g "$RG" \
    -n "$VMVNETNAME" \
    --address-prefix "$CIDRVNETADDRESS" \
    --subnet-name "$VMSUBNETNAME" \
    --subnet-prefixes "$CIDRSUBVNETADDRESS"
  showstatusmsg "done"
}

function create_keyvault() {

  showmsg "Create keyvault: $KEYVAULT"

  az keyvault create --resource-group "$RG" \
    --name "$KEYVAULT" \
    --location "$REGION" \
    --enabled-for-deployment true \
    --enabled-for-disk-encryption true \
    --enabled-for-template-deployment true

  showstatusmsg "done"
}

function create_cluster_cloudinit_commands() {

  [[ -z ${CLUSTERNAME-} ]] && return

  cat <<EOF
    - bash $CREATECLUSTERFILE

EOF
}

function create_cluster_cloudinit_files() {

  [[ -z ${CLUSTERNAME-} ]] && return

  cyclecloud_subscription_name=$1

  cat <<EOF

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
          "DynamicSpotMaxPrice": null,
          "HTCImageName" : "$CLUSTERIMAGE",
          "HPCImageName" : "$CLUSTERIMAGE",
          "SchedulerImageName" : "$CLUSTERIMAGE",
          "DynamicImageName" : "$CLUSTERIMAGE"
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

function create_cloud_init() {

  account_info=$(az account show)

  azure_subscription_id=$(echo "$account_info" | jq -r '.id')
  azure_tenant_id=$(echo "$account_info" | jq -r '.tenantId')
  cyclecloud_subscription_name=$(echo "$account_info" | jq -r '.name')
  cyclecloud_admin_name=$ADMINUSER
  cyclecloud_storage_account=$STORAGEACCOUNT
  cyclecloud_storage_container=cyclecloud
  cyclecloud_location=$REGION
  cyclecloud_rg=$RG

  cat <<EOF >"$CLOUDINITFILE"
#cloud-config

runcmd:
    - alias apt-get='apt-get -o DPkg::Lock::Timeout=-1'

    # Install CycleCloud
    - apt-get -y install gnupg2
    - wget -qO - https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    - echo 'deb https://packages.microsoft.com/repos/cyclecloud bionic main' > /etc/apt/sources.list.d/cyclecloud.list
    - apt-get update
    - apt-get install -yq cyclecloud8=8.4.0-3122
    - /opt/cycle_server/cycle_server await_startup

    # Collect and process admin password and ssh public key
    - bash /tmp/azcliinstaller.sh
    - az login --identity --allow-no-subscriptions
    - CCPASSWORD=\$(az keyvault secret show --name ccpassword --vault-name $KEYVAULT --query 'value' -o tsv)
    - CCPUBKEY=\$(az keyvault secret show --name ccpubkey --vault-name $KEYVAULT --query 'value' -o tsv)
    - escaped_CCPASSWORD=\$(printf '%s\n' "\$CCPASSWORD" | sed -e 's/[]\/\$*.^[]/\\\&/g')
    - escaped_CCPUBKEY=\$(printf '%s\n' "\$CCPUBKEY" | sed -e 's/[]\/\$*.^[]/\\\&/g')
    - sed -i "s/CCPASSWORD/\$escaped_CCPASSWORD/g" /tmp/${CYCLECLOUDACCOUNTFILE}
    - sed -i "s/CCPUBKEY/\$escaped_CCPUBKEY/g" /tmp/${CYCLECLOUDACCOUNTFILE}

    # Setup CycleCloud
    - mv /tmp/$CYCLECLOUDACCOUNTFILE /opt/cycle_server/config/data/
    - apt-get install -yq unzip python3-venv
    - unzip /opt/cycle_server/tools/cyclecloud-cli.zip -d /tmp
    - python3 /tmp/cyclecloud-cli-installer/install.py -y --installdir /home/${cyclecloud_admin_name}/.cycle --system
    - runuser -l ${cyclecloud_admin_name} -c "/usr/local/bin/cyclecloud initialize --loglevel=debug --batch --url=http://localhost:8080 --verify-ssl=false --username=\"$cyclecloud_admin_name\" --password=\"\$CCPASSWORD\""
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

    - path: /tmp/azcliinstaller.sh
      content: |
        function retry_installer(){
            local attempts=0
            local max=15
            local delay=25

            while true; do
                ((attempts++))
                "\$@" && {
                    echo "CLI installed"
                    break
                } || {
                    if [[ \$attempts -lt \$max ]]; then
                        echo "CLI installation failed. Attempt \$attempts/\$max."
                        sleep \$delay;
                    else
                        echo "CLI installation has failed after \$attempts attempts."
                        break
                    fi
                }
            done
        }

        function install_azure_cli(){
            install_script="/tmp/azurecli_installer.sh"
            curl -sL https://aka.ms/InstallAzureCLIDeb -o "\$install_script"
            retry_installer sudo bash "\$install_script"
            rm \$install_script
        }

        if ! command -v az &> /dev/null
        then
            echo "Installing Azure CLI"
            install_azure_cli
        fi
$(create_cluster_cloudinit_files "$cyclecloud_subscription_name")

EOF
}

function create_vm() {

  showmsg "Start CycleCloud VM provisioning request"

  az vm create -n "$VMNAME" \
    -g "$RG" \
    --image "$VMIMAGE" \
    --size "$SKU" \
    --vnet-name "$VMVNETNAME" \
    --subnet "$VMSUBNETNAME" \
    --public-ip-address "" \
    --admin-username "$ADMINUSER" \
    --assign-identity \
    --generate-ssh-keys \
    --custom-data "$CLOUDINITFILE"

  showstatusmsg "done"
}

function peer_vpn() {

  set +e
  showmsg "VPNRG/VPNVNET required for testing cyclecloud access"
  if [ -z "$VPNRG" ] || [ -z "$VPNVNET" ]; then
    showstatusmsg "warning"
    return 1
  fi

  echo "Peering vpn with created vnet"

  curl https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh -O 2 /dev/null &>1

  bash ./create_peering_vpn.sh "$VPNRG" "$VPNVNET" "$RG" "$VMVNETNAME"

  if [[ $? -ne 0 ]]; then
    showstatusmsg "failed"
  else
    VPNVNETPEERED=true
    showstatusmsg "done"
  fi

  rm -f create_peering_vpn.sh
  set -e
}

function get_subnetid() {

  subnetid=$(az network vnet subnet show \
    --resource-group "$RG" --vnet-name "$VMVNETNAME" \
    --name "$VMSUBNETNAME" \
    --query "id" -o tsv)

  echo "$subnetid"
}

function create_storage_account() {

  showmsg "Create storage account: $STORAGEACCOUNT"

  az storage account create \
    -n "$STORAGEACCOUNT" \
    -g "$RG" \
    --sku Standard_LRS

  showstatusmsg "done"
}

function add_vm_permission_subscription() {

  showmsg "Add VM principal ID access to subscription"

  account_info=$(az account show)
  subscription=$(echo "$account_info" | jq -r '.id')

  VMPrincipalID=$(az vm show \
    -g "$RG" \
    -n "$VMNAME" \
    --query "identity.principalId" \
    -o tsv)

  az role assignment create \
    --assignee-principal-type ServicePrincipal \
    --assignee-object-id "${VMPrincipalID}" \
    --role "Contributor" \
    --scope "/subscriptions/${subscription}"

  az role assignment list --assignee "${VMPrincipalID}"

  showstatusmsg "done"
}

function add_vm_permission_keyvault() {

  showmsg "Add VM principal ID permission to keyvault: $KEYVAULT"

  VMPrincipalID=$(az vm show \
    -g "$RG" \
    -n "$VMNAME" \
    --query "identity.principalId" \
    -o tsv)

  echo "$VMPrincipalID"

  az keyvault set-policy --resource-group "$RG" \
    --name "$KEYVAULT" \
    --object-id "$VMPrincipalID" \
    --key-permissions all \
    --secret-permissions all

  showstatusmsg "done"
}

function show_vm_access() {

  showmsginfo "CycleCloud access when cloud-init is done"
  ipaddress=$(az vm show -g "$RG" -n "$VMNAME" --query privateIps -d --out tsv)

  showmsginfo "CycleCloud via SSH: ssh [-i <privsshkey>] $ADMINUSER@$ipaddress"
  showmsginfo "CycleCloud via WEB: http://$ipaddress:8080"
}

function set_keyvault_secrets() {

  showmsg "Set keyvault secrets"

  az keyvault secret set --name ccpassword --vault-name "$KEYVAULT" --value "$CCPASSWORD" >/dev/null
  az keyvault secret set --name ccpubkey --vault-name "$KEYVAULT" --value "$CCPUBKEY" >/dev/null

  showstatusmsg "done"
}

function wait_cyclecloud() {

  if [ "$VPNVNETPEERED" == false ]; then
    showmsginfo "Cannot test cyclecloud access as no VPN peer was established"
    return 1
  fi

  set +e
  ccvmipaddress=$1
  pollingdelay=$2

  showmsg "Polling CycleCloud (VPN required). You can control-c at any time "

  while true; do
    gotaccess=$(eval "$SSHCMD" "$ADMINUSER"@"$ccvmipaddress" hostname >/dev/null 2>/dev/null)
    error=$?
    echo "error=$error"
    [[ "$error" == 0 ]] && break
    sleep "$pollingdelay"
    spinanim
  done

  showstatusmsg "done"
  set -e
}

function wait_scheduler() {

  set +e
  set -x
  ccvmipaddress=$1
  pollingdelay=$2

  showmsg "Polling cluster scheduler. This may take a while..."

  while true; do
    eval "$SSHCMD" "$ADMINUSER"@"$ccvmipaddress" 'cyclecloud show_nodes scheduler -c "$CLUSTERNAME" --states="Started" --output="%(Status)s" 2> /dev/null'
    schedulerstatus=$(eval "$SSHCMD" "$ADMINUSER"@"$ccvmipaddress" 'cyclecloud show_nodes scheduler -c "$CLUSTERNAME" --states="Started" --output="%\(Status\)s" 2> /dev/null')
    [[ "$schedulerstatus" == "Ready" ]] && break
    echo "schedulerstatus=$schedulerstatus"
    sleep "$pollingdelay"
    spinanim
  done

  if [[ "$schedulerstatus" == "Ready" ]]; then
    showstatusmsg "done"
    schedulerip=$(eval "$SSHCMD" "$ADMINUSER"@"$ccvmipaddress" 'cyclecloud show_nodes scheduler -c "$CLUSTERNAME" --states="Started" --output="%\(PrivateIp\)s" 2> /dev/null')
    showmsginfo "Scheduler via SSH: ssh [-i <privsshkey>] $ADMINUSER@$schedulerip"
  else
    showstatusmsg "failed"
  fi
  set -e
}

function wait_cluster_provision() {

  if [ "$VPNVNETPEERED" == false ]; then
    showmsginfo "Cannot test cyclecloud/cluster access as no VPN peer was established"
    return 1
  fi

  pollingdelay=10

  ccvmipaddress=$(az vm show -g "$RG" -n "$VMNAME" --query privateIps -d --out tsv 2>&1)

  wait_cyclecloud "$ccvmipaddress" "$pollingdelay"
  wait_scheduler "$ccvmipaddress" "$pollingdelay"
}

##############################################################################
# Main function calls
##############################################################################

[[ "$*" =~ -h|--help|-help ]] && echo "$0 <clustername>" && exit 0

echo ">> Logfile: $LOGFILE"

[[ "$#" == 1 ]] && echo ">> Cluster creation enabled: ${CLUSTERNAME:=$1}"

validate_secret_availability

echo ">> Start provisioning process"
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
wait_cyclecloud

[[ ! -z ${CLUSTERNAME-} ]] && wait_cluster_provision
