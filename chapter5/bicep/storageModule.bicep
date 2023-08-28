param storageAccountName string
param location string = resourceGroup().location
param allowedSubnetId string
param storageContainerName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  kind: 'BlockBlobStorage'
  properties: {
    isNfsV3Enabled: true
    isHnsEnabled: true
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [{
        action: 'Allow'
        id: allowedSubnetId
      }
    ]
    }
    supportsHttpsTrafficOnly: false
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobServices
  name: storageContainerName
}

output storageAccountId string = storageAccount.id
