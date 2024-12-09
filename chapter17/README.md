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
supercomputing and AI/ML applications. The network cards for InfiniBand are
called a host channel adapters (HCAs).


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

It is also possible to do some RDMA local test using the following command:
```
$ run_perftest_loopback 0 1 ib_write_bw -s 1000
************************************
* Waiting for client to connect... *
************************************
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF          Device         : mlx5_ib0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF          Device         : mlx5_ib0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : ON
 ibv_wr* API     : ON
 CQ Moderation   : 100
 TX depth        : 128
 Mtu             : 4096[B]
 CQ Moderation   : 100
 Link type       : IB
 Mtu             : 4096[B]
 Max inline data : 0[B]
 Link type       : IB
 rdma_cm QPs     : OFF
 Max inline data : 0[B]
 Data ex. method : Ethernet
 rdma_cm QPs     : OFF
---------------------------------------------------------------------------------------
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0x29b QPN 0x013c PSN 0x5cd491 RKey 0x040500 VAddr 0x0055ae3cf1c000
 local address: LID 0x29b QPN 0x013b PSN 0xb8cbdb RKey 0x040600 VAddr 0x00560ad0c50000
 remote address: LID 0x29b QPN 0x013b PSN 0xb8cbdb RKey 0x040600 VAddr 0x00560ad0c50000
 remote address: LID 0x29b QPN 0x013c PSN 0x5cd491 RKey 0x040500 VAddr 0x0055ae3cf1c000
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MiB/sec]    BW average[MiB/sec]   MsgRate[Mpps]
 #bytes     #iterations    BW peak[MiB/sec]    BW average[MiB/sec]   MsgRate[Mpps]
Conflicting CPU frequency values detected: 1846.550000 != 2596.396000. CPU Frequency is not max.
 1000       5000             4104.91            4020.54              4.215846
---------------------------------------------------------------------------------------
 1000       5000             4104.91            4020.54              4.215846
---------------------------------------------------------------------------------------
```

Check firmware information

```
$ ethtool -i ib0
driver: mlx5_core[ib_ipoib]
version: 24.07-0.6.1
firmware-version: 20.31.1014 (MT_0000000223)
expansion-rom-version:
bus-info: 0101:00:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```


#### Exploring two nodes

To run a test with two VMs, provision a VM Scale Set (VMSS) in Azure. Tests
won't work provisioning two separate VMs
[LINK](https://learn.microsoft.com/en-us/azure/virtual-machines/setup-infiniband).


```
az vmss create -n myvmss1  \
               -g netto241206v1 \
               --image microsoft-dsvm:ubuntu-hpc:2204:latest\
               --vm-sku standard_hb120rs_v3  \
               --vnet-name netto241206v1VNET  \
               --subnet netto241206v1SUBNET  \
               --security-type '\''Standard'\''  \
               --public-ip-address '\'''\''  \
               --admin-username azureuser  \
               --instance-count 2  \
               --generate-ssh-keys
```

Once provisioned, you can for instance run a Send Latency Test

In the server machine run:

```
$ ib_send_lat --all --CPU-freq --iters=100000

************************************
* Waiting for client to connect... *
************************************
---------------------------------------------------------------------------------------
                    Send Latency Test
 Dual-port       : OFF          Device         : mlx5_ib0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : ON
 RX depth        : 512
 Mtu             : 4096[B]
 Link type       : IB
 Max inline data : 236[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0x439 QPN 0x012e PSN 0xb9aea2
 remote address: LID 0x43a QPN 0x012d PSN 0x3db11e
---------------------------------------------------------------------------------------
 #bytes #iterations    t_min[usec]    t_max[usec]  t_typical[usec]    t_avg[usec]    t_stdev[usec]   99% percentile[usec]   99.9% percentile[usec]
 2       100000          1.55           7.16         1.60              1.60             0.07            1.62                 3.49
 4       100000          1.55           7.23         1.58              1.59             0.06            1.62                 3.29
 8       100000          1.55           22.36        1.58              1.59             0.07            1.62                 3.22
 16      100000          1.55           21.41        1.58              1.59             0.07            1.62                 3.40
 32      100000          1.55           6.20         1.58              1.59             0.07            1.62                 3.43
 64      100000          1.62           6.18         1.65              1.65             0.07            1.69                 3.46
 128     100000          1.64           13.84        1.68              1.68             0.07            1.72                 3.52
 256     100000          2.08           18.54        2.12              2.13             0.10            2.17                 3.98
 512     100000          2.12           8.49         2.15              2.17             0.07            2.31                 3.87
 1024    100000          2.17           27.38        2.21              2.23             0.10            2.37                 4.04
 2048    100000          2.30           12.33        2.34              2.35             0.08            2.43                 4.22
 4096    100000          2.81           14.50        2.85              2.86             0.07            3.02                 4.44
 8192    100000          3.11           8.20         3.19              3.19             0.07            3.34                 5.03
 16384   100000          3.68           17.48        3.76              3.77             0.08            3.91                 5.57
...
```

In the client machine run:

```
$ ib_send_lat --all --CPU-freq   --iters=100000 $SERVER
---------------------------------------------------------------------------------------
                    Send Latency Test
 Dual-port       : OFF          Device         : mlx5_ib0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : ON
 TX depth        : 1
 Mtu             : 4096[B]
 Link type       : IB
 Max inline data : 236[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0x43a QPN 0x012d PSN 0x3db11e
 remote address: LID 0x439 QPN 0x012e PSN 0xb9aea2
---------------------------------------------------------------------------------------
 #bytes #iterations    t_min[usec]    t_max[usec]  t_typical[usec]    t_avg[usec]    t_stdev[usec]   99% percentile[usec]   99.9% percentile[usec]
 2       100000          1.55           7.17         1.60              1.60             0.09            1.62                 3.65
 4       100000          1.54           7.22         1.58              1.59             0.06            1.62                 3.27
 8       100000          1.55           22.40        1.58              1.59             0.07            1.62                 3.22
 16      100000          1.55           21.40        1.58              1.59             0.08            1.62                 3.40
 32      100000          1.55           6.20         1.58              1.59             0.07            1.62                 3.43
 64      100000          1.62           6.19         1.65              1.65             0.07            1.68                 3.47
 128     100000          1.65           13.83        1.68              1.68             0.07            1.72                 3.52
 256     100000          2.09           18.54        2.12              2.13             0.10            2.17                 3.98
 512     100000          2.12           8.49         2.16              2.17             0.07            2.31                 3.87
 1024    100000          2.17           27.38        2.21              2.23             0.10            2.37                 4.04
 2048    100000          2.30           12.34        2.34              2.35             0.08            2.43                 4.23
 4096    100000          2.81           14.48        2.85              2.86             0.07            3.02                 4.43
 8192    100000          3.11           8.18         3.19              3.19             0.07            3.34                 5.03
 16384   100000          3.68           17.45        3.76              3.77             0.08            3.92                 5.58
...
```


Similar, Send BW test can be run. On the server machine execute:

```
$ ib_send_bw --all --CPU-freq --iters=100000
 WARNING: BW peak won't be measured in this run.

************************************
* Waiting for client to connect... *
************************************
---------------------------------------------------------------------------------------
                    Send BW Test
 Dual-port       : OFF          Device         : mlx5_ib0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : ON
 RX depth        : 512
 CQ Moderation   : 100
 Mtu             : 4096[B]
 Link type       : IB
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0x439 QPN 0x012f PSN 0xe6be9b
 remote address: LID 0x43a QPN 0x012e PSN 0x53099c
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MiB/sec]    BW average[MiB/sec]   MsgRate[Mpps]
 2          100000           0.00               9.29                 4.869852
 4          100000           0.00               18.47                4.841161
 8          100000           0.00               37.35                4.894914
 16         100000           0.00               74.60                4.889038
 32         100000           0.00               149.31               4.892644
 64         100000           0.00               298.53               4.891084
 128        100000           0.00               596.10               4.883235
 256        100000           0.00               1189.91              4.873857
 512        100000           0.00               2370.48              4.854738
 1024       100000           0.00               4710.37              4.823419
 2048       100000           0.00               9303.36              4.763320
 4096       100000           0.00               18287.02             4.681478
 8192       100000           0.00               23539.34             3.013035
 16384      100000           0.00               23551.65             1.507306
....
```

On the client side, run:

```
$ ib_send_bw --all --CPU-freq   --iters=100000 10.31.0.7
 WARNING: BW peak won't be measured in this run.
---------------------------------------------------------------------------------------
                    Send BW Test
 Dual-port       : OFF          Device         : mlx5_ib0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : ON
 TX depth        : 128
 CQ Moderation   : 100
 Mtu             : 4096[B]
 Link type       : IB
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0x43a QPN 0x012e PSN 0x53099c
 remote address: LID 0x439 QPN 0x012f PSN 0xe6be9b
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MiB/sec]    BW average[MiB/sec]   MsgRate[Mpps]
 2          100000           0.00               9.29                 4.868276
 4          100000           0.00               18.46                4.840157
 8          100000           0.00               37.34                4.893924
 16         100000           0.00               74.59                4.888095
 32         100000           0.00               149.28               4.891664
 64         100000           0.00               298.46               4.889968
 128        100000           0.00               595.96               4.882103
 256        100000           0.00               1189.64              4.872746
 512        100000           0.00               2369.90              4.853561
 1024       100000           0.00               4709.34              4.822369
 2048       100000           0.00               9301.12              4.762171
 4096       100000           0.00               18282.39             4.680292
 8192       100000           0.00               23532.80             3.012198
 16384      100000           0.00               23547.97             1.507070
...
```


#### References

- [InfiniBand at Wikipedia](https://en.wikipedia.org/wiki/InfiniBand)
- [Introduction to InfiniBand](https://network.nvidia.com/pdf/whitepapers/IB_Intro_WP_190.pdf)
- [Azure: Set up InfiniBand](https://learn.microsoft.com/en-us/azure/virtual-machines/setup-infiniband)
- [InfiniBand Essentials Every HPC Expert Must Know, 2014](https://people.cs.pitt.edu/~jacklange/teaching/cs1652-f15/1_Mellanox.pdf)
- [InfiniBand Principles Every HPC Expert MUST Know (Part 1)](https://www.youtube.com/watch?v=wecZb5lHkXk)
- [InfiniBand Principles Every HPC Expert MUST Know (Part 2)](https://www.youtube.com/watch?v=Pgy4wAw6eEo)
- [27 Aug 18: Webinar: Introduction to InfiniBand Networks](https://www.youtube.com/watch?v=2gidd6lLiH8)
- [High-performance computing on InfiniBand enabled HB-seri\es and N-series VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/overview-hb-hc)
- [CERN. InfiniBand Linux
SW Stack, 2009](https://indico.cern.ch/event/218156/attachments/351726/490091/9_OFED_SW_stack.pdf)
- [CERN, Into to InfiniBand](https://indico.cern.ch/event/218156/attachments/351724/490088/Intro_to_InfiniBand.pdf)
- [How do a loop back test with single card installed?](https://forums.developer.nvidia.com/t/how-do-a-loop-back-test-with-single-card-installed/210070/1)
- [RDMA not working with ConnectX-6](https://forums.developer.nvidia.com/t/rdma-not-working-with-connectx-6/205913/3)
- [RedHat. Chapter 1. Introduction to InfiniBand and RDMA](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_infiniband_and_rdma_networks/understanding-infiniband-and-rdma_configuring-infiniband-and-rdma-networks)
- [Introduction to Programming Infiniband RDMA](https://insujang.github.io/2020-02-09/introduction-to-programming-infiniband/)
