#!/usr/bin/env bash

set -x

ADMINUSER=$(grep name /opt/cycle/jetpack/config/auth.json | awk -F'"' '{print $4}')

runuser -l "$ADMINUSER" -c 'curl -O https://raw.githubusercontent.com/marconetto/azadventures/main/chapter12/run_wrf_eth_12km.sh'
runuser -l "$ADMINUSER" -c 'curl -O https://raw.githubusercontent.com/marconetto/azadventures/main/chapter12/run_wrf_hb_2_5km.sh'

runuser -l "$ADMINUSER" -c 'curl -O https://www2.mmm.ucar.edu/wrf/users/benchmark/v44/v4.4_bench_conus12km.tar.gz'
runuser -l "$ADMINUSER" -c 'tar zxvf v4.4_bench_conus12km.tar.gz ; rm v4.4_bench_conus12km.tar.gz'

runuser -l "$ADMINUSER" -c 'echo "curl -O https://www2.mmm.ucar.edu/wrf/users/benchmark/v44/v4.4_bench_conus2.5km.tar.gz" >> download_wrf_hb_2_5km.sh'
#runuser -l "$ADMINUSER" -c 'curl -O https://www2.mmm.ucar.edu/wrf/users/benchmark/v44/v4.4_bench_conus2.5km.tar.gz'
#runuser -l "$ADMINUSER" -c 'tar zxvf v4.4_bench_conus2.5km.tar.gz ; rm v4.4_bench_conus2.5km.tar.gz'
