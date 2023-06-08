#!/usr/bin/env bash


RG=myresourcegroup
SKU=Standard_DS1_v2
VMSSNAME=myScaleSet
REGION=eastus
VMSSADMINUSER=azureuser
VNETADDRESS=10.42.0.0

JUMPBOXRG=mnettobastion1
JUMPBOXVNET=mnettobastion1vnet1
JUMPBOXSUBNET=mnettobastion1subnet1

VMSSVNETNAME="$VMSSNAME"VNET
VMSSSUBNETNAME="$VMSSNAME"SUBNET

function showinstances(){

    VMS=$(az vmss list-instances \
      --resource-group $RG \
      --name $VMSSNAME \
      --query "[].{name:name}" --output tsv)

     IPS=$(az vmss nic list --resource-group $RG \
         --vmss-nam $VMSSNAME --query "[].ipConfigurations[].privateIPAddress" --output tsv)

    ARRAY_VMS=($VMS)
    ARRAY_IPS=($IPS)

    for i in "${!ARRAY_VMS[@]}"; do
        printf "%s has private ip %s\n" "${ARRAY_VMS[i]}" "${ARRAY_IPS[i]}"
    done
}




function get_provisioning_state(){

    echo "get provisioning state"

    az vmss list-instances --resource-group $RG \
                           --name $VMSSNAME \
                           --query "[].{Name:name, ProvisioningState:provisioningState}" --output table
}


function monitor_autscaling_trigger(){

   # there is a delay between actual trigger and info available in activity log
   az monitor activity-log list --resource-group $RG  > tmp.json

   NUMOPERATIONS=`cat tmp.json | jq '.[] | select(.caller != null) |select(.caller | contains("autoscale")) | {caller: .caller, time: .submissionTimestamp}' | grep time | wc -l`
   echo "Past # of autoscaling operations: $NUMOPERATIONS"

   while true
   do
       az monitor activity-log list --resource-group $RG  > tmp.json
       # cat tmp.json | jq '.[] | select(.caller != null) |select(.caller | contains("autoscale")) | {caller: .caller, time: .submissionTimestamp}'
       NEWNUMOPERATIONS=`cat tmp.json | jq '.[] | select(.caller != null) |select(.caller | contains("autoscale")) | {caller: .caller, time: .submissionTimestamp}' | grep time | wc -l`
       echo "Current # of autoscaling operations $NEWNUMOPERATIONS"

       if [ "$NEWNUMOPERATIONS" != "$NUMOPERATIONS" ]; then
           echo "New autoscaling operation triggered!"
           NUMOPERATIONS=$NEWNUMOPERATIONS
       fi
      sleep 10
   done
}


function loopshowinstances(){

    while true
    do
       showinstances
       get_provisioning_state
      sleep 1
    done

}


function create_resource_group(){

    az group create --location $REGION \
                    --name $RG
}

function create_vnet_subnet(){

     az network vnet create -g $RG \
                            -n $VMSSVNETNAME \
                            --address-prefix "$VNETADDRESS"/16 \
                            --subnet-name $VMSSSUBNETNAME \
                            --subnet-prefixes "$VNETADDRESS"/24
}


function generate_cloudinit(){

    echo "Generating cloud-init file"

    cat << EOF > cloud-init.txt
#cloud-config
package_upgrade: true
packages:
  - stress
  - stress-ng

EOF
}

function provision_vmss(){

    az vmss create \
      --resource-group $RG \
      --name $VMSSNAME \
      --image UbuntuLTS \
      --orchestration-mode Uniform \
      --instance-count 2 \
      --admin-username $VMSSADMINUSER \
      --generate-ssh-keys \
      --vnet-name $VMSSVNETNAME \
      --subnet $VMSSSUBNETNAME \
      --vm-sku $SKU \
      --public-ip-address "" \
      --custom-data cloud-init.txt
}

function set_autoscaling_profile(){


  az monitor autoscale create \
  --resource-group $RG \
  --resource $VMSSNAME \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name autoscale \
  --min-count 2 \
  --max-count 10 \
  --count 2
}

function set_manual_scaling(){

    az monitor autoscale update --name autoscale \
                   --resource-group $RG \
                   --enabled false


}

function set_auto_scaling(){

    az monitor autoscale update --name autoscale \
                   --resource-group $RG \
                   --enabled true


}


function back_original_capacity(){

    az vmss scale --resource-group $RG \
                 --name $VMSSNAME \
                 --new-capacity 2
}


function remove_all_instances(){

    az vmss delete-instances --instance-ids "*"\
                             --resource-group $RG \
                             --name $VMSSNAME


}

function set_autoscaling_rules(){

    az monitor autoscale rule create \
        --resource-group $RG \
        --autoscale-name autoscale \
        --condition "Percentage CPU > 71 avg 5m" \
        --scale out 1

    az monitor autoscale rule create \
        --resource-group $RG \
        --autoscale-name autoscale \
        --condition "Percentage CPU < 30 avg 5m" \
        --scale in 1

}

#create_resource_group
#create_vnet_subnet
#provision_storage_account
#set_storage_account_access
#provision_storage_container
#generate_cloudinit
#provision_vmss
#showinstances
#loopshowinstances
#set_autoscaling_profile
#set_autoscaling_rules
#monitor_autscaling_trigger
#set_manual_scaling
#remove_all_instances
#back_original_capacity
#set_auto_scaling
