#!/usr/bin/env bash


RG=mydemo
SKU=Standard_B2ms
VMIMAGE=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101
CCIMAGE=azurecyclecloud:azure-cyclecloud:cyclecloud8:latest
REGION=eastus

STORAGEACCOUNT="$RG"sa

VNETADDRESS=10.38.0.0

VPNRG=myvpnrg
VPNVNET=myvpnvnet

VMNAME="$RG"vm
VMVNETNAME="$RG"VNET
VMSUBNETNAME="$RG"SUBNET
ADMINUSER=azureuser

KEYVAULT="$RG"kv

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


function create_keyvault(){

    az keyvault create --resource-group $RG \
                   --name $KEYVAULT \
                   --location "$REGION" \
                   --enabled-for-deployment true \
                   --enabled-for-disk-encryption true \
                   --enabled-for-template-deployment true
}


function create_cloud_init(){



    account_info=$(az account show)

    azure_subscription_id=$(echo $account_info | jq -r '.id')
    azure_tenant_id=$(echo $account_info | jq -r '.tenantId')
    cyclecloud_subscription_name=$(echo $account_info | jq -r '.name')
    cyclecloud_admin_name=azureuser
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
    - apt-get install -yq cyclecloud8=8.3.0-3062
    - escaped_CCPASSWORD=\$(printf '%s\n' "\$CCPASSWORD" | sed -e 's/[]\/\$*.^[]/\\\&/g')
    - escaped_CCPUBKEY=\$(printf '%s\n' "\$CCPUBKEY" | sed -e 's/[]\/\$*.^[]/\\\&/g')
    - sed -i "s/CCPASSWORD/\$escaped_CCPASSWORD/g" /tmp/cyclecloud_account.json
    - sed -i "s/CCPUBKEY/\$escaped_CCPUBKEY/g" /tmp/cyclecloud_account.json
    - mv /tmp/cyclecloud_account.json /opt/cycle_server/config/data/cyclecloud_account.json
    - /opt/cycle_server/cycle_server await_startup
    - unzip /opt/cycle_server/tools/cyclecloud-cli.zip -d /tmp
    - python3 /tmp/cyclecloud-cli-installer/install.py -y --installdir /home/${cyclecloud_admin_name}/.cycle --system
    - cmd="/usr/local/bin/cyclecloud initialize --loglevel=debug --batch --url=http://localhost:8080 --verify-ssl=false --username=${cyclecloud_admin_name} --password='\$CCPASSWORD'"
    - runuser -l ${cyclecloud_admin_name} -c "\$cmd"
    - mv /tmp/azure_subscription.json /opt/cycle_server/azure_subscription.json
    - runuser -l ${cyclecloud_admin_name} -c '/usr/local/bin/cyclecloud account create -f /opt/cycle_server/azure_subscription.json'
    - rm -f /opt/cycle_server/config/data/cyclecloud_account.json.imported

write_files:

  - path: /tmp/cyclecloud_account.json
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

  - path: /tmp/azure_subscription.json
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
          --assignee-object-id $VMPrincipalID \
          --role "Contributor" \
          --scope "/subscriptions/${subscription}"

    az role assignment list --assignee $VMPrincipalID

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
}

function get_password_manually(){

    unset CCPASSWORD
    echo -n "Enter password: "
    while IFS= read -p "$prompt" -r -s -n 1 char
    do
        if [[ $char == $'\0' ]] ; then
            break
        fi
        if [[ $char == $'\177' ]] ; then
            prompt=$'\b \b'
            CCPASSWORD="${CCPASSWORD%?}"
        else
            prompt='*'
            CCPASSWORD+="$char"
        fi
    done
    echo -e "\npassword=$CCPASSWORD"
}


function validate_secret_availability(){

    if [ -z ${CCPASSWORD+x} ] ; then
        echo "CCPASSWORD: must be set and non-empty"
        echo "Control-C to cancel and set CCPASSWORD in environment variable"
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
                echo "Happy for you! Will use this key!"
                CCPUBKEY=$(cat $PUBKEYFILE)
            else
                echo "Without CCPUBKEY I cannot continue..."
                exit
            fi
        fi
    else
        echo "Got CCPUBKEY from environment variable"
    fi

}


function set_keyvault_secrets(){

    az keyvault secret set --name ccpassword --vault-name $KEYVAULT --value "$CCPASSWORD" > /dev/null
    az keyvault secret set --name ccpubkey --vault-name $KEYVAULT --value "$CCPUBKEY" > /dev/null
}

validate_secret_availability

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
