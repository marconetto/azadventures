## Single VM under private net accessed by bastion in Azure (jumpbox)

**GitHub Pages: [Here](https://marconetto.github.io/azadventures/chapter2/)**

This page contains instructions to create a single VM under a private network
that is accessed via a bastion service. This VM is known also as jumpbox.

Azure Bastion is a service maintained for you and is not part of the user VM.
An Azure Bastion deployment is per virtual network, not per
subscription/account or virtual machine.

<br>

**FILES**

- [create_bastion.sh](create_bastion.sh): CLI-based script to automate bastion+vm creation
- [setvars.sh](setvars.sh): helper script to setup variables to customize deployment
<br>

**DISCLAIMER.** This document is work-in-progress and my personal experience
performing this task.

<br>

---



### Usage

Modify `setvars.sh` to customize deployment variables (i.e. resource group, vnet, sku,..). Then:

```
source setvars.sh
```

After variables are setup:

```
./create_bastion.sh
```

The script will create the resource group, vnet, bastion and a VM (jumpbox). It will also create the `jumpboxaccess.sh` script, which contains a bash function to simplify the jupmpbox access.

```
source ./jumpboxaccess.sh
```

To access the jumpbox vm, just type:

```
sshjumpbox
```



### Behind the scenes

There are no highlight discussions on this topic so all required steps are in the `create_bastion.sh` script.


### Another way to connect to the jumpbox VM


##### OPTION 1
You can ignore the `jumpboxaccess.sh` script and run the steps manually:

```
VMID=`az vm show --name $VMNAME \
                 --resource-group $RG \
                 --query 'id'  \
                 --output tsv`

az network bastion ssh --name $BASTIONNAME \
                       --resource-group $RG \
                       --target-resource-id $VMID \
                       --auth-type ssh-key \
                       --username $ADMINUSER \
                       --ssh-key ~/.ssh/id_rsa
```

##### OPTION 2

Alternatively, first open a tunnel, for instance:

```
az network bastion tunnel --name mnettohpc1bastion \
                          --resource-group mnettohpc1 \
                          --target-resource-id $VMID \
                          --resource-port 22 \
                          --port 2200
```

then

```
ssh azureuser@127.0.0.1 -p 2200
```


##### OPTION 3

You can also establish the ssh connection using bastion ssh and then, once you
are in the vm, you can type ``~`` ``C``. This will open prompt: ``ssh>`` to add
the tunnel (using the same syntax you would add to the ssh commandline):

```
azureuser@vm01:~$
ssh> -L 2201:localhost:22
azureuser@vm01:~$
```

then in your machine:

```
ssh azureuser@127.0.0.1 -p 2201
```



#### Delete all resources
```
az group delete -n $RG \
                --force-deletion-types Microsoft.Compute/virtualMachines \
                --yes
```


### Problems

If you cannot connect to bastion+vm make sure there is no security rule in your
subscription.



## References

- bastion overview: <https://learn.microsoft.com/en-us/azure/bastion/bastion-overview>
- bastion overview: <https://azure.microsoft.com/en-us/products/azure-bastion>
- deploy bastion via cli: <https://learn.microsoft.com/en-us/azure/bastion/create-host-cli>
- bastion connection: <https://learn.microsoft.com/en-us/azure/bastion/connect-native-client-windows>
- escape characters: <https://man.openbsd.org/ssh#ESCAPE_CHARACTERS>
