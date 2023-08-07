## Peering vnets to access via VPN gateway and bastion

You don't want to create bastion-enabled vms (aka jumpbox) or vpn gateway
every time you provision resources in azure, including resources in different
resource groups or vnets. That is why it is a good idea to have a resource group
for a vpngateway or bastion so you can use those to access the new provisioned
resources.


### Peering for VPN gateway
This is a step-by-step tutorial to create a single VM under a private network that
is accessed via a bastion.


All the steps are based on Azure CLI, and therefore can be fully automated.


Assume we have two vnets: "vnetgw" which has the VPN gateway and "vnetvms" where
your resources are provisioned.


Check out create_peering_vpn.sh in this folder to automate vpn peering

Check out create_peering_bastion.sh in this folder to automate bastion peering


*DISCLAIMER: This document is work-in-progress and my personal experience
performing this task.*

<br>
---

##### GW VNET TO VM VNET
```
vnet1Id=$(az network vnet show \
  --resource-group mnettorg1 \
  --name vm02-vnet \
  --query id --out tsv)
```

```
az network vnet peering create \
  --name vnetvmsTovnetgw \
  --resource-group mnettovpn1 \
  --vnet-name mnettovpn1vnet1 \
  --remote-vnet $vnet1Id \
  --allow-vnet-access \
  --allow-gateway-transit \
  --allow-forwarded-traffic
```

##### VM VNET TO GW VNET
```
vnet2Id=$(az network vnet show \
  --resource-group mnettovpn1 \
  --name mnettovpn1vnet1 \
  --query id --out tsv)
```

```
az network vnet peering create \
  --name vnetgwTovnetvms \
  --resource-group mnettorg1 \
  --vnet-name vm02-vnet \
  --remote-vnet $vnet2Id \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --use-remote-gateways
```



There was a command "--remote-vnet-id" that no longer exists. Therefore,
"--remote-vnet" can use a vnet name if it is in the same resource group, or the
resource id in case the vnet is in another resource group, but same
subscription.

On flag "--use-remote-gateways":
- Allows VNet to use the remote VNet's gateway. Remote VNet gateway must have --allow-gateway-transit enabled for remote peering. Only 1 peering can have this flag enabled. Cannot be set if the VNet already has a gateway.


### check the created peerings

```
az network vnet peering list -g mnettovpn1 --vnet-name mnettovpn1vnet1 -o table
```


```
az network vnet peering list -g mnettorg1 --vnet-name vm02-vnet -o table
```

### Peering for bastion-based access


It is pretty much the same as the VPN-based one above, just make sure that the
options "--use-remote-gateways" and "--allow-gateway-transit" are removed from
the commands.


## References

- https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview
- https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-connect-virtual-networks-portal
- https://learn.microsoft.com/en-us/azure/virtual-network/create-peering-different-deployment-models
- https://davidsudjiman.wordpress.com/2022/01/25/azure-vpn-gateway-transit-for-virtual-network-peering/
- https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-peering-gateway-transit
- https://learn.microsoft.com/en-us/azure/bastion/vnet-peering
