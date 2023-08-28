targetScope = 'subscription'


@description('Resource group to deploy all resources')
param resourceGroupName string

param location string
param vnetName string
param vnetAddressPrefix string
param subnetName string
param subnetAddressPrefix string
param storageAccountName string
param storageContainerName string

param vmssName string
param vmssAdminUserName string
param vmssVnetName string
param vmssSubnetName string
param sku string
param cloudInitScript string

param sshKeyFile string

param jumpboxResourceGroup string = ''
param jumpboxVnetName string = ''

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module vnetModule './vnetModule.bicep' = {
  scope: rg
  name: 'vnetModule'
  params: {
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    subnetName:  subnetName
    subnetAddressPrefix: subnetAddressPrefix
    location: location
  }
}

module storageModule './storageModule.bicep' = {
  scope: rg
  name: 'storageModule'
  params: {
    storageAccountName: storageAccountName
    storageContainerName: storageContainerName
    allowedSubnetId: vnetModule.outputs.subnetId
    location: location
  }
}

// output subnetId string = vnetModule.outputs.subnetId

module vmssModule './vmssModule.bicep' = {
  scope: rg
  name: 'vmssModule'
  params: {
    sshKeyFile: sshKeyFile
    vmssName: vmssName
    subnetId:  vnetModule.outputs.subnetId
    vmssAdminUserName: vmssAdminUserName
    vmssVnetName: vmssVnetName
    vmssSubnetName: vmssSubnetName
    cloudInitScript: cloudInitScript
    sku: sku
    location: location
  }
}

module peerFirstVnetSecondVnet 'vnetpeering.bicep' =  if (jumpboxResourceGroup != '') {
 name: 'peerFirstToSecond'
 scope: rg
 params: {
   existingLocalVirtualNetworkName: vnetModule.outputs.vnetName
   existingRemoteVirtualNetworkName: jumpboxVnetName
   existingRemoteVirtualNetworkResourceGroupName: jumpboxResourceGroup
 }
}

module peerSecondVnetFirstVnet 'vnetpeering.bicep' = if (jumpboxResourceGroup != '') {
 name: 'peerSecondToFirst'
 scope: resourceGroup(jumpboxResourceGroup)
 params: {
   existingLocalVirtualNetworkName: jumpboxVnetName
   existingRemoteVirtualNetworkName: vnetModule.outputs.vnetName
   existingRemoteVirtualNetworkResourceGroupName: rg.name
 }
}

output vnetModuleOutputs object = vnetModule.outputs
output showSubnetID string = vnetModule.outputs.subnetId
