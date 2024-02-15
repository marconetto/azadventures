## CycleCloud Cluster with SLURM+EESSI+WRF using CLI

**GitHub Pages: [Here](https://marconetto.github.io/azadventures/chapter12/)**

In this tutorial we will explore the use of CycleCloud cluster templates and projects in order to run experiments for Weather Research & Forecasting (WRF) Model. Other applications can be used with some modifications.

Here is what we want to achieve:

1. Provision CycleCloud + SLURM cluster using only CLI
1. Auto setup EESSI to enable execution of WRF 3.9
1. Auto download Conus 2.5km data for running WRF benchmark
1. Auto setup three scheduler queues to explore three Azure SKUs



## USAGE



## BACKGROUND



### Overview: CycleCloud cluster templates, projects, cloud-init

When we provision CycleCloud cluster, we can choose which job scheduler the
cluster resources are managed by; which includes SLURM, PBS, and LSF. Such
clusters have a pre-defined list of job queues. If we want to provision
a cluster with some customizations, such as pre-download an application, change
job queues and resource types, add start up tasks, among others, we need to
those using what is called *cluster templates* and *projects*.

#### Cluster templates

Cluster templates define cluster configurations. You can specify the VM types of
cluster nodes, storage options, deployment region, network ports to access
a scheduler node, cluster partitions/queues, etc. All these can also be
parameterized, so a template can be used for multiple use cases.

The format of these cluster templates follow INI format. Further details can be found in both links:

```
[cluster]
  [[node, nodearray]]
    [[[volume]]]
    [[[network-interface]]]
    [[[cluster-init]]]
    [[[input-endpoint]]]
    [[[configuration]]]
[environment]
[noderef]
[parameters]
  [[parameters]]
    [[[parameter]]]
```


1. cyclecloud cluster templates [LINK 1](https://learn.microsoft.com/en-us/training/modules/customize-clusters-azure-cyclecloud/2-describe-templates)
1. cyclecloud cluster templates [LINK 2](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/cluster-templates?view=cyclecloud-8)

Here is an example of a cluster template for a SLURM cluster: [LINK](https://github.com/Azure/cyclecloud-slurm/blob/master/templates/slurm.txt)

#### Cluster projects

As mentioned earlier, cluster template defines configuration for the *overall*
cluster. Inside the template, you can define configurations for *nodes*, and
those are called CycleCloud *projects*. These projects contain *specs.* When
a node starts, CycleCloud configures it by processing and running a sequence of
specs. These specs can be python, shell, or powershell scripts. Think projects
are "cluster-init files", similar to "cloud-init" but they are executed once
nodes are ready (different from cloud-init, which is exectued before cyclecloud
processes are executed on the node).

Projects are used in the cluster templates with this following syntax:

```
[[[cluster-init <project>:<spec>:<project version>]]]
```

Here is a simplified view of a CycleCloud project:

```
\myproject
          ├── project.ini
          ├── templates
          ├── specs
          │   ├── default
          │     └── cluster-init
          │        ├── scripts
          │        ├── files
          │        └── tests
```

- **templates directory:** hold cluster templates
- **specs:** the specifications defining your project
- **scripts:** scripts executed in lexicographical order on the node
- **files:** raw data files to will be put on the node)
- **tests:** tests executed when a cluster is started in testing mode.

Here is the URL on how to create a project and additional functionalities of
cluster projects:
[LINK](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/projects?view=cyclecloud-8)


#### Cloud-init

CycleCloud also supports cloud-init, the configurations can be executed at the
first boot a VM performs, before any other CycleCloud specific configuration
occurs on the VM (such as installation of HPC schedulers). Cloud-init can be
used for configuring things such as networking, yum/apt mirrors, etc.

Further details can be found here: [LINK](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/cloud-init?view=cyclecloud-8)

```
[node scheduler]
CloudInit = '''#!/bin/bash
echo "cloud-init works" > /tmp/cloud-init.txt
'''
```


### Making WRF available on cluster nodes using EESSI


We can make WRF available through EESSI---European Environment for Scientific
Software Installations (EESSI, pronounced as "easy"). There are certain steps to
be executed in the cluster nodes to make WRF available for execution. We will
make use of cluster template and cyclecloud project files to get there.

There are several ways of doing so; let's see one of those ways:

#### Getting the original SLURM template

In your `$HOME` directory inside the CycleCloud VM:

```
EXISTING_TEMPLATE=$(sudo find /opt/cycle_server -iname "*slurm_template*txt")
NEW_TEMPLATE=newslurm.txt
sudo cp $EXISTING_TEMPLATE $NEW_TEMPLATE
sudo chown azureuser.azureuser $NEW_TEMPLATE
```

You can also get the template from git:

```
cyclecloud project fetch https://github.com/Azure/cyclecloud-slurm/releases/3.0.5 cc-slurm
NEW_TEMPLATE=cc-slurm/templates/slurm.txt
```

If you `diff` the two `NEW_TEMPLATE` the content should be exactly the same,
assuming you got the right release ID from your current CycleCloud installation.

#### Creating and uploading a CycleCloud project


```
LOCKER=`cyclecloud locker list | cut -d " " -f1`
echo $LOCKER | cyclecloud project init cc_eessi
```

Copy the new template to the user home directory:

```
cp $NEW_TEMPLATE $HOME/
```

Create file with this content `cc_eessi/specs/default/cluster-init/scripts/00_setup_eessi.sh`:
```
#!/usr/bin/env bash

# instructions from: https://www.eessi.io/docs/getting_access/native_installation
sudo apt-get install lsb-release
wget https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest_all.deb
sudo dpkg -i cvmfs-release-latest_all.deb
rm -f cvmfs-release-latest_all.deb
sudo apt-get update
sudo apt-get install -y cvmfs

wget https://github.com/EESSI/filesystem-layer/releases/download/latest/cvmfs-config-eessi_latest_all.deb
sudo dpkg -i cvmfs-config-eessi_latest_all.deb

sudo bash -c "echo 'CVMFS_CLIENT_PROFILE="single"' > /etc/cvmfs/default.local"
sudo bash -c "echo 'CVMFS_QUOTA_LIMIT=10000' >> /etc/cvmfs/default.local"

sudo cvmfs_config setup
```

Upload the project

```
cd cc_eessi/
cyclecloud project upload $LOCKER
cd ..
```

Let's create a second project so the scheduler downloads the WRF benchmark data
once the scheduler is provisioned.


```
LOCKER=`cyclecloud locker list | cut -d " " -f1`
echo $LOCKER | cyclecloud project init cc_wrfconus
```

Create file with this content `cc_wrfconus/specs/default/cluster-init/scripts/00_get_conus.sh`:


```
#!/usr/bin/env bash

curl -O https://www2.mmm.ucar.edu/wrf/users/benchmark/v3911/bench_12km.tar.bz2
tar jxvf bench_12km.tar.bz2
```



#### Updating and uploading a CycleCloud cluster template

Upload the cluster template:

```
cyclecloud import_template -f cc_eessi/templates/newslurm.txt
```

Once you modify `NEW_TEMPLATE`, you can import it by running:

Create project:


```
cyclecloud project upload
```


```
cyclecloud import_template -f $NEW_TEMPLATE
```



<br>

## References
1. azure cyclecloud:<br> <https://learn.microsoft.com/en-us/azure/cyclecloud/overview>
1. cyclecloud cluster templates (link 1):<br> <https://learn.microsoft.com/en-us/training/modules/customize-clusters-azure-cyclecloud/2-describe-templates>
1. cyclecloud cluster templates (link 2):<br> <https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/cluster-templates?view=cyclecloud-8>
1. cyclecloud projects: <br>
   <https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/projects?view=cyclecloud-8>
1. cyclecloud projects: <br> <https://learn.microsoft.com/en-us/training/modules/customize-clusters-azure-cyclecloud/5-customize-software-installations>
1. cyclecloud core concepts: <br>
   <https://learn.microsoft.com/en-us/azure/cyclecloud/concepts/core?view=cyclecloud-8>
1. SLURM cluster template: <br>
   <https://github.com/Azure/cyclecloud-slurm/blob/master/templates/slurm.txt>
1. cyclecloud cloud-init: <br>
   <https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/cloud-init?view=cyclecloud-8>
1. EESSI:<br>
<https://www.eessi.io/docs/getting_access/native_installation/>
1. EESSI+WRF on Azure: <br>
<https://easybuild.io/eum22/013_eum22_WRF_Azure_EESSI.pdf>
