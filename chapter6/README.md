## Auto and manual scaling in VM Scale Sets

The goal of this tutorial is to provision a VMSS and exercise both auto
and manual scaling. Auto-scaling is a key feature of cloud computing platforms
as it allows the computing capacity to be increased or decreased according to
a pre-defined policy.

Terminology:
- **Scaling up or vertical scaling:**  increase computing power of existing
- **Scaling out or horizontal scaling:**  add more resources to the original
  resource pool
- **Scaling down:** reduce computing power or number of resources from original
  resources / resource pool


In a high level, this is what the instructions will allow you to do:
1. Provision 1 VMSS with 2 VMs and enable autoscaling and autoscaling rules
3. Push load to the VMs to trigger scale out for a third VM
4. Let the third VM go away
5. Disable autoscaling and remove all instances of VMSS
5. Bring back 2 VMs using manual scaling and set autoscaling again


In more details these are the major steps:
1. Create resource group, VNET, and SUBNET
2. Peering jumpbox with VNET
3. Generate cloud-init file to automate installation of ``stress-ng`` (load
   generator)
4. Provision VMSS with two instances
5. Enable autoscaling and autoscaling rules
6. Generate load to trigger scale out for the third VM
7. See scale in and deletion of third VM
8. Disable auto-scaling / enable manual-scaling
9. Shutdown all VM instances with manual-scaling
10. Bring back two VMs plus auto-scaling


All these steps can be executed from your personal Linux machine OR in a linux
jumpbox VM inside azure.

**FILES:**
- ``vmss_scaling.sh``: automates all these steps and has some useful functions
- ``vmss_addload.sh``: automates load generation via ``stress-ng``

*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>

---

<br>

### Define a few variables

RG=demo1vmss1
SKU=Standard_DS1_v2


```
RG=demo1vmss1
SKU=Standard_DS1_v2
VMSSNAME=myScaleSet
REGION=eastus
VMSSADMINUSER=azureuser
VNETADDRESS=10.42.0.0

JUMPBOXRG=mnettobastion1
JUMPBOXVNET=mnettobastion1vnet1
JUMPBOXSUBNET=mnettobastion1subnet1

VMSSVNETNAME="$VMSSNAME"VNET
VMSSSUBNETNAME="$VMSSNAME"SUBNET
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
                       -n $VMSSVNETNAME \
                       --address-prefix "$VNETADDRESS"/16 \
                       --subnet-name $VMSSSUBNETNAME \
                       --subnet-prefixes "$VNETADDRESS"/24
```


### 2. Peering jumpbox with VNET

If you are doing this in the jumpbox/bastion VM, you may want to do some network
peering between the jumpbox and the VMSS vnet to be able to ssh into the VM
instances. If that is the case, please checkout the following url:

https://github.com/marconetto/azadventures/tree/main/chapter3/

You will basically do:

```
curl
https://raw.githubusercontent.com/marconetto/azadventures/main/chapter3/create_peering_bastion.sh  -O

bash ./create_peering_bastion.sh $JUMPBOXRG $JUMPBOXVNET $RG $VMSSVNET
```

### 3. Generate cloud-init file to automate installation of ``stress-ng``

The following code will generate ``cloud-init.txt``. This file defines a set of
instructions to be executed when VM instances are created. This is where we
install the load generator tool.

Further reading on cloud init can be found in references section of this
tutorial.


```
cat << EOF > cloud-init.txt
#cloud-config
package_upgrade: true
packages:
  - stress-ng
EOF
```

### 4. Provision VMSS with two instances

```
az vmss create \
  --resource-group $RG \
  --name $VMSSNAME \
  --image UbuntuLTS \
  --orchestration-mode Uniform \
  --instance-count 2 \
  --admin-username $VMSSADMINUSER \
  --generate-ssh-keys \
  --vnet-name $VMSSVNETNAME \
  --subnet $VMSSSUBNETNAME \
  --vm-sku $SKU \
  --public-ip-address "" \
  --custom-data cloud-init.txt
```

### 5. Enable autoscaling and autoscaling rules

##### First we need to create the autoscaling profile

```
az monitor autoscale create \
--resource-group $RG \
--resource $VMSSNAME \
--resource-type Microsoft.Compute/virtualMachineScaleSets \
--name autoscale \
--min-count 2 \
--max-count 10 \
--count 2
```

##### Then we say how/when scale out and scale in operations should happen


```
az monitor autoscale rule create \
   --resource-group $RG \
   --autoscale-name autoscale \
   --condition "Percentage CPU > 71 avg 5m" \
   --scale out 1

az monitor autoscale rule create \
   --resource-group $RG \
   --autoscale-name autoscale \
   --condition "Percentage CPU < 30 avg 5m" \
   --scale in 1
```


### 6. Generate load to trigger scale out for the third VM

There are many options to generate load in VMs to exercise auto-scaling. Here we
will use ``stress-ng`` to say what is the percentage of cpu utilization we want
to have in each VM instances for a given amount of time.

The script ``vmss_addload.sh`` automates this process of getting the VM
instances of the VMSS and ``ssh`` into them to trigger ``stress-ng``.

```
Usage: ./vmss_addload.sh -g <resourcegroup> -v <vmss> < -l <load in percentage> -d <duration in secs> | -k (kill) >
```

You can also kill ``stress-ng`` process in all VM instances using this tool.


#### NOTE on VM instance status info VERSUS ssh into VMs

Once the third VM provisioning is triggered, you will notice that after a while
you can actually ``ssh`` into the new VM but its status is still "Creating".
When the "Succeeded" status is reached it is when the VM is fully ready, that
is, all post provisioning (cloud init, custom scripts, azure extensions)
completed successfully. SSH service is started before this post provisioning
phase.

Here is how you see the status of the VMs:

```
az vmss list-instances --resource-group $RG \
                       --name $VMSSNAME \
                       --query "[].{Name:name, ProvisioningState:provisioningState}" --output table
```

Here is how to see VM private IPs:

```
VMS=$(az vmss list-instances \
  --resource-group $RG \
  --name $VMSSNAME \
  --query "[].{name:name}" --output tsv)
  IPS=$(az vmss nic list --resource-group $RG \
     --vmss-nam $VMSSNAME --query "[].ipConfigurations[].privateIPAddress" --output tsv)
 ARRAY_VMS=($VMS)
ARRAY_IPS=($IPS)
 for i in "${!ARRAY_VMS[@]}"; do
    printf "%s has private ip %s\n" "${ARRAY_VMS[i]}" "${ARRAY_IPS[i]}"
done
```


### 7. See scale in and deletion of third VM

After the load generator is completed, all VMs will have low utilization and the
third VM will be deleted. You can see that happening with the command in Step
8 that shows the status of the VMs.


### 8. Disable auto-scaling / enable manual-scaling


Let's say you want to switch off all instances of the VMSS for some
maintenance/testing.

Here is how you do it.

```
az monitor autoscale update --name autoscale \
               --resource-group $RG \
               --enabled false
```
#### 9. Shutdown all VM instances with manual-scaling

Then destroy all VM instances

```
az vmss delete-instances --instance-ids "*"\
                         --resource-group $RG \
                         --name $VMSSNAME
```



### 10. Bring back two VMs plus auto-scaling


You can bring back your original 2 VMs

```
az vmss scale --resource-group $RG \
             --name $VMSSNAME \
             --new-capacity 2
```

Then enable back autoscaling

```
az monitor autoscale update --name autoscale \
               --resource-group $RG \
               --enabled true
```


### You can delete everything! :)

```
az group delete -g $RG
```


## References

- auto-scaling rules cli: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/tutorial-autoscale-cli?tabs=Ubuntu
- vm provisioning states: https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing
- cloud init: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/tutorial-automate-vm-deployment
- cloud init: https://cloud-init.io/
- load generator stress-ng: https://github.com/ColinIanKing/stress-ng



## Appendix
#### SKU list

If you want to know the list of available SKUs, you can use the following
command:

```
az vm list-skus --location eastus --output table
```
