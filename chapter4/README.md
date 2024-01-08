## On regions, SKUs, quotas, and costs

This chapter is a bit different. It is not an end-to-end tutorial like the
others, but a set of pointers and commands about regions, SKUs, quotas, and
costs.

We have been provisioning VMs and specifying their SKUs. You may be wondering,
where you can find which SKUs are available, what their properties are, how many
can you get, how much they cost, etc.

*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>

---

<br>

Before we start, make sure you have azure cli installed and you are using the
right subscription:

```
az account set -n <subscription name or id>
```
and to double check you are in the right subscription:

```
az account show
```

### 1. Regions

In Azure, data centers are spread in multiple physical geographies, like USA,
Canda, Brazil, Africa, France, Japan, Australia, etc. Inside a geography you can
find regions. For instance, in USA geography you can have EastUs, WestUS,
South Central US, among other regions. In each region there are one to three
availability zones, which are separated groups of datacenters in a particular
region.

In this website you can find info about the geographies and regions:

<https://azure.microsoft.com/en-us/explore/global-infrastructure/geographies>

And here more info about availability zones:

<https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview>


To get the names of the regions using azure CLI:

```
az account list-locations -o table
```

Output will be something like:

```
DisplayName               Name                 RegionalDisplayName
------------------------  -------------------  -------------------------------------
East US                   eastus               (US) East US
East US 2                 eastus2              (US) East US 2
South Central US          southcentralus       (US) South Central US
...                       ...                  ...
```

### 2. SKUs


SKU, which stands for Stock Keeping Unit, is how a virtual machine size is called in Azure.


There are several SKUs in Azure to be selected for provisioning virtual
machines.


##### 2.1 SKU: Sizes

When selecting an SKU, one needs to understand the workload in which the virtual
machine will host/process. There are different SKUs, to exemplify:
- General purpose. Used for test and development, or small to medium data bases,
  web servers.
  - B, Dsv3, Dv3, Dasv4, Dav4, DSv2, ...
- GPU capability. Used for heavy graphic rendering or deep learning training.
  - NC, NCv2, NCv3, ND, NDv2, ...
- High Performance Computing. Most power CPU machines wth high-throughput network interfaces (RDMA).
  - HB, HBv2, HBv3, HBv4, HC, HX
- Compute intensive applications. Higher CPU-to-memory-ratio to support medium traffic web services and batch
  processes, AI inferencing.
  - Fsv2, FX
- Low-lantency disk access. Big Data, SQL, NoSQL databases, data warehousing, and large transactional databases.
  - Lsv3, Lasv3, Lsv2, ...
- Extended Memory.Relational databases, analytics services, large in memory
  workloads
  - Ev2, Eav4, Ev5, Mv2, ...

The following reference contains information about the SKU sizes:

<https://learn.microsoft.com/en-us/azure/virtual-machines/sizes>

Inside the link above, there are links to each group of SKU sizes, for instance:

- HPC SKUs: <https://learn.microsoft.com/en-us/azure/virtual-machines/sizes-hpc>
- GPU SKUs: <https://learn.microsoft.com/en-us/azure/virtual-machines/sizes-gpu>

The link below contains a VM selection advisor in which one can specify
information about the target workload, and options about SKUs are presented:
- VM Selector: <https://aka.ms/vm-selector>

If one wants to know the list of available SKUs, the following command can be
used:

```
az vm list-skus --location eastus --output table
```

##### 2.2 SKU: Naming

When selecting an SKU, one sees names such as `Standard_E16d_v5`,  `Standard_NC12s_v3`, and `Standard_HB176-48rs_v4`. These names specify details about the SKU size.

The major blocks of these names are:
```
[Family] +
[Sub-family] +
[# of vCPUs] +
[Constrained vCPUs] +
[Additive Features] +
[Accelerator Type] +
[Version]`
```

```
Additive Features:
a = AMD-based processor
b = Block Storage performance
d = diskful (that is, a local temp disk is present); this feature is for newer Azure VMs, see Ddv4 and Ddsv4-series
i = isolated size
l = low memory; a lower amount of memory than the memory intensive size
m = memory intensive; the most amount of memory in a particular size
p = ARM Cpu
t = tiny memory; the smallest amount of memory in a particular size
r = remote direct memory access (RDMA) connectivity
s = Premium Storage capable, including possible use of Ultra SSD (Note: some newer sizes without the attribute of s can still support Premium Storage, such as M128, M64, etc.)
C = Confidential
NP = node packing
Full description of the naming conventions can be found here:
```

<https://learn.microsoft.com/en-us/azure/virtual-machines/vm-naming-conventions>

Here is the link to describe about constrained vCPUs, which are VMs that have
a reduced number of cores but maintaining their original properties such as
memory size. One of the use cases for such constrained vCPUs is to save software
licensing costs, as some licenses are based on the number of cores a VM has.

<https://learn.microsoft.com/en-us/azure/virtual-machines/constrained-vcpu>


### 3. Quotas

Each subscription has an associated quota, which defines how many machines
/ cores of a given SKU can be rented per region.

To get the quota and its usage for all SKUs of a given region:

```
az vm list-usage --location <region> --out table
az vm list-usage --location eastus --out table
```

To get the usage and quota for a specific region and specific SKU


```
az vm list-usage --location <region> | grep <sku>
az vm list-usage --location centralus -o table  | grep "Standard HBv4"
az vm list-usage -l eastus -o table | grep "Name\b\|---\|HB\|NV\|NC"
```

You can use `az quota` command to manage (e.g. request new quota). See details
in the following url:

<https://learn.microsoft.com/en-us/cli/azure/quota?view=azure-cli-latest>


### 4. Costs

Details on costs can be found here:

<https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/>

There is also this site below which is not the official azure site but can be
helpful:

<https://azureprice.net/>

For costs, you can leverage the rest api from Microsoft Azure. Details of the
api can be found here:

<https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices>

In this website above, there is a code available in python to use the rest api,
with some hard coded values.

In this git folder, there is a slightly modified version of the code to obtain the cost
using the region and sku as arguments:

```
python3 get_price.py  westus3 Standard_HB120rs_v3
python3 get_price.py  canadacentral Standard_HC44rs
```

There is also another modified version you can look for price for linux machine
without being Low Priority or Spot and you can look for the sku name ignoreing
the case:

The `get_price.py` script has a few lines of code and can be easily modified to
explore more filters of the rest api.


```
python3 get_price_linux.py    westus3 standard_HB120rs_v3
```






### References

- Manage quota:
  <https://learn.microsoft.com/en-us/cli/azure/quota?view=azure-cli-latest>
- Retail price api:
  <https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices>
- Official price website: <https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/>
- Unofficial price website: <https://azureprice.net/>
- More on naming: <https://www.kenmuse.com/blog/mastering-azure-virtual-machines>
- SKU naming: <https://learn.microsoft.com/en-us/azure/virtual-machines/vm-naming-conventions>
- Constrained vCPUs: <https://learn.microsoft.com/en-us/azure/virtual-machines/constrained-vcpu>



