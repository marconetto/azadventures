export RG=nettocc20240215v1
# export REGION=canadacentral
# export REGION=eastus2euap
#export REGION=centraluseuap
#export REGION=eastuseuap
export REGION=eastus

export VMNAME=${RG}vm01
export SKUCYCLECLOUD=Standard_E32s_v4
# export SKU=Standard_B2ms

export SKUSCHEDULER=Standard_D4ads_v5
# export SKUHPCNODES=Standard_HC44rs
#export SKUHPCNODES=Standard_F2s_v2
#export SKUHPCNODES=Standard_HC44-32rs
export SKUHPCNODES=Standard_HB120rs_v3

export VMIMAGE=Canonical:0001-com-ubuntu-server-focal:20_04-lts-gen2:latest
# export VMIMAGE=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101
export ADMINUSER=azureuser

export STORAGEACCOUNT=${RG}sa
export KEYVAULT=${RG}kv

export VNETADDRESS=10.60.0.0
export VMVNETNAME=${RG}VNET
export VMSUBNETNAME=${RG}SUBNET

export VPNRG=nettovpn2
export VPNVNET=nettovpn2vnet1

export AZURETAGS="'mytagname1=mytagvalue1' 'mytagname2=mytagvalue2'"
