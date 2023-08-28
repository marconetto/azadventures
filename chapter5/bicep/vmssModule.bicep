
param vmssName string
param vmssAdminUserName string
param vmssVnetName string
param vmssSubnetName string
param sku string
param subnetId string
param location string = resourceGroup().location

param sshKeyFile string
param cloudInitScript string

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2021-03-01' = {
  name: vmssName
  location: location
  sku: {
    name: sku
    tier: 'Standard'
    capacity: 2
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: vmssName
        adminUsername: vmssAdminUserName
        customData: loadFileAsBase64('cloud-init.txt')
        linuxConfiguration:{
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${vmssAdminUserName}/.ssh/authorized_keys'
                keyData: loadTextContent('key.pub')
              }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: 'UbuntuServer'
          sku: '18.04-LTS'
          version: 'latest'
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nicName'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig2'
                  properties: {
                    subnet: {
                      id: subnetId
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

