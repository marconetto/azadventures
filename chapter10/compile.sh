#!/usr/bin/env bash

# based on: https://github.com/kaneuffe/azure-batch-workshop

echo "Creating run_mpi.sh file"


MPI_EXE=mpi_show_hosts
MPI_CODE=mpi_show_hosts.c

MPI_EXE_PATH="${AZ_BATCH_NODE_MOUNTS_DIR}/data/"
cat << 'EOF' > run_mpi.sh
#!/bin/bash

if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

module load gcc-9.2.0
module load mpi/hpcx

# Create host file
batch_hosts=hosts.batch
rm -rf $batch_hosts
IFS=';' read -ra ADDR <<< "$AZ_BATCH_NODE_LIST"
for i in "${ADDR[@]}"; do echo $i >> $batch_hosts;done

# Determine hosts to run on
src=$(tail -n1 $batch_hosts)
dst=$(head -n1 $batch_hosts)
echo "Src: $src"
echo "Dst: $dst"

NODES=2
PPN=2
NP=$(($NODES*$PPN))

set -x

mpirun -np $NP --oversubscribe --host ${src}:${PPN},${dst}:${PPN} --map-by ppr:${PPN}:node --mca btl tcp,vader,self --mca coll_hcoll_enable 0 --mca btl_tcp_if_include lo,eth0 --mca pml ^ucx ${MPI_EXE_PATH}/${MPI_EXE}
EOF

chmod +x run_mpi.sh


if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

module load gcc-9.2.0
module load mpi/hpcx

set -x
echo "Compiling mpi code"
mpicc -o ${MPI_EXE} ${MPI_CODE}
ls -l ${MPI_EXE}
