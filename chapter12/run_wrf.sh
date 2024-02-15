#!/bin/bash

execdir="run_$((RANDOM % 90000 + 10000))"

mkdir -p $execdir
cd $execdir || exit
ln -s /cvmfs/pilot.eessi-hpc.org/versions/2021.12/software/linux/x86_64/intel/haswell/software/WRF/3.9.1.1-foss-2020a-dmpar/WRFV3/run/* .
ln -sf /shared/home/azureuser/bench_12km/* .
echo "Execution directory: $execdir"

module load mpi
source /cvmfs/pilot.eessi-hpc.org/latest/init/bash
module load WRF/3.9.1.1-foss-2020a-dmpar
#module load OpenMPI/4.1.1-GCC-10.3.0

export UCX_TLS=tcp
export UCX_NET_DEVICES=eth0

time /opt/openmpi-4.1.5/bin/mpirun -np 4 --mca pml ucx wrf.exe
#time /opt/openmpi-4.1.5/bin/mpirun -np 8  --oversubscribe  --mca pml ucx wrf.exe
