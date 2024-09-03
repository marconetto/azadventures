### MPI implementations


#### Overview

MPI is a specification which defines communication protocols and routines for parallel programming. MPI-based programs have multiple tasks which need to exchange messages to achieve the final result.

There are various MPI implementations such as:

- [MPICH (MPI Chameleon)](https://www.mpich.org/): portable MPI implementation from Argonne National Laboratory. First version was developed in early 90s, and still under development. It is one of the most popular implementations of MPI.

- [OpenMPI](https://www.open-mpi.org/): came from a merger of other three MPI implementations (FT-MPI, LA-MPI, LAM/MP).

- [Intel MPI](https://www.intel.com/content/www/us/en/developer/tools/oneapi/mpi-library.html): optimized specifically for Intel processors and part of Intel's suite of HPC tools.

- [MVAPICH](https://mvapich.cse.ohio-state.edu/): Developed at Ohio State University, its original implementation was an MPI implementation over the InfiniBand VAPI interface based on the MPICH implementation. It focuses on exploiting the novel features of high-performance networking technologies.

- [NVIDIA HPC-X MPI](https://developer.nvidia.com/networking/hpc-x): HPC-X is
a software suite which includes an MPI implementation that is optimized for
NVIDIA interconnects and GPUs.

#### References

- MPICH (MPI Chameleon): <https://www.mpich.org/>
- OpenMPI: <https://www.open-mpi.org/>
- Intel MPI:
<https://www.intel.com/content/www/us/en/developer/tools/oneapi/mpi-library.html>
- MVAPICH: <https://mvapich.cse.ohio-state.edu/>
- NVIDIA HPC-X MPI: <https://developer.nvidia.com/networking/hpc-x>
