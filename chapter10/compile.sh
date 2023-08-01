#!/usr/bin/env bash


if [ -f /etc/bashrc ]; hen
        . /etc/bashrc
fi

module load gcc-9.2.0
module load mpi/hpcx

set -x
echo "Compiling mpi code"
mpicc -o mpi_show_hosts mpi_show_hosts.c
ls -l mpi_show_hosts
