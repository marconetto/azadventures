### Notes on InfiniBand


#### Overview



InfiniBand (IB) is a cutting-edge computer networking standard tailored for
high-performance computing (HPC) environments, offering exceptional throughput
and ultra-low latency that far surpass general-purpose Ethernet. For instance,
its HDR (High Data Rate) and NDR (Next Data Rate) generations deliver 200 Gbps
and 400 Gbps per port, respectively. Unlike Ethernet, which typically has higher
latency and incurs CPU overhead, InfiniBand features hardware-level RDMA (Remote
Direct Memory Access), enabling near-zero CPU involvement for data transfers.
This ensures consistent, deterministic performance critical for HPC workloads.
Furthermore, its sub-microsecond latency, advanced congestion management, and
scalability across thousands of nodes make it the preferred choice for
supercomputing and AI/ML applications.


Here are the VM types (SKUs) which contain InfiniBand network in Azure:


- [HB Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hb-family): Designed for high-performance computing, these series
provide Mellanox InfiniBand interconnects with up to 200 Gbps bandwidth.

- [HC Series](https://learn.microsoft.com/en-us/azure/virtual-machines/hc-series-overview): Optimized for computationally intensive workloads, the HC series supports 100 Gbps InfiniBand connectivity.

- [ND Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nd-family): Targeted for AI and machine learning workloads, these SKUs include NVIDIA GPUs and leverage InfiniBand for fast inter-node communication.


#### Exploring single node


First, let's explore a few IB-related commands you can play with using a single VM in Azure.

Here, we assume the provisioned VM uses an [Azure HPC
image](https://github.com/Azure/azhpc-images), which contains all required
drivers---including Mellanox OFED (OpenFabrics Enterprise Distribution) / NVIDIA DOCA drivers---and tools to support InfiniBand.

First you will need to provision a VM.


Example of command assuming resource group and network have already been
provisioned:

```
$ az vm create -n vmnetto_6402 \
             -g netto241203v1 \
             --image microsoft-dsvm:ubuntu-hpc:2204:latest \
             --size standard_hb120rs_v3 \
             --vnet-name netto241203v1VNET \
             --subnet netto241203v1SUBNET \
             --security-type Standard \
             --public-ip-address '' \
             --admin-username azureuser \
             --generate-ssh-keys
```


Once the machine is provisioned here are a few things you can run.

Lists InfiniBand Host Channel Adapters (HCAs) recognized by the system.

```
$ lspci | grep -i infiniband
0101:00:00.0 Infiniband controller: Mellanox Technologies MT28908 Family [ConnectX-6 Virtual Function]
```

Displays details about InfiniBand devices, including port states and supported features.

```
$ ibv_devinfo
hca_id: mlx5_ib0
        transport:                      InfiniBand (0)
        fw_ver:                         20.31.1014
        node_guid:                      0015:5dff:fe33:ff56
        sys_image_guid:                 0c42:a103:00fb:517c
        vendor_id:                      0x02c9
        vendor_part_id:                 4124
        hw_ver:                         0x0
        board_id:                       MT_0000000223
        phys_port_cnt:                  1
                port:   1
                        state:                  PORT_ACTIVE (4)
                        max_mtu:                4096 (5)
                        active_mtu:             4096 (5)
                        sm_lid:                 549
                        port_lid:               958
                        port_lmc:               0x00
                        link_layer:             InfiniBand
```

Shows the status of InfiniBand devices, including port state, GUID, and link layer (IB or Ethernet).
```
$ ibstat
CA 'mlx5_ib0'
        CA type: MT4124
        Number of ports: 1
        Firmware version: 20.31.1014
        Hardware version: 0
        Node GUID: 0x00155dfffe33ff56
        System image GUID: 0x0c42a10300fb517c
        Port 1:
                State: Active
                Physical state: LinkUp
                Rate: 200
                Base lid: 958
                LMC: 0
                SM lid: 549
                Capability mask: 0x2659ec48
                Port GUID: 0x00155dfffd33ff56
                Link layer: InfiniBand
```

Confirms IB modules are loaded (e.g., ib_core, mlx5_core).

```
$ lsmod | grep -i ib
libcrc32c              16384  3 nf_conntrack,nf_nat,nf_tables
ib_ipoib              135168  0
ib_cm                 131072  2 rdma_cm,ib_ipoib
ib_umad                40960  0
mlx5_ib               450560  0
ib_uverbs             163840  2 rdma_ucm,mlx5_ib
ib_core               409600  8 rdma_cm,ib_ipoib,iw_cm,ib_umad,rdma_ucm,ib_uverbs,mlx5_ib,ib_cm
mlx5_core            2170880  1 mlx5_ib
mlx_compat             69632  11 rdma_cm,ib_ipoib,mlxdevm,iw_cm,ib_umad,ib_core,rdma_ucm,ib_uverbs,mlx5_ib,ib_cm,mlx5_core
```

Maps InfiniBand devices to the associated network devices. Also identifies the GUID of the local InfiniBand port.

```
$ ibdev2netdev
mlx5_ib0 port 1 ==> ib0 (Up)
```

Lists the available RDMA-capable devices on the system, such as InfiniBand or RoCE (RDMA over Converged Ethernet) devices, that are compatible with the libibverbs API.

```
$ ibv_devices
    device                 node GUID
    ------              ----------------
    mlx5_ib0            00155dfffe33ff56
```


Check the status of the InfiniBand (IB) stack and services on a system.
`/etc/init.d/openibd` is the init script that controls the InfiniBand daemon
(openibd). It manages the InfiniBand-related services, such as starting,
stopping, and checking the status of InfiniBand hardware and network interfaces.

```
$ /etc/init.d/openibd status
  HCA driver loaded

Configured IPoIB devices:
ib0

Currently active IPoIB devices:
Configured Mellanox EN devices:

Currently active Mellanox devices:
ib0

The following OFED modules are loaded:

  rdma_ucm
  rdma_cm
  ib_ipoib
  mlx5_core
  mlx5_ib
  ib_uverbs
  ib_umad
  ib_cm
  ib_core
  mlxfw
```



#### References

- [InfiniBand at Wikipedia](https://en.wikipedia.org/wiki/InfiniBand)
- [Introduction to InfiniBand](https://network.nvidia.com/pdf/whitepapers/IB_Intro_WP_190.pdf)
- [InfiniBand Essentials Every HPC Expert Must Know, 2014](https://people.cs.pitt.edu/~jacklange/teaching/cs1652-f15/1_Mellanox.pdf)
- [InfiniBand Principles Every HPC Expert MUST Know (Part 1)](https://www.youtube.com/watch?v=wecZb5lHkXk)
- [InfiniBand Principles Every HPC Expert MUST Know (Part 2)](https://www.youtube.com/watch?v=Pgy4wAw6eEo)
- [27 Aug 18: Webinar: Introduction to InfiniBand Networks](https://www.youtube.com/watch?v=2gidd6lLiH8)
- [High-performance computing on InfiniBand enabled HB-seri\es and N-series VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/overview-hb-hc)
