## Run MPI jobs using Azure Batch + NFS

The goal of this tutorial is to provision is to use Azure Batch to run
a Message Passing Interface (MPI) application.

Azure Batch allows the creation of resources to run High Performance Computing
(HPC) applications. Different from Azure CycleCloud, it does not have support to
traditional job schedulers such as PBS, SLURM, LSF, etc. It is possible to use
Azure Batch for both embarrassingly parallel and tightly coupled applications.


In this tutorial we will consider a setup that there is no public IP address to
access resources and that any access is done via a VPN (or jumpbox/bastion vm).


In a high level, the instructions will:

1. Provision storage account with fileshare and NFS
2. Provision batch service
3. Setup batch service pool
4. Create and submit a job/task to run a simple MPI application with two nodes.


In more details these are the major steps:

1. Create resource group, VNET, and SUBNET
2. Provision a VM for testing purposes
3. Peering VPN
4. Create storage account with NFS support using private endpoint
5. Create batch account with user subscription allocation mode
6. Login into the batch account
7. Create pool with nfs support
8. Create batch job
9. Prepare MPI program into the storage
10. Submit MPI task


**FILES:**

- ``mpi_batch.sh``: automates all these steps and has some useful functions
- compile.sh
[compile.sh:](compile.sh)
  https://raw.githubusercontent.com/marconetto/azadventures/main/chapter10/compile.sh


*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>

---

<br>

### Define a few variables


## References
- azure batch: https://learn.microsoft.com/en-us/azure/batch/
- batch + HPC: https://learn.microsoft.com/en-us/azure/batch/batch-technical-overview
- batch pool creation: https://learn.microsoft.com/en-us/azure/batch/batch-pool-create-event
- batch pool creation: https://learn.microsoft.com/en-us/rest/api/batchservice/pool/add?tabs=HTTP#request-body
- batch task creation:
  https://learn.microsoft.com/en-us/rest/api/batchservice/task/add?tabs=HTTP
- azure batch workshop: https://github.com/kaneuffe/azure-batch-workshop
