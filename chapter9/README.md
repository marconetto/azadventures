## Create custom VM images (and use them via CLI/Terraform)

**GitHub Pages: [Here](https://marconetto.github.io/azadventures/chapter9/)**

The goal of this tutorial is to describe how to create a custom VM image from an
existing VM, and provision a new VM from this custom image using CLI.

Content of this git folder:
- [terra folder](https://github.com/marconetto/azadventures/tree/main/chapter9/terra): terraform scripts to provision VM with custom image



*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>
---


#### Definitions

A Virtual Machine (VM) image is a snapshot of a VM. It contains its operating
system, applications, configurations, etc.  that was captured at a given moment.
With this image, new VMs can be created that will be similar to that original
VM.

In Azure, one can configure a VM image to be either generalized or specialized.
VM image generalization is a process to remove machine and user specific
information from the VM (e.g. Unique System Identifiers, computer name, user
specific data, etc).

There are also different types of images:

- **Platform Images:** Azure provides a set of pre-built VM images that include
  various operating systems (Windows Server, various distributions of Linux),
  and sometimes additional software configurations like SQL Server or Visual
  Studio. These images are maintained and updated by Microsoft.

- **Marketplace Images:** Azure Marketplace offers a wide range of VM images
  provided by both Microsoft and third-party vendors. These images can include
  specialized software stacks, application servers, databases, and more. Users
  can select and deploy these images directly from the Azure Marketplace.

- **Custom Images:** Users can create custom VM images based on existing VMs in
  Azure. This allows users to capture and replicate VM configurations, including
  installed software, data, and settings. Here you can save your image in the
  azure image gallery in your subscription.


Shared Image Gallery: Azure Shared Image Gallery is a service that enables users to centrally manage and share custom VM images, including across different Azure Active Directory tenants. Shared Image Gallery simplifies image distribution and governance for organizations with complex deployment requirements.




In Azure, **VM image definitions** consist of three main fields:

- **Publisher:** The publisher represents the entity that created the VM image.
  They can be Microsoft, third-party vendors, or organizations.

- **Offer:** The offer specifies the category or type of VM image provided by
  the publisher. It further categorizes VM images based on the intended use or
  purpose. For example, Microsoft might offer High Performance Computing (HPC)
  offer, which would contain software related to HPC (example MPI, OpenMPI,
  network and accelerator drivers).

- **SKU (Stock Keeping Unit):** The SKU identifies a specific version or variant
  of the VM image within the offer. SKUs help distinguish between different
  configurations, editions, or versions of the same VM image. For instance,
  within the "WindowsServer" offer, there might be SKUs corresponding to
  different editions such as Standard, Datacenter, or specific release versions
  like 2016, 2019, etc.

Image definitions can also contain: recommended vCPUs, recommended memory, description, end of life date, and release notes.

A VM image also has a version, which allows one to track changes and manage updates to the VM image over time.

Example of **VM image identification**: `microsoft-dsvm:ubuntu-hpc:1804:18.04.2021051701`


In the Azure marketplace website you can find more info (such as pointers to
websites describing the VM images): <https://azuremarketplace.microsoft.com/en-us/marketplace/apps>




#### Basic commands and examples to list images

To obtain the list of all VM images (this command execution takes a while):

```
az vm image list --all --output table > bigtable.txt
```

To get the Ubuntu VM images for HPC:

```
az vm image list --publisher microsoft-dsvm --offer ubuntu-hpc --output table --all
```

```
Architecture    Offer       Publisher       Sku                Urn                                                           Version
--------------  ----------  --------------  -----------------  ------------------------------------------------------------  ----------------
x64             ubuntu-hpc  microsoft-dsvm  1804               microsoft-dsvm:ubuntu-hpc:1804:18.04.2021051701               18.04.2021051701
x64             ubuntu-hpc  microsoft-dsvm  1804               microsoft-dsvm:ubuntu-hpc:1804:18.04.2021110101               18.04.2021110101
x64             ubuntu-hpc  microsoft-dsvm  1804               microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101               18.04.2021120101
x64             ubuntu-hpc  microsoft-dsvm  1804               microsoft-dsvm:ubuntu-hpc:1804:18.04.2022061601               18.04.2022061601
x64             ubuntu-hpc  microsoft-dsvm  1804               microsoft-dsvm:ubuntu-hpc:1804:18.04.2022121201               18.04.2022121201
.
.
.
```

#### Create VM image from existing VM

Here we assume one has a VM already provisioned called `myoriginalvm` in
a resource group `myoriginalrg`.

Create resource group:

```
az group create --name mygalleryrg --location eastus
```

Create gallery:

```
az sig create --resource-group mygalleryrg --gallery-name mygallery
```

Get original VM id (this will get a string like
`"/subscriptions/xyz/resourceGroups/.../myoriginalvm"`):

```
ORIGINALVMID=$(az vm get-instance-view -g myoriginalrg -n myoriginalvm --query id)
```


The example below creates the VM image definition, containing publisher, offer,
SKU, for a linux, and using the VM image generalization process.

```
az sig image-definition create --resource-group mygalleryrg \
                               --gallery-name mygallery \
                               --gallery-image-definition myimagedef \
                               --publisher myimagepub \
                               --offer myimageoffer \
                               --sku myimagesku \
                               --os-type Linux \
                               --os-state Generalized \
                               --hyper-v-generation V2
```

The following command shows that the definition is there:

```
az sig image-definition list --gallery-name mygallery \
                             --resource-group mygalleryrg \
                             --output table
```

We need to generalize the VM before creating the generalized VM image.


Deprovision the VM by using the Azure VM agent to delete machine-specific files and data.

```
sudo waagent -deprovision+user -force
```

Turn off the VM (release its resources), while keeping the VM state stored:

```
az vm deallocate --resource-group myoriginalrg --name myoriginalvm
```

Mark VM as generalized

```
az vm generalize --resource-group myoriginalrg --name myoriginalvm
```

Then we create an actual VM image version:

```
az sig image-version create \
   --resource-group mygalleryrg \
   --gallery-name mygallery \
   --gallery-image-definition myimagedef \
   --gallery-image-version 1.0.0 \
   --target-regions "eastus" \
   --managed-image "/subscriptions/<subscriptionid>/resourceGroups/myoriginalrg/providers/Microsoft.Compute/virtualMachines/myoriginalvm"
```

#### Create VM from custom VM image using CLI


```
az group create --name myResourceGroup --location eastus
```

```
az vm create --resource-group myResourceGroup \
    --name mynewvm \
    --image "/subscriptions/<Subscription ID>/resourceGroups/mygalleryrg/providers/Microsoft.Compute/galleries/mygallery/images/myimagedef"
```


#### Create VM from custom VM image using Terraform

Inside this git folder you can find a subfolder called terra, which contains
code to provision a VM in azure using terraform. The code came from:
<https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform>


Inside the original `main.tf`, you would find something like:

```
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
```

The link below shows how to define the source image id in terraform:
<https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine.html#source_image_id>

To use the custom VM image, `main.tf` was modified to use the VM image from the
gallery defined above:

```
  source_image_id = "/subscriptions/<Subscription ID>/resourceGroups/mygalleryrg/providers/Microsoft.Compute/galleries/mygallery/images/myimagedef/versions/1.0.0"
```



Then:

```
terraform init -upgrade
terraform plan -out main.tfplan
terraform apply main.tfplan
```



## References

- **azure cli:**<br>
<https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt]>
- **tutorial linux custom images:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/linux/tutorial-custom-images>
- **specialized vs generalized images:**<br>
https://learn.microsoft.com/en-us/azure/virtual-machines/shared-image-galleries?tabs=azure-cli#generalized-and-specialized-images>
- **VM image definitions:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/shared-image-galleries?tabs=azure-cli#image-definitions>
- **Azure HPC images blog:**<br>
<https://techcommunity.microsoft.com/t5/azure-compute-blog/azure-hpc-vm-images/ba-p/977094>
- **Azure HPC image docs:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/configure#centos-hpc-vm-images>
- **azure marketplace:**<br>
<https://azuremarketplace.microsoft.com/en-us/marketplace/apps>
- **azure shared image gallery:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/shared-image-galleries>
- **troubleshooting shared image:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/troubleshooting-shared-images>
- **generalized azure VM:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/generalize>
- **provision vm with terraform:**<br>
<https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform>
