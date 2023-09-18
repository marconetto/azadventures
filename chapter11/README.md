## Run MPI jobs using Azure CycleCloud + SLURM 

# (Work in Process)

<br>

**GOAL AND CONTEXT**

The goal of this tutorial is to demonstrate how to run
a Message Passing Interface (MPI) application using Azure Cycle Cloud.

Azure CycleCloud allows the creation of resources to run High Performance
Computing (HPC) applications. It allows the deployment of traditional job
schedulers such as PBS, SLURM, and LSF, etc.


<br>

**ORGANIZATION**

In this tutorial we will consider a setup that there is no public IP address to
access resources and that any access to resource pool is done via a VPN (or
jumpbox/bastion vm).


In a high level, the instructions will:

1. Provision CycleCloud via marketplace and some additional config using CLI
2. Provision CycleCloud fully automated (TBD)
3. Provision the SLURM cluster in Cyclecloud
4. Submit a job/task to run a simple MPI application with two nodes.


---

<br>

### Define a few variables

```
RG=mydemo1
STORAGE_ACCOUNT="$RG"sa
VMNAME="$RG"vm

VPNRG=myvpnrg
VPNVNET=myvpnvnet
```

### 1. CycleCloud via Azure Marketplace

##### 1.1 Go to market place and search for cyclecloud

Select cyclecloud version 8.4

Username can be kept azureuser

Select generate new ssh key pair or provide existing one

Select no public ip address (None) in network tab

Enable system assigned managed identity in management tab

##### 1.2 Peer vnet

After provisioning is done, we need a way to access the VM given it has no public ip address.

```
curl -LO https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh
bash ./create_peering_vpn.sh $VPNRG $VPNVNET $RG $VMNAME
```

##### 1.3 Create storage account required by cyclecloud

```
az storage account create \
          -n $STORAGE_ACCOUNT \
          -g $RG \
          --sku Standard_LRS
```

##### 1.4 Login into the ccportal and create administrator account

Open the web browser: ``https://<cyclecloudvmipaddress>/welcome``

For the administor user you can use the same admin user of the cyclecloud vm: azureuser

Paste public key. If you downloaded the key from azure (where $privkey and
$pubkey are the name of the input and output file):

```
chmod 600 $privkey
ssh-keygen -f $privkey -y > $pubkey
chmod 600 $pubkey
```


##### 1.5 Add access of the VM to the subscription

Still in the browser, a subscription configuration page in cyclecloud will open
and when trying to validate credentials it will fail.
Go back to the terminal and run the following commands:


```
VMPrincipalID=$(az vm show \
                         -g $RG \
                         -n "$HOST_VM_NAME" \
                         --query "identity.principalId" \
                         -o tsv)

az role assignment create \
      --assignee-principal-type ServicePrincipal \
      --assignee-object-id $VMPrincipalID \
      --role "Contributor" \
      --scope "/subscriptions/$SUBSCRIPTION"

az role assignment list --assignee $VMPrincipalID
```

##### 1.6 Complete installation

Once access rights are configure, the validation of credential will work, just
add the storage account name and move ahead.







<br>

**DISCLAIMER.** This document is work-in-progress and my personal experience
performing this task.


---

<br>

### You can delete everything! :)

```
az group delete -g $RG
```


## References
- azure cyclecloud: https://learn.microsoft.com/en-us/azure/cyclecloud/overview
- azure cyclecloud marketplace install: https://learn.microsoft.com/en-us/azure/cyclecloud/qs-install-marketplace?view=cyclecloud-8
- azure cyclecloud manual install: https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/install-manual?view=cyclecloud-8
- managed identities overview: https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview
- managed identity in cyclecloud: https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/managed-identities?view=cyclecloud-8
