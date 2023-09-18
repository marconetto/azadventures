#!/usr/bin/env bash


RG=mydemo
SKU=Standard_B2ms
VMIMAGE=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101
REGION=eastus

STORAGEACCOUNT="$RG"sa

VNETADDRESS=10.38.0.0

VPNRG=myvpnrg
VPNVNET=myvpnvnet

VMNAME="$RG"vm
VMVNETNAME="$RG"VNET
VMSUBNETNAME="$RG"SUBNET
ADMINUSER=azureuser

CLOUDINITFILE=cloudinit.file

function create_resource_group(){

    az group create --location $REGION \
                    --name $RG
}

function create_vnet_subnet(){

    az network vnet create -g $RG \
                           -n $VMVNETNAME \
                           --address-prefix "$VNETADDRESS"/16 \
                           --subnet-name $VMSUBNETNAME \
                           --subnet-prefixes "$VNETADDRESS"/24
}


function create_cloud_init(){

    if [ -z ${CCPASSWORD+x} ] ; then
        echo "CCPASSWORD: must be set and non-empty"
        exit
    fi
    if [ -z ${CCPUBKEY+x} ] ; then
        echo "CCPUBKEY: must be set and non-empty"
        exit
    fi

    account_info=$(az account show)

    azure_subscription_id=$(echo $account_info | jq -r '.id')
    azure_tenant_id=$(echo $account_info | jq -r '.tenantId')
    cyclecloud_subscription_name=$(echo $account_info | jq -r '.name')
    cyclecloud_admin_name=azureuser
    cyclecloud_storage_account=$STORAGEACCOUNT
    cyclecloud_storage_container=cyclecloud
    cyclecloud_location=$REGION
    cyclecloud_rg=$RG
    cyclecloud_admin_password=$CCPASSWORD
    cyclecloud_admin_public_key=$CCPUBKEY

cat << EOF > $CLOUDINITFILE

#cloud-config

runcmd:
  #
  # Install CycleCloud
  #
  - apt -y install wget gnupg2
  - wget -qO - https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
  - echo 'deb https://packages.microsoft.com/repos/cyclecloud bionic main' > /etc/apt/sources.list.d/cyclecloud.list
  - apt update
  - apt-get install -yq openjdk-8-jdk
  - update-java-alternatives -s java-1.8.0-openjdk-amd64
  - apt-get install -yq python3-venv
  - apt-get install -yq python3.8-venv
  - apt-get install -yq cyclecloud8=8.3.0-3062
  # Because /opt/cycle_server/config/ already exists, you need to force install
  - bash \`find /opt/cycle_server/.installer -maxdepth 1 -type d | grep '/opt/cycle_server/.installer/'\`/install.sh --force
  - /opt/cycle_server/cycle_server await_startup
  # Install CycleCloud CLI
  - unzip /opt/cycle_server/tools/cyclecloud-cli.zip -d /tmp
  - python3 /tmp/cyclecloud-cli-installer/install.py -y --installdir /home/${cyclecloud_admin_name}/.cycle --system
  # Separate command to avoid potential quote / double quote / var expansion troubles
  - cmd="/usr/local/bin/cyclecloud initialize --loglevel=debug --batch --url=http://localhost:8080 --verify-ssl=false --username=${cyclecloud_admin_name} --password='${cyclecloud_admin_password}'"
  # Must run as user or CycleCloud will attempt to install in /root/.cycle
  - runuser -l ${cyclecloud_admin_name} -c "\$cmd"
  - runuser -l ${cyclecloud_admin_name} -c '/usr/local/bin/cyclecloud account create -f /opt/cycle_server/azure_subscription.json'
  - rm -f /opt/cycle_server/config/data/cyclecloud_account.json.imported

write_files:
  - path: /opt/cycle_server/config/java_home
    content: |
      /usr/local/openjdk-8

  - path: /opt/cycle_server/config/data/cyclecloud_account.json
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
          "RawPassword": "${cyclecloud_admin_password}",
          "Superuser": true
        },
        {
          "AdType": "Credential",
          "CredentialType": "PublicKey",
          "Name": "${cyclecloud_admin_name}/public",
          "PublicKey": "${cyclecloud_admin_public_key}"
        },
        {
          "AdType": "Application.Setting",
          "Name": "cycleserver.installation.complete",
          "Value": true
        }
      ]

  - path: /opt/cycle_server/azure_subscription.json
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

EOF


}

function create_vm() {


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

}

function peer_vpn(){

    echo "Peering vpn with created vnet"

    curl https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh  -O

    bash ./create_peering_vpn.sh $VPNRG $VPNVNET $RG $VMVNETNAME
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
}

function add_vm_permission(){

    account_info=$(az account show)
    subscription=$(echo $account_info | jq -r '.id')

    VMPrincipalID=$(az vm show \
                             -g $RG \
                             -n "$VMNAME" \
                             --query "identity.principalId" \
                             -o tsv)
    az role assignment create \
          --assignee-principal-type ServicePrincipal \
          --assignee-object-id $VMPrincipalID \
          --role "Contributor" \
          --scope "/subscriptions/${subscription}"

    az role assignment list --assignee $VMPrincipalID

}

create_resource_group
create_vnet_subnet
peer_vpn
create_storage_account

create_cloud_init
create_vm
add_vm_permission
