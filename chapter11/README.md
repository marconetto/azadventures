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

1. Provision CycleCloud fully automated (plus setup of admin account and subscription enablement)
2. Provision the SLURM cluster in Cyclecloud
3. Submit a job/task to run a simple MPI application with two nodes.
4. Appendix: 1. Provision CycleCloud via marketplace: mix browser and CLI (traditional installation)


**FILES**
- [cyclecloud_cli.sh](cyclecloud_cli.sh): automates cylecloud installation



<br>

**DISCLAIMER.** This document is work-in-progress and my personal experience
performing this task.

---

<br>

##  Provision of CycleCloud (fully automated)

### 1. Define a few variables

Here you can create a file called ``variables.sh``, then execute ``source variables.sh``

You can also use ``export VAR=VALUE`` for variables such as ``CCPASSWORD`` and ``CCPUBKEY``.

```
RG=mydemo1
STORAGE_ACCOUNT="$RG"sa
VMNAME="$RG"vm

VPNRG=myvpnrg
VPNVNET=myvpnvnet

CCPASSWORD=content1
CCPUBKEY=pubsshkey
```

### 2. Run automation script to provision cyclecloud


```
./cyclecloud_cli.sh
```



## References
- azure cyclecloud: https://learn.microsoft.com/en-us/azure/cyclecloud/overview
- azure cyclecloud marketplace install: https://learn.microsoft.com/en-us/azure/cyclecloud/qs-install-marketplace?view=cyclecloud-8
- azure cyclecloud manual install: https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/install-manual?view=cyclecloud-8
- managed identities overview: https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview
- managed identity in cyclecloud: https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/managed-identities?view=cyclecloud-8
- cyclecloud terraform automation: https://github.com/yosoyjay/cyclecloud-llm/tree/main/cyclecloud
- cyclecloud bicep automation: https://techcommunity.microsoft.com/t5/azure-high-performance-computing/automate-the-deployment-of-your-cyclecloud-server-with-bicep/ba-p/3668769
- https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/running-in-locked-down-network?view=cyclecloud-8

## Appendix: 1. Provision CycleCloud via marketplace: mix browser and CLI (traditional installation)

##### 1 Go to market place and search for cyclecloud

Select cyclecloud version 8.4

Username can be kept azureuser

Select generate new ssh key pair or provide existing one

Select no public ip address (None) in network tab

Enable system assigned managed identity in management tab

##### 2 Peer vnet

After provisioning is done, we need a way to access the VM given it has no public ip address.

```
curl -LO https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_vpn.sh
bash ./create_peering_vpn.sh $VPNRG $VPNVNET $RG $VMNAME
```

##### 3 Create storage account required by cyclecloud

```
az storage account create \
          -n $STORAGE_ACCOUNT \
          -g $RG \
          --sku Standard_LRS
```

##### 4 Login into the ccportal and create administrator account

Open the web browser: ``https://<cyclecloudvmipaddress>/welcome``

For the administor user you can use the same admin user of the cyclecloud vm: azureuser

Paste public key. If you downloaded the key from azure (where $privkey and
$pubkey are the name of the input and output file):

```
chmod 600 $privkey
ssh-keygen -f $privkey -y > $pubkey
chmod 600 $pubkey
```


##### 5 Add access of the VM to the subscription

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

##### 6 Complete installation

Once access rights are configure, the validation of credential will work, just
add the storage account name and move ahead.




