### Notes on NCCL

<br>

#### Overview


NCCL (pronounced "Nickel") stands for NVIDIA Collective Communications Library.
It is a high-performance library developed by NVIDIA to handle multi-GPU and
multi-node communication, optimized for deep learning workloads. It is tightly
optimized for NVIDIA's GPU interconnects including NVLink, NVSwitch, PCIe, and
InfiniBand with GPUDirect RDMA.

Here are the VM types (SKUs) which contain GPU in Azure and can be used for NCCL
testing:

- [ND Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nd-family): Targeted for AI and machine learning workloads, these SKUs include NVIDIA GPUs and leverage InfiniBand for fast inter-node communication.

- [NC Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nc-series): Designed for compute-intensive GPU workloads, these SKUs feature NVIDIA GPUs and are well-suited for CUDA-accelerated applications, simulations, and rendering tasks. Later versions (like NCv3) support InfiniBand for multi-node scalability.

- [NG Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/ng-family): Designed for cloud gaming and remote desktop applications.

Note: [NV Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nv-family) has no NVLink and Infiniband, so it is not the focus for NCCL testing.


#### Single node test

Here is an example with:

```
VMIMAGE=microsoft-dsvm:ubuntu-hpc:2204:latest
SKU=Standard_NC12s_v3
```

Once you get a GPU-based VM, you can run the following command to see the GPUs.

```
lspci | grep -i nvidia
0001:00:00.0 3D controller: NVIDIA Corporation GV100GL [Tesla V100 PCIe 16GB] (rev a1)
0002:00:00.0 3D controller: NVIDIA Corporation GV100GL [Tesla V100 PCIe 16GB] (rev a1)
```

To use `nvidia-smi`, you may have to install NVIDIA drivers, as those are not
installed using the above (Azure HPC) image for NC series.

```
sudo apt update && sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers install
```

```
nvidia-smi
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.133.20             Driver Version: 570.133.20     CUDA Version: 12.8     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  Tesla V100-PCIE-16GB           Off |   00000001:00:00.0 Off |                  Off |
| N/A   29C    P0             24W /  250W |       0MiB /  16384MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   1  Tesla V100-PCIE-16GB           Off |   00000002:00:00.0 Off |                  Off |
| N/A   32C    P0             28W /  250W |       0MiB /  16384MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+
```


You can also check topology of the NVIDIA GPUs.

- `nvidia-smi`: This is the NVIDIA System Management Interface, a tool to interact with and query information about NVIDIA GPUs.

- `topo`: This specifies that you want to view the topology of the GPUs, which includes information about how GPUs are interconnected (e.g., via PCIe, NVLink, etc.).

- `-m`: Displays the GPUDirect communication matrix for the system.

```
nvidia-smi topo -m
        GPU0    GPU1    CPU Affinity    NUMA Affinity   GPU NUMA ID
GPU0     X      NODE    0-11    0               N/A
GPU1    NODE     X      0-11    0               N/A

Legend:

  X    = Self
  SYS  = Connection traversing PCIe as well as the SMP interconnect between NUMA nodes (e.g., QPI/UPI)
  NODE = Connection traversing PCIe as well as the interconnect between PCIe Host Bridges within a NUMA node
  PHB  = Connection traversing PCIe as well as a PCIe Host Bridge (typically the CPU)
  PXB  = Connection traversing multiple PCIe bridges (without traversing the PCIe Host Bridge)
  PIX  = Connection traversing at most a single PCIe bridge
  NV#  = Connection traversing a bonded set of # NVLinks
```

- *GPU0 / GPU1*: These refer to the two GPUs. The row and column labels are showing connections between the GPUs.

- *X (Self)*: It means the GPU is referencing itself (i.e., it's not connected to any other device for that direction).

- *NODE*: The connection between the two GPUs is within the same NUMA node (a group of CPUs and memory). It’s a high-bandwidth connection, typically over PCIe within the same physical node, where both GPUs share the same memory space.

- *CPU Affinity (0-11)*: This shows which CPU cores are associated with the GPUs. In this case, 0-11 means that both GPUs are linked to the same set of 12 CPU cores.

- *NUMA Affinity (0)*: Both GPUs are in the same NUMA node (NUMA node 0).

- *GPU NUMA ID (N/A)*: This means the GPU NUMA ID is not applicable in this VM. This typically happens when the VM has only one NUMA node or the GPUs are not distinguished by specific NUMA IDs.


In the Azure HPC image, `nccle-tests` is already installed and can be found
here: `/opt/nccl-tests`

Go to that directory and run (for single GPU):

```
./build/all_reduce_perf -b 8 -e 2048M -f 2 -g 1
# nThread 1 nGpus 1 minBytes 8 maxBytes 2147483648 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid  55295 on vmnetto9831 device  0 [0x00] Tesla V100-PCIE-16GB
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1     4.45    0.00    0.00      0     0.27    0.03    0.00      0
          16             4     float     sum      -1     4.17    0.00    0.00      0     0.26    0.06    0.00      0
          32             8     float     sum      -1     6.80    0.00    0.00      0     0.26    0.12    0.00      0
          64            16     float     sum      -1     4.18    0.02    0.00      0     0.26    0.25    0.00      0
         128            32     float     sum      -1     4.26    0.03    0.00      0     0.26    0.49    0.00      0
         256            64     float     sum      -1     4.26    0.06    0.00      0     0.26    1.00    0.00      0
         512           128     float     sum      -1     4.47    0.11    0.00      0     0.26    2.01    0.00      0
        1024           256     float     sum      -1     4.26    0.24    0.00      0     0.26    4.02    0.00      0
        2048           512     float     sum      -1     4.28    0.48    0.00      0     0.26    8.03    0.00      0
        4096          1024     float     sum      -1     4.23    0.97    0.00      0     0.26   16.06    0.00      0
        8192          2048     float     sum      -1     4.24    1.93    0.00      0     0.25   32.13    0.00      0
       16384          4096     float     sum      -1     4.27    3.84    0.00      0     0.26   64.25    0.00      0
       32768          8192     float     sum      -1     4.14    7.91    0.00      0     0.25  128.53    0.00      0
       65536         16384     float     sum      -1     4.22   15.53    0.00      0     0.26  252.06    0.00      0
      131072         32768     float     sum      -1     4.50   29.13    0.00      0     0.27  494.61    0.00      0
      262144         65536     float     sum      -1     4.40   59.58    0.00      0     0.27  989.22    0.00      0
      524288        131072     float     sum      -1     4.28  122.36    0.00      0     0.26  2016.88    0.00      0
     1048576        262144     float     sum      -1     5.28  198.41    0.00      0     0.26  4032.98    0.00      0
     2097152        524288     float     sum      -1     7.50  279.44    0.00      0     0.27  7913.78    0.00      0
     4194304       1048576     float     sum      -1    12.92  324.52    0.00      0     0.27  15534.46    0.00      0
     8388608       2097152     float     sum      -1    22.94  365.69    0.00      0     0.27  31655.12    0.00      0
    16777216       4194304     float     sum      -1    43.50  385.70    0.00      0     0.26  64527.75    0.00      0
    33554432       8388608     float     sum      -1    84.14  398.80    0.00      0     0.26  129055.51    0.00      0
    67108864      16777216     float     sum      -1    165.5  405.52    0.00      0     0.26  258111.02    0.00      0
   134217728      33554432     float     sum      -1    328.0  409.19    0.00      0     0.26  516222.03    0.00      0
   268435456      67108864     float     sum      -1    652.9  411.15    0.00      0     0.27  1012963.98    0.00      0
   536870912     134217728     float     sum      -1   1305.6  411.20    0.00      0     0.26  2064888.12    0.00      0
  1073741824     268435456     float     sum      -1   2605.4  412.12    0.00      0     0.27  4051855.94    0.00      0
  2147483648     536870912     float     sum      -1   5206.2  412.49    0.00      0     0.29  7535030.34    0.00      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 0
#
```

Now with two GPUs on the same node:

```
./build/all_reduce_perf -b 8 -e 2048M -f 2 -g 2
# nThread 1 nGpus 2 minBytes 8 maxBytes 2147483648 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid  55353 on vmnetto9831 device  0 [0x00] Tesla V100-PCIE-16GB
#  Rank  1 Group  0 Pid  55353 on vmnetto9831 device  1 [0x00] Tesla V100-PCIE-16GB
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1    10.91    0.00    0.00      0    11.51    0.00    0.00      0
          16             4     float     sum      -1    10.63    0.00    0.00      0    10.67    0.00    0.00      0
          32             8     float     sum      -1    10.61    0.00    0.00      0    10.62    0.00    0.00      0
          64            16     float     sum      -1    10.68    0.01    0.01      0    10.90    0.01    0.01      0
         128            32     float     sum      -1    11.22    0.01    0.01      0    11.38    0.01    0.01      0
         256            64     float     sum      -1    10.78    0.02    0.02      0    10.50    0.02    0.02      0
         512           128     float     sum      -1    11.42    0.04    0.04      0    10.77    0.05    0.05      0
        1024           256     float     sum      -1    12.75    0.08    0.08      0    10.97    0.09    0.09      0
        2048           512     float     sum      -1    11.67    0.18    0.18      0    11.32    0.18    0.18      0
        4096          1024     float     sum      -1    11.97    0.34    0.34      0    11.73    0.35    0.35      0
        8192          2048     float     sum      -1    12.79    0.64    0.64      0    12.75    0.64    0.64      0
       16384          4096     float     sum      -1    15.34    1.07    1.07      0    15.12    1.08    1.08      0
       32768          8192     float     sum      -1    21.09    1.55    1.55      0    21.19    1.55    1.55      0
       65536         16384     float     sum      -1    32.84    2.00    2.00      0    32.71    2.00    2.00      0
      131072         32768     float     sum      -1    49.32    2.66    2.66      0    48.54    2.70    2.70      0
      262144         65536     float     sum      -1    71.46    3.67    3.67      0    68.89    3.81    3.81      0
      524288        131072     float     sum      -1    106.5    4.92    4.92      0    105.2    4.98    4.98      0
     1048576        262144     float     sum      -1    181.1    5.79    5.79      0    179.6    5.84    5.84      0
     2097152        524288     float     sum      -1    329.4    6.37    6.37      0    327.2    6.41    6.41      0
     4194304       1048576     float     sum      -1    632.5    6.63    6.63      0    629.7    6.66    6.66      0
     8388608       2097152     float     sum      -1   1233.2    6.80    6.80      0   1239.2    6.77    6.77      0
    16777216       4194304     float     sum      -1   2460.4    6.82    6.82      0   2457.8    6.83    6.83      0
    33554432       8388608     float     sum      -1   4882.6    6.87    6.87      0   4911.1    6.83    6.83      0
    67108864      16777216     float     sum      -1   9761.2    6.88    6.88      0   9779.0    6.86    6.86      0
   134217728      33554432     float     sum      -1    19527    6.87    6.87      0    19472    6.89    6.89      0
   268435456      67108864     float     sum      -1    39061    6.87    6.87      0    38985    6.89    6.89      0
   536870912     134217728     float     sum      -1    77947    6.89    6.89      0    77924    6.89    6.89      0
  1073741824     268435456     float     sum      -1   156007    6.88    6.88      0   155884    6.89    6.89      0
  2147483648     536870912     float     sum      -1   312034    6.88    6.88      0   311620    6.89    6.89      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 3.37715
#


```


You can also use MPI:

```
module load mpi/hpcx

export NCCL_DEBUG=INFO
export NCCL_P2P_LEVEL=NVL
export CUDA_VISIBLE_DEVICES=0,1

mpirun -np 2 \
  -H localhost:2 \
  -bind-to none -map-by slot \
  -x NCCL_DEBUG -x LD_LIBRARY_PATH -x PATH -x CUDA_VISIBLE_DEVICES \
  ./build/all_reduce_perf -b 8 -e 2048M -f 2 -g 1

```

- *-np 2*: 2 processes, one per GPU

- *-H localhost:2*: run 2 processes on local machine

- *-g 1*: one GPU per process

- *-b 8 -e 512M*: buffer size range (begin, end)

Example of output:

```
# nThread 1 nGpus 1 minBytes 8 maxBytes 2147483648 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid  55805 on vmnetto9831 device  0 [0x00] Tesla V100-PCIE-16GB
#  Rank  1 Group  0 Pid  55806 on vmnetto9831 device  1 [0x00] Tesla V100-PCIE-16GB
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1    11.05    0.00    0.00      0    10.91    0.00    0.00      0
          16             4     float     sum      -1    10.83    0.00    0.00      0    10.58    0.00    0.00      0
          32             8     float     sum      -1    11.41    0.00    0.00      0    11.24    0.00    0.00      0
          64            16     float     sum      -1    11.26    0.01    0.01      0    11.15    0.01    0.01      0
         128            32     float     sum      -1    11.95    0.01    0.01      0    11.36    0.01    0.01      0
         256            64     float     sum      -1    11.36    0.02    0.02      0    11.27    0.02    0.02      0
         512           128     float     sum      -1    11.38    0.04    0.04      0    11.44    0.04    0.04      0
        1024           256     float     sum      -1    11.58    0.09    0.09      0    11.73    0.09    0.09      0
        2048           512     float     sum      -1    12.41    0.16    0.16      0    12.10    0.17    0.17      0
        4096          1024     float     sum      -1    12.68    0.32    0.32      0    12.40    0.33    0.33      0
        8192          2048     float     sum      -1    14.28    0.57    0.57      0    13.98    0.59    0.59      0
       16384          4096     float     sum      -1    15.94    1.03    1.03      0    15.91    1.03    1.03      0
       32768          8192     float     sum      -1    22.45    1.46    1.46      0    22.62    1.45    1.45      0
       65536         16384     float     sum      -1    34.72    1.89    1.89      0    34.68    1.89    1.89      0
      131072         32768     float     sum      -1    50.87    2.58    2.58      0    49.89    2.63    2.63      0
      262144         65536     float     sum      -1    71.13    3.69    3.69      0    71.17    3.68    3.68      0
      524288        131072     float     sum      -1    110.4    4.75    4.75      0    110.4    4.75    4.75      0
     1048576        262144     float     sum      -1    187.0    5.61    5.61      0    186.7    5.62    5.62      0
     2097152        524288     float     sum      -1    339.7    6.17    6.17      0    338.5    6.20    6.20      0
     4194304       1048576     float     sum      -1    690.1    6.08    6.08      0    643.9    6.51    6.51      0
     8388608       2097152     float     sum      -1   1264.0    6.64    6.64      0   1262.2    6.65    6.65      0
    16777216       4194304     float     sum      -1   2506.6    6.69    6.69      0   2506.7    6.69    6.69      0
    33554432       8388608     float     sum      -1   4998.0    6.71    6.71      0   4995.7    6.72    6.72      0
    67108864      16777216     float     sum      -1   9966.8    6.73    6.73      0   9966.2    6.73    6.73      0
   134217728      33554432     float     sum      -1    19921    6.74    6.74      0    19926    6.74    6.74      0
   268435456      67108864     float     sum      -1    39867    6.73    6.73      0    39849    6.74    6.74      0
   536870912     134217728     float     sum      -1    79712    6.74    6.74      0    79704    6.74    6.74      0
  1073741824     268435456     float     sum      -1   159411    6.74    6.74      0   159384    6.74    6.74      0
  2147483648     536870912     float     sum      -1   318760    6.74    6.74      0   318732    6.74    6.74      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 3.28316
#
```


<br>
<br>

#### References

- [Azure Run NCCL tests](https://learn.microsoft.com/en-us/samples/azure/azureml-examples/run-nccl-tests-on-gpu-to-check-performance-and-configuration/)
- [Azure CycleCloud + container + NCCL](https://techcommunity.microsoft.com/blog/azurehighperformancecomputingblog/running-container-workloads-in-cyclecloud-slurm-%E2%80%93-multi-node-multi-gpu-jobs-nccl/4399865)
- [Optimizing AI Workloads on Azure: CPU Pinning via NCCL Topology file](https://techcommunity.microsoft.com/blog/azurehighperformancecomputingblog/optimizing-ai-workloads-on-azure-cpu-pinning-via-nccl-topology-file/4371810)
- [NVIDIA NCCL tests git](https://github.com/NVIDIA/nccl-tests)
- [NVIDIA NCCL test doc](https://github.com/NVIDIA/nccl-tests/blob/master/doc/PERFORMANCE.md)
- [NVIDIA DGX H100/H200 User Guide](https://docs.nvidia.com/dgx/dgxh100-user-guide/introduction-to-dgxh100.html)

