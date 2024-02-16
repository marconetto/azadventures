#!/bin/bash

source /cvmfs/pilot.eessi-hpc.org/latest/init/bash
module load WRF/3.9.1.1-foss-2020a-dmpar
module load mpi

execdir="run_$((RANDOM % 90000 + 10000))"
mkdir -p $execdir
cd $execdir || exit
echo "Execution directory: $execdir"

wrfrundir=$(which wrf.exe | sed 's/\/main\/wrf.exe/\/run\//')
ln -s "$wrfrundir"/* .
ln -sf /shared/home/azureuser/bench_12km/* .

export UCX_TLS=tcp
export UCX_NET_DEVICES=eth0
export OMPI_MCA_pml=ucx

time mpirun -np 4 wrf.exe
