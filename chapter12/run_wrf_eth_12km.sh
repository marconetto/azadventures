#!/bin/bash
#SBATCH --nodes=4
#SBATCH --tasks-per-node=2

source /cvmfs/software.eessi.io/versions/2023.06/init/bash
module load WRF/4.4.1-foss-2022b-dmpar

execdir="run_$((RANDOM % 90000 + 10000))"
mkdir -p $execdir
cd $execdir || exit
echo "Execution directory: $execdir"

wrfrundir=$(which wrf.exe | sed 's/\/main\/wrf.exe/\/run\//')
ln -s "$wrfrundir"/* .
ln -sf /shared/home/azureuser/v4.4_bench_conus12km/* .

export UCX_TLS=tcp
export UCX_NET_DEVICES=eth0

time mpirun wrf.exe
