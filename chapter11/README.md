## Run MPI jobs using Azure CycleCloud + SLURM 

### (Work in Process)

<br>

**GOAL AND CONTEXT**

The goal of this tutorial is to demonstrate how to run
a Message Passing Interface (MPI) application using Azure Cycle Cloud.

Azure CycleCloud allows the creation of resources to run High Performance
Computing (HPC) applications. It allows the deployment of traditional job
schedulers such as PBS, SLURM, and LSF, etc.


<br>

**ORGANIZATION**

In a high level, the instructions will:

1. Provision CycleCloud fully automated (including setup of admin account and subscription access)
2. Provision the SLURM cluster in Cyclecloud
3. Submit a job/task to run a simple MPI application with two nodes.
4. Appendix: 1. Provision CycleCloud via marketplace: mix browser and CLI (traditional installation)


**ASSUMPTIONS**

- Cyclecloud will be used with no public address;
- A VPN is expected to be configured (see [https://marconetto.github.io/azadventures/chapter1/](https://marconetto.github.io/azadventures/chapter1/)


**FILES**
- [cyclecloud_cli.sh](cyclecloud_cli.sh): automates cyclecloud installation using Azure CLI



<br>

**DISCLAIMER.** This document is work-in-progress and my personal experience
performing this task.

---

<br>

##  Provision of CycleCloud

### 1. Define a few variables

The first lines of the automation script contain variables you may want to change.

```
RG=mydemo1
SKU=Standard_B2ms
VMIMAGE=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101
REGION=eastus

STORAGEACCOUNT="$RG"sa
KEYVAULT="$RG"kv

VNETADDRESS=10.38.0.0

VPNRG=myvpnrg
VPNVNET=myvpnvnet

VMNAME="$RG"vm
VMVNETNAME="$RG"VNET
VMSUBNETNAME="$RG"SUBNET
ADMINUSER=azureuser
```


In the automation process we also need two variables: ``CCPASSWORD`` and ``CCPUBKEY``.

These variables need to be setup, as they will be stored in key vault and collected by cloud-init when provisioning the cyclecloud VM.

During the execution of the automation script, you will be asked about these two variables if they are not set.
For ``CCPUBKEY``, it will try to get the key from ``$HOME/.ssh/id_rsa.pub``.

If you don't want any interaction when executing the automation you can simply do:

```
export CCPASSWORD=HelloMyPassword
export CCPUBKEY=$(cat ~/.ssh/id_rsa.pub)
```

<br>

### 2. Run automation script to provision cyclecloud


```
./cyclecloud_cli.sh
```

Depending on your setup, you need to switch on again your VPN client.

Once it is done you can login into the VM created in the browser after that using:

```
<VMCycleCloudIPAddress>:8080
```

<br>

<br>

## References
- azure cyclecloud: https://learn.microsoft.com/en-us/azure/cyclecloud/overview
- azure cyclecloud marketplace install: https://learn.microsoft.com/en-us/azure/cyclecloud/qs-install-marketplace?view=cyclecloud-8
- azure cyclecloud manual install: https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/install-manual?view=cyclecloud-8
- managed identities overview: https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview
- managed identity in cyclecloud: https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/managed-identities?view=cyclecloud-8
- cyclecloud terraform automation: https://github.com/yosoyjay/cyclecloud-llm/tree/main/cyclecloud
- cyclecloud bicep automation: https://techcommunity.microsoft.com/t5/azure-high-performance-computing/automate-the-deployment-of-your-cyclecloud-server-with-bicep/ba-p/3668769
- https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/running-in-locked-down-network?view=cyclecloud-8

<br>

<br>

---

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




