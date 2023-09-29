## Provision CycleCloud + SLURM using CLI to run MPi jobs

<br>

**GOAL AND CONTEXT**

The goal of this tutorial is to demonstrate how to provision cyclecloud and a SLURM cluster using Azure CLI and Cyclecloud CLI.

Azure CycleCloud allows the creation of resources to run High Performance
Computing (HPC) applications. It allows the deployment of traditional job
schedulers such as PBS, SLURM, and LSF, etc.


<br>

**ORGANIZATION**

In a high level, the instructions will:

1. Provision CycleCloud fully automated (including setup of admin account and subscription access)
2. Provision the SLURM cluster in Cyclecloud
3. Appendix: 1. Provision CycleCloud via marketplace: mix browser and CLI (traditional installation)

<br>

**ASSUMPTIONS**

- Cyclecloud will be used with NO public address;
- A VPN is expected to be configured (see [https://marconetto.github.io/azadventures/chapter1/](https://marconetto.github.io/azadventures/chapter1/)
- If VPN is not configured, it is OK!  Leave `VPNRG` and `VPNVNET` unset. You will just not have a verification to see if cyclecloud is running and the slurm cluster is ready for job submission
- The automation was tested only with image ``microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101``
- All resources (cyclecloud, storage account, keyvault...) are in the same resource group
- Scheduler and compute node images are the default ones of the cyclecloud SLURM template: cycle.image.alma

<br>

**FILES**
- [git folder](https://github.com/marconetto/azadventures/tree/main/chapter11): git folder with the required files
- [cyclecloud_cli.sh](cyclecloud_cli.sh): automates cyclecloud installation using Azure CLI
- [setvars.sh](setvars.sh): sets variables to customize deployment



<br>

**DISCLAIMER.** This document is work-in-progress and my personal experience
performing this task.

---

<br>

##  Provision of CycleCloud

### 1. Define deployment variables

Modify `setvars.sh` to customize deployment variables, which are related names
of resource group, storage account, keyvault, among others. Type the following
command to setup the variables before deployment.

```
source setvars.sh
```

In the automation process we also need two variables: ``CCPASSWORD`` and ``CCPUBKEY``, which are not `setvars.sh`

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



This automation script contains the following major steps:
1. provision basic infrastructure (resource group, vnet, vnet peering with vpn, keyvault)
2. store admin password and public ssh key in keyvault
3. generate a cloud-init that will install cyclecloud when the cyclecloud vm is created
4. provision cyclecloud vm, setup admin password, setup subscription


```
./cyclecloud_cli.sh
```

Depending on your setup, you need to switch on again your VPN client.

Once it is done you can login into the VM created in the browser after that using:

```
<VMCycleCloudIPAddress>:8080
```



### 3. Run automation script to provision cyclecloud + slurm cluster

To provision the slurm cluster as well, just use the parameter `cluster` when calling the script. This will add more steps in the cloud-init file used to provision the cyclecloud VM. The cluster will be created based on the cyclecloud SLURM template. If VPN is setup, the script will poll cyclecloud to check when the cluster becomes ready to submit jobs via the cluster scheduler machine.

```
./cyclecloud_cli.sh cluster
```


### 4. Run automation script to provision cyclecloud + slurm cluster + mpi test code






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
- cyclecloud cluster templates: https://learn.microsoft.com/en-us/training/modules/customize-clusters-azure-cyclecloud/2-describe-templates
- cyclecloud projects: https://learn.microsoft.com/en-us/training/modules/customize-clusters-azure-cyclecloud/5-customize-software-installations

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




