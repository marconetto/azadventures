export RG=mydemo
export REGION=eastus

export VMNAME=${RG}vm
export SKU=Standard_B2ms
export VMIMAGE=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101
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
