## Run MPI jobs using Azure Batch + NFS

The goal of this tutorial is to demonstrate how to run
a Message Passing Interface (MPI) application using Azure Batch.

Azure Batch allows the creation of resources to run High Performance Computing
(HPC) applications. Different from Azure CycleCloud, it does not make use of
traditional job schedulers such as PBS, SLURM, LSF, etc. It has its own
resource/task manager/scheduler. It is possible to use Azure Batch for both
embarrassingly parallel and tightly coupled applications.


In this tutorial we will consider a setup that there is no public IP address to
access resources and that any access to resource pool is done via a VPN (or
jumpbox/bastion vm).


In a high level, the instructions will:

1. Provision storage account with fileshare and NFS
2. Provision batch service
3. Setup batch service pool
4. Create and submit a job/task to run a simple MPI application with two nodes.


In more details these are the major steps:

1. Create resource group, VNET, and SUBNET
2. Provision a VM for testing purposes
3. Peering VPN
4. Create storage account with NFS and private endpoint
5. Create batch account with user subscription allocation mode
6. Login into the batch account
7. Create pool with nfs support
8. Create batch job
9. Prepare MPI program into the storage
10. Submit MPI task


**FILES:**
- [mpi_batch.sh](mpi_batch.sh): automates all these steps and has some useful functions
- [compile.sh](compile.sh): compiles MPI source code and generates the mpirun
  script into the storage
- [mpi_show_hosts.c](mpi_show_hosts.c): MPI application source code



*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>

---

<br>

### Define a few variables

```
RG=advdemo
SKU=Standard_HB120-16rs_v3
VMIMAGE=OpenLogic:CentOS-HPC:7_9-gen2:7.9.2022040101
NODEAGENTSKUID="batch.node.centos 7"
REGION=eastus

STORAGEACCOUNT="$RG"sa
BATCHACCOUNT="$RG"ba
KEYVAULT="$RG"kv

STORAGEFILE=data

JSON_POOL=pool_nfs.json
JSON_TASK=task_mpi.json

VNETADDRESS=10.44.0.0

VPNRG=myvpn
VPNVNET=myvpnvnet

VMNAME="$RG"vm1
VMVNETNAME="$VMNAME"VNET
VMSUBNETNAME="$VMNAME"SUBNET
ADMINUSER=azureuser
DNSZONENAME="privatelink.file.core.windows.net"

POOLNAME=mpipool
JOBNAME=mpijob
```


### 1. Create resource group, VNET, and SUBNET

##### Create resource group

```
az group create --location $REGION \
                --name $RG
```

##### Create VNET and SUBNET


```
az network vnet create -g $RG \
                       -n $VMVNETNAME \
                       --address-prefix "$VNETADDRESS"/16 \
                       --subnet-name $VMSUBNETNAME \
                       --subnet-prefixes "$VNETADDRESS"/24
```


### 2. Provision a VM for testing purposes


```
az vm create -n $VMNAME \
          -g $RG \
          --image $VMIMAGE \
          --size $SKU \
          --vnet-name $VMVNETNAME \
          --subnet $VMSUBNETNAME \
          --public-ip-address "" \
          --admin-username $ADMINUSER \
          --generate-ssh-keys
private_ip=`az vm show -g $RG -n $VMNAME -d --query privateIps -otsv`
echo "Private IP of $VMNAME: ${private_ip}"
```

### 3. Peering VPN


```
curl https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh  -O
bash ./create_peering_vpn.sh $VPNRG $VPNVNET $RG $VMVNETNAME
```

A solution using jumpbox/bastion could be also used here.


### 4. Create storage account with NFS and private endpoint

Here we are gonna be using Azure file share

##### Create storage account

```
az storage account create \
--resource-group $RG \
--name $STORAGEACCOUNT \
--location $REGION \
--kind FileStorage \
--sku Premium_LRS \
--output none
```

##### Disable secure transfer is required for nfs support


```
az storage account update --https-only false \
   --name $STORAGEACCOUNT --resource-group $RG
```

##### Create a fileshare with NFS support

```
az storage share-rm create \
  --storage-account $STORAGEACCOUNT \
  --enabled-protocol NFS \
  --root-squash NoRootSquash \
  --name $STORAGEFILE \
  --quota 100
```

##### Get storage accound id and subnet id

```
storage_account_id=`az storage account show \
                  --resource-group $RG\
                  --name $STORAGEACCOUNT \
                  --query "id" -o tsv `
```

```
subnetid=`az network vnet subnet show \
      --resource-group $RG\
      --vnet-name $VMVNETNAME \
      --name $VMSUBNETNAME \
      --query "id" -o tsv `
```


##### Create private endpoint

```
endpoint=`az network private-endpoint create \
          --resource-group $RG\
          --name "$STORAGEACCOUNT-PrivateEndpoint" \
          --location $REGION \
          --subnet $subnetid \
          --private-connection-resource-id ${storage_account_id} \
          --group-id "file" \
          --connection-name "$STORAGEACCOUNT-Connection" \
          --query "id" -o tsv `
```


##### Create private dns

```
dns_zone=`az network private-dns zone create \
          --resource-group $RG \
          --name $DNSZONENAME \
          --query "id" -o tsv`
```

##### Get vnetid

```
vnetid=`az network vnet show \
  --resource-group $RG \
  --name $VMVNETNAME \
  --query "id" -o tsv`
```


##### Create private dns link to vnet

```
az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name $DNSZONENAME \
  --name "$VMVNETNAME-DnsLink" \
  --virtual-network $vnetid \
  --registration-enabled false
```

##### Get private endpoint nic and ip

```
endpoint_nic=`az network private-endpoint show \
  --ids $endpoint \
  --query "networkInterfaces[0].id" -o tsv `
```

```
endpoint_ip=`az network nic show \
  --ids ${endpoint_nic} \
  --query "ipConfigurations[0].privateIPAddress" -o tsv `
```

##### Create DNS record for the private endpoint


```
az network private-dns record-set a create \
        --resource-group $RG \
        --zone-name $DNSZONENAME \
        --name $STORAGEACCOUNT
```

```
az network private-dns record-set a add-record \
        --resource-group $RG \
        --zone-name $DNSZONENAME  \
        --record-set-name $STORAGEACCOUNT    \
        --ipv4-address ${endpoint_ip}
```

##### (optional) test nfs in the test vm

Inside the test VM (which can be access with ssh via vpn):

```
sudo mkdir /nfs ; sudo mount $STORAGEACCOUNT.file.core.windows.net:/$STORAGEACCOUNT/$STORAGEFILE /nfs/
```


### 5. Create batch account with user subscription allocation mode


To create a batch account with user subscription pool allocation mode, we need
to create a keyvault first. When using user subcription a new resource group is
automatically created to keep the resources visible in the user subscription.
This is different then batch service pool allocation mode which resources are
allocated in the batch service subscription itself.



##### Allow Azure Batch to access the subscription (one-time operation in
subscription).

```
az role assignment create --assignee ddbf3205-c6bd-46ae-8127-60eb93363864 --role contributor
```

##### Create keyvault


```
az keyvault create --resource-group $RG \
                   --name $KEYVAULT \
                   --location "$REGION" \
                   --enabled-for-deployment true \
                   --enabled-for-disk-encryption true \
                   --enabled-for-template-deployment true
```

```
az keyvault set-policy --resource-group $RG \
                       --name $KEYVAULT \
                       --spn ddbf3205-c6bd-46ae-8127-60eb93363864 \
                       --key-permissions all \
                       --secret-permissions all
```


##### Create batch account

```
az batch account create --resource-group $RG \
                        --name $BATCHACCOUNT \
                        --location "$REGION" \
                        --keyvault $KEYVAULT
```

Note you cannot use ``--storage-account $STORAGEACCOUNT`` as batch does not support storage account with fileshare to be link with it.



# --storage-account $STORAGEACCOUNT    # does not support azure fileshare


### 6. Login into the batch account


```
az batch account login \
     --name $BATCHACCOUNT \
     --resource-group $RG
```

### 7. Create pool with nfs support


We first create the json file that represents all required input, and then we
execute the command to create the pool.

```
# e.g.: VMIMAGE=OpenLogic:CentOS-HPC:7_9-gen2:7.9.2022040101
IFS=':' read -r publisher offer sku version <<< "$VMIMAGE"

nodeagent_sku_id=$(get_node_agent_sku)

read -r -d '' START_TASK << EOF
/bin/bash -c hostname ; env ; pwd
EOF

nfs_share_hostname="${STORAGEACCOUNT}.file.core.windows.net"
nfs_fileshare=${STORAGEFILE}
nfs_share_directory="/${STORAGEACCOUNT}/${nfs_fileshare}"

cat << EOF > $JSON_POOL
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

az batch pool create \
    --json-file $JSON_POOL
```

### 8. Create batch job

```
az batch job create \
    --id $JOBNAME \
    --pool-id $POOLNAME
```

### 9. Prepare MPI program into the storage

The following code will create a task to compile the MPI source code and to
create a script to execute the mpirun. The creation of the mpirun script is inside the
[compile.sh](compile.sh) script.


```
random_number=$((RANDOM % 9000 + 1000))

mpistuffurl='https://raw.githubusercontent.com/marconetto/azadventures/main/chapter10/compile.sh'
mpicodeurl='https://raw.githubusercontent.com/marconetto/azadventures/main/chapter10/mpi_show_hosts.c'

az batch task create \
    --task-id mpi-compile_${random_number} \
    --job-id $JOBNAME \
    --command-line "/bin/bash -c 'cd \$AZ_BATCH_NODE_MOUNTS_DIR/${STORAGEFILE} ; pwd ; wget -N -L $mpistuffurl ; wget -N -L $mpicodeurl ; chmod +x compile.sh ; ./compile.sh'"
```

### 10. Submit MPI task

```
random_number=$((RANDOM % 9000 + 1000))

taskid="mpirun_"$(random_number)

cat << EOF >  $JSON_TASK
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

```


### You can delete everything! :)

```
az group delete -g $RG
```


## References
- azure batch: https://learn.microsoft.com/en-us/azure/batch/
- batch + HPC: https://learn.microsoft.com/en-us/azure/batch/batch-technical-overview
- batch pool creation: https://learn.microsoft.com/en-us/azure/batch/batch-pool-create-event
- batch pool creation: https://learn.microsoft.com/en-us/rest/api/batchservice/pool/add?tabs=HTTP#request-body
- batch task creation:
  https://learn.microsoft.com/en-us/rest/api/batchservice/task/add?tabs=HTTP
- azure batch workshop: https://github.com/kaneuffe/azure-batch-workshop
- fileshare+nfs: https://learn.microsoft.com/en-us/azure/storage/files/storage-files-quick-create-use-linux
- batch+cli:
  https://github.com/Azure-Samples/azure-cli-samples/blob/master/batch
