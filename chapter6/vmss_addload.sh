#!/usr/bin/env bash

RG=myresourcegroup
VMSSNAME=myScaleSet


function get_vmss_instances(){

    VMS=$(az vmss list-instances \
      --resource-group $RG \
      --name $VMSSNAME \
      --query "[].{name:name}" --output tsv)

     IPS=$(az vmss nic list --resource-group $RG \
         --vmss-nam $VMSSNAME --query "[].ipConfigurations[].privateIPAddress" --output tsv)

    ARRAY_VMS=($VMS)
    ARRAY_IPS=($IPS)

}


function run_command_vmss(){

    COMMAND=$@
    echo "RUN: $COMMAND"

    SSH="ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

    for i in "${!ARRAY_VMS[@]}"; do
       IP="${ARRAY_IPS[i]}"
       printf "%s has private ip %s\n" "${ARRAY_VMS[i]}" "${ARRAY_IPS[i]}"
       echo "$SSH $IP \"nohup $COMMAND &\""
       $SSH $IP nohup $COMMAND &
    done
}

function gen_load(){

    load=$1
    duration=$2

    COMMAND=$(printf 'stress-ng --cpu 0 --cpu-method all --cpu-load %s --timeout %ss --quiet' "$load" "$duration")

    run_command_vmss $COMMAND

}

function kill_load(){


    echo "kill load"
    COMMAND="killall stress-ng"
    run_command_vmss $COMMAND

}

usage() { echo "Usage: $0 -g <resourcegroup> -v <vmss> < -l <load in percentage> -d <duration in secs> | -k (kill) >" 1>&2; exit 1; }


while getopts ":g:v:l:d:k" o; do
    case "${o}" in
        g)

            RG=${OPTARG}
            ;;
        v)
            VMSS=${OPTARG}
            ;;
        l)
            LOAD=${OPTARG}
            ;;
        d)
            DURATION=${OPTARG}
            ;;
        k)
           KILL="true"
           ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

echo $RG $VMSS $LOAD $DURATION $KILL
if [ -z "${RG}" ] || [ -z ${VMSS} ] ; then
    usage
fi

if [  ! -z "${LOAD}" ] &&  [ -z "${DURATION}"  ] ;then
    usage
fi

if [  ! -z "${DURATION}" ] &&  [ -z "${LOAD}"  ] ;then
    usage
fi

if [  -z "${DURATION}" ] &&  [ -z "${LOAD}"  ] && [ -z "${KILL}" ];then
    usage
fi

get_vmss_instances

if [ ! -z "${LOAD}" ]; then
   gen_load $LOAD $DURATION
else
   kill_load
fi
