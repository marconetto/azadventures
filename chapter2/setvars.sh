export RG=mybastionrg
export REGION=eastus

export VMNAME=${RG}jumpbox
export SKU=Standard_B2ms
export VMIMAGE=Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest
#export VMIMAGE=microsoft-dsvm:ubuntu-hpc:1804:18.04.2021120101
export ADMINUSER=azureuser

export VNETADDRESS=10.38.0.0
export VMVNETNAME=${RG}VNET
export VMSUBNETNAME=${RG}SUBNET

export CREATEJUMPBOX=true
