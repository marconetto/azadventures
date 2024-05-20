#!/usr/bin/env bash

RG=advdemo
SKU=Standard_HB120-16rs_v3
VMIMAGE=almalinux:almalinux-hpc:8_6-hpc-gen2:latest
NODEAGENTSKUID="batch.node.el 8"
REGION=eastus

STORAGEACCOUNT="$RG"sa
BATCHACCOUNT="$RG"ba
KEYVAULT="$RG"kv

STORAGEFILE=data

JSON_POOL=pool_nfs.json
JSON_TASK=task_mpi.json

VNETADDRESS=10.36.0.0

VPNRG=myvpn
VPNVNET=myvpnvnet

VMNAMEPREFIX="$RG"vm
VMVNETNAME="$RG"VNET
VMSUBNETNAME="$RG"SUBNET
ADMINUSER=azureuser
DNSZONENAME="privatelink.file.core.windows.net"

POOLNAME=mpipool
JOBNAME=mpijob

function get_random_code() {

  random_number=$((RANDOM % 9000 + 1000))
  echo $random_number
}

function create_resource_group() {

  az group create --location $REGION \
    --name $RG
}

function create_vnet_subnet() {

  az network vnet create -g $RG \
    -n $VMVNETNAME \
    --address-prefix "$VNETADDRESS"/16 \
    --subnet-name $VMSUBNETNAME \
    --subnet-prefixes "$VNETADDRESS"/24
}

function create_vm() {

  echo "creating $VMNAME for testing"

  vmname="${VMNAMEPREFIX}_"$(get_random_code)

  FILE=/tmp/vmcreate.$$
  cat <<EOF >$FILE
#cloud-config

runcmd:
- echo "mounting shared storage on the vm"
- mkdir /nfs
- mount $STORAGEACCOUNT.file.core.windows.net:/$STORAGEACCOUNT/$STORAGEFILE /nfs/
EOF

  az vm create -n "$vmname" \
    -g $RG \
    --image $VMIMAGE \
    --size $SKU \
    --vnet-name $VMVNETNAME \
    --subnet $VMSUBNETNAME \
    --public-ip-address "" \
    --admin-username $ADMINUSER \
    --generate-ssh-keys \
    --custom-data $FILE

  private_ip=$(az vm show -g $RG -n "$vmname" -d --query privateIps -otsv)
  echo "Private IP of $vmname: ${private_ip}"
}

function peer_vpn() {

  echo "Peering vpn with created vnet"

  curl https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh -O

  bash ./create_peering_vpn.sh $VPNRG $VPNVNET $RG $VMVNETNAME
}

function get_subnetid() {

  subnetid=$(az network vnet subnet show \
    --resource-group $RG --vnet-name $VMVNETNAME \
    --name $VMSUBNETNAME \
    --query "id" -o tsv)

  echo "$subnetid"
}

function create_storage_account_files_nfs() {

  az storage account create \
    --resource-group $RG \
    --name $STORAGEACCOUNT \
    --location $REGION \
    --kind FileStorage \
    --sku Premium_LRS \
    --output none

  # disable secure transfer is required for nfs support
  az storage account update --https-only false \
    --name $STORAGEACCOUNT --resource-group $RG

  az storage share-rm create \
    --storage-account $STORAGEACCOUNT \
    --enabled-protocol NFS \
    --root-squash NoRootSquash \
    --name $STORAGEFILE \
    --quota 100

  storage_account_id=$(az storage account show \
    --resource-group $RG --name $STORAGEACCOUNT \
    --query "id" -o tsv)

  subnetid=$(get_subnetid)

  endpoint=$(az network private-endpoint create \
    --resource-group $RG --name "$STORAGEACCOUNT-PrivateEndpoint" \
    --location $REGION \
    --subnet "$subnetid" \
    --private-connection-resource-id "${storage_account_id}" \
    --group-id "file" \
    --connection-name "$STORAGEACCOUNT-Connection" \
    --query "id" -o tsv)

  dns_zone=$(az network private-dns zone create \
    --resource-group $RG \
    --name $DNSZONENAME \
    --query "id" -o tsv)

  vnetid=$(az network vnet show \
    --resource-group $RG \
    --name $VMVNETNAME \
    --query "id" -o tsv)

  az network private-dns link vnet create \
    --resource-group $RG \
    --zone-name $DNSZONENAME \
    --name "$VMVNETNAME-DnsLink" \
    --virtual-network "$vnetid" \
    --registration-enabled false

  endpoint_nic=$(az network private-endpoint show \
    --ids "$endpoint" \
    --query "networkInterfaces[0].id" -o tsv)

  endpoint_ip=$(az network nic show \
    --ids "${endpoint_nic}" \
    --query "ipConfigurations[0].privateIPAddress" -o tsv)

  az network private-dns record-set a create \
    --resource-group $RG \
    --zone-name $DNSZONENAME \
    --name $STORAGEACCOUNT

  az network private-dns record-set a add-record \
    --resource-group $RG \
    --zone-name $DNSZONENAME \
    --record-set-name $STORAGEACCOUNT \
    --ipv4-address "${endpoint_ip}"

  az storage share-rm list -g $RG \
    --storage-account $STORAGEACCOUNT

  echo "inside the test VM:"
  echo "sudo mkdir /nfs ; sudo mount $STORAGEACCOUNT.file.core.windows.net:/$STORAGEACCOUNT/$STORAGEFILE /nfs/"
}

function create_keyvault() {

  echo "Creating keyVault"

  az keyvault create --resource-group $RG \
    --name $KEYVAULT \
    --location "$REGION" \
    --enabled-for-deployment true \
    --enabled-for-disk-encryption true \
    --enabled-for-template-deployment true

  az keyvault set-policy --resource-group $RG \
    --name $KEYVAULT \
    --spn ddbf3205-c6bd-46ae-8127-60eb93363864 \
    --key-permissions all \
    --secret-permissions all
}

function create_batch_account_with_usersubscription() {

  # Allow Azure Batch to access the subscription (one-time operation).
  # az role assignment create --assignee ddbf3205-c6bd-46ae-8127-60eb93363864 --role contributor

  create_keyvault

  # Create the Batch account, referencing the Key Vault either by name (if they
  # exist in the same resource group) or by its full resource ID.
  echo "Creating batchAccount"
  az batch account create --resource-group $RG \
    --name $BATCHACCOUNT \
    --location "$REGION" \
    --keyvault $KEYVAULT
  # --storage-account $STORAGEACCOUNT    # does not support azure fileshare
}

function login_batch_with_usersubcription() {

  # Authenticate directly against the account for further CLI interaction.
  # Batch accounts that allocate pools in the user's subscription must be
  # authenticated via an Azure Active Directory token.

  echo "login into the batch account with user subscription"
  az batch account login \
    --name $BATCHACCOUNT \
    --resource-group $RG
}

function get_node_agent_sku() {

  # TODO: AUTOMATE
  echo "${NODEAGENTSKUID}"
}

function create_pool() {

  # e.g.: VMIMAGE=almalinux:almalinux-hpc:8_6-hpc-gen2:latest
  IFS=':' read -r publisher offer sku version <<<"$VMIMAGE"

  nodeagent_sku_id=$(get_node_agent_sku)

  read -r -d '' START_TASK <<EOF
/bin/bash -c hostname ; env ; pwd
EOF

  nfs_share_hostname="${STORAGEACCOUNT}.file.core.windows.net"
  nfs_fileshare=${STORAGEFILE}
  nfs_share_directory="/${STORAGEACCOUNT}/${nfs_fileshare}"
  subnetid=$(get_subnetid)

  cat <<EOF >$JSON_POOL
{
  "id": "$POOLNAME",
  "vmSize": "$SKU",
  "virtualMachineConfiguration": {
       "imageReference": {
            "publisher": "$publisher",
            "offer": "$offer",
            "sku": "$sku",
            "version": "$version"
        },
        "nodeAgentSkuId": "$nodeagent_sku_id"
    },
  "targetDedicatedNodes": 2,
  "enableInterNodeCommunication": true,
  "networkConfiguration": {
    "subnetId": "$subnetid",
    "publicIPAddressConfiguration": {
                "provision": "NoPublicIPAddresses"
            }
  },
  "taskSchedulingPolicy": {
    "nodeFillType": "Pack"
  },
  "targetNodeCommunicationMode": "simplified",
  "mountConfiguration": [
      {
          "nfsMountConfiguration": {
              "source": "${nfs_share_hostname}:/${nfs_share_directory}",
              "relativeMountPath": "$STORAGEFILE",
              "mountOptions": "-o rw,hard,rsize=65536,wsize=65536,vers=4,minorversion=1,tcp,sec=sys"
          }
      }
  ],
  "startTask": {
    "commandLine":"${START_TASK}",
    "userIdentity": {
        "autoUser": {
          "scope":"pool",
          "elevationLevel":"admin"
        }
    },
    "maxTaskRetryCount":1,
    "waitForSuccess":true
  }
}
EOF

  echo "create pool with nfs support"
  az batch pool create \
    --json-file $JSON_POOL
}

function create_job() {

  az batch job create \
    --id $JOBNAME \
    --pool-id $POOLNAME
}

function create_mpirun_task() {

  taskid="mpirun_"$(get_random_code)

  cat <<EOF >$JSON_TASK
{
  "id": "$taskid",
  "displayName": "mpi-task",
  "commandLine": "/bin/bash -c '\$AZ_BATCH_NODE_MOUNTS_DIR/data/run_mpi.sh'",
  "environmentSettings": [
    {
      "name": "NODES",
      "value": "2"
    },
    {
      "name": "PPN",
      "value": "2"
    }
  ],
  "userIdentity": {
    "autoUser": {
      "scope": "pool",
      "elevationLevel": "nonadmin"
    }
  },
  "multiInstanceSettings": {
    "coordinationCommandLine": "/bin/bash -c env",
    "numberOfInstances": 2,
    "commonResourceFiles": []
  }
}
EOF

  az batch task create \
    --job-id $JOBNAME \
    --json-file $JSON_TASK
}

function add_mpi_program_storage() {

  random_number=$(get_random_code)

  echo "add mpi program to storage account"

  mpistuffurl='https://raw.githubusercontent.com/marconetto/azadventures/main/chapter10/compile.sh'
  mpicodeurl='https://raw.githubusercontent.com/marconetto/azadventures/main/chapter10/mpi_show_hosts.c'

  az batch task create \
    --task-id mpi-compile_"${random_number}" \
    --job-id $JOBNAME \
    --command-line "/bin/bash -c 'cd \$AZ_BATCH_NODE_MOUNTS_DIR/${STORAGEFILE} ; pwd ; wget -N -L $mpistuffurl ; wget -N -L $mpicodeurl ; chmod +x compile.sh ; ./compile.sh'"
}

create_resource_group
create_vnet_subnet
peer_vpn
create_storage_account_files_nfs
create_vm
create_batch_account_with_usersubscription
login_batch_with_usersubcription
create_pool
create_job
add_mpi_program_storage
create_mpirun_task
