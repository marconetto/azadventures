## Single VM under private net accessed by bastion in Azure


This is a step-by-step tutorial to create a single VM under a private network that
is accessed via a bastion.

All the steps are based on Azure CLI, and therefore can be fully automated.


Azure Bastion is a service maintained for you and is not part of the user VM. An
Azure Bastion deployment is per virtual network, not per subscription/account or
virtual machine.

Check out create_bastion.sh in this folder to automate vpn creation

*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

</br>

---

#### Create basic components (resource group, vnet and bastion subnet)

Create resource group:

```
az group create --name mnettohpc1 \
                --location EastUS
```

See the resource groups of your subscription:

```
az group list -o table
```

To delete the resource group, in case you want to give up now :)! You can use
the command below to delete everything once you are done with the tutorial.

```
az group delete -g mnettohpc1
```

Create a VNET. The default address space is: "10.0.0.0/16":

```
az network vnet create -g mnettohpc1 \
                       -n mnettohpc1vnet1 \
                       --address-prefix 10.201.0.0/20 \
                       --tags 'NRMSBastion=true'
```

Create subnet to place the VMs:

```
az network vnet subnet create -g mnettohpc1 \
                              -n mnettohpc1subnet1 \
                              --vnet-name mnettohpc1vnet1 \
                              --address-prefix 10.201.2.0/24
```

Create a virtual network and an Azure Bastion subnet, which needs to be
AzureBastionSubnet so Azure can know know which subnet to deploy the Bastion
resources to.

```
az network vnet subnet create -g mnettohpc1 \
                              -n AzureBastionSubnet \
                              --vnet-name mnettohpc1vnet1 \
                              --address-prefix 10.201.0.0/26
```

Create public IP for the bastion node:


```
az network public-ip create --resource-group mnettohpc1 \
                            --name mnettohpc1vnet1bastionpip \
                            --sku Standard \
                            --location eastus
```


Create bastion itself:

```
az network bastion create --name mnettohpc1bastion \
                          --public-ip-address mnettohpc1vnet1bastionpip \
                          --resource-group mnettohpc1 \
                          --vnet-name mnettohpc1vnet1 \
                          --location eastus \
                          --enable-tunneling
```

Enable tunneling in case you see this message when using bastion ssh: "Bastion Host SKU must be Standard and Native Client must be enabled"

```
az network bastion update --name mnettohpc2bastion1 \
                          --resource-group mnettohpc2 \
                          --enable-tunneling
```

### Provision VM

Provision your VM, with no public ip address, and configured to use your ssh key.

```
az vm create -n vm01 \
             -g mnettohpc1 \
             --image UbuntuLTS \
             --size Standard_DS1_v2 \
             --vnet-name mnettohpc1vnet1 \
             --subnet mnettohpc1subnet1 \
             --public-ip-address "" \
             --generate-ssh-keys
```

### Connect to existing VM in the vnet

Get vm id and connect to the vm ysing bastion ssh extension:
```
VMID=`az vm show --name vm01 \
                 --resource-group mnettohpc5 \
                 --query 'id'  \
                 --output tsv`

az network bastion ssh --name mnettohpc5bastion \
                       --resource-group mnettohpc5 \
                       --target-resource-id $VMID \
                       --auth-type ssh-key \
                       --username azureuser \
                       --ssh-key ~/.ssh/id_rsa
```

### Using local ssh client


First open a tunnel, for instance:

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

You can also establish the ssh connection using bastion ssh and then, once you
are in the vm, you can type ``~`` ``C``. This will open prompt: ``ssh>`` to add the tunnel (using the same syntax you would add to the ssh commandline):

```
azureuser@vm01:~$
ssh> -L 2201:localhost:22
azureuser@vm01:~$
```

then in your machine:

```
ssh azureuser@127.0.0.1 -p 2201
```



### Delete all resources
```
az group delete -n mnettohpc1 \
                --force-deletion-types Microsoft.Compute/virtualMachines \
                --yes
```


## Problems

If you cannot connect to bastion+vm make sure there is no security rule in your
subscription.



## References

- https://learn.microsoft.com/en-us/azure/bastion/create-host-cli
- https://learn.microsoft.com/en-us/azure/bastion/connect-native-client-windows
- https://man.openbsd.org/ssh#ESCAPE_CHARACTERS
- https://learn.microsoft.com/en-us/azure/bastion/bastion-overview
- https://azure.microsoft.com/en-us/products/azure-bastion
