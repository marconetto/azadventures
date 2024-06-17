export RG=mydemo
export REGION=eastus

export VMNAME=${RG}vm

export SKUCYCLECLOUD=Standard_E32s_v4
export SKUSCHEDULER=Standard_D4ads_v5
export SKUHPCNODES=Standard_F2s_v2
#export SKUHPCNODES=Standard_HB120rs_v3

# export VMIMAGE=microsoft-dsvm:ubuntu-hpc:2204:latest
export VMIMAGE=microsoft-dsvm:ubuntu-hpc:2004:latest
export ADMINUSER=azureuser

export STORAGEACCOUNT=${RG}sa
export KEYVAULT=${RG}kv

export VNETADDRESS=10.38.0.0
export VMVNETNAME=${RG}VNET
export VMSUBNETNAME=${RG}SUBNET

export VPNRG=myvpnrg
export VPNVNET=myvpnvnet

# uncomment here to enable tags for resource group
#export AZURETAGS="'mytagname1=mytagvalue1' 'mytagname2=mytagvalue2'"
