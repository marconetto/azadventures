#!/usr/bin/env bash

if [ "$#" != 4 ]; then

  echo "Usage: $0 <resourcegroup gw vnet> <gw vnet> <resourcegroup vm vnet> <vm vnet>"
  exit 1
fi

function check_error() {

  error=$1

  if [[ $error -ne 0 ]]; then
    echo "Error creating peering"
    exit "$1"
  fi
}

echo "---- Starting VPN Peering ----"

RGGWVNET=$1
GWVNET=$2
RGVMVNET=$3
VMVNET=$4

GWVNET_TO_VMVNET=${RGGWVNET}-${GWVNET}-TO-${RGVMVNET}-${VMVNET}
VMVNET_TO_GWVNET=${RGVMVNET}-${VMVNET}-TO-${RGGWVNET}-${GWVNET}

echo "RGVMVNET=$RGVMVNET"
echo "VMVNET=$VMVNET"
echo "RGGWVNET=$RGGWVNET"
echo "GWVNET=$GWVNET"

echo "GWVNET_TO_VMVNET"="${GWVNET_TO_VMVNET}"
echo "VMVNET_TO_GWVNET"="${VMVNET_TO_GWVNET}"

# GW VNET TO VM VNET
vmvnetid=$(az network vnet show \
  --resource-group "${RGVMVNET}" \
  --name "$VMVNET" \
  --query id --out tsv)

echo "VM VNET ID=$vmvnetid"

set -x
az network vnet peering create \
  --name "${GWVNET_TO_VMVNET}" \
  --resource-group "${RGGWVNET}" \
  --vnet-name "${GWVNET}" \
  --remote-vnet "'${vmvnetid}'" \
  --allow-vnet-access \
  --allow-gateway-transit \
  --allow-forwarded-traffic
set +x

check_error $?

# VM VNET TO GW VNET
gwvnetid=$(az network vnet show \
  --resource-group "${RGGWVNET}" \
  --name "${GWVNET}" \
  --query id --out tsv)

echo "GW VNET ID=$gwvnetid"

set -x
az network vnet peering create \
  --name "${VMVNET_TO_GWVNET}" \
  --resource-group "${RGVMVNET}" \
  --vnet-name "${VMVNET}" \
  --remote-vnet "'${gwvnetid}'" \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --use-remote-gateways
set +x

check_error $?

az network vnet peering list -g "${RGGWVNET}" --vnet-name "${GWVNET}" -o table
az network vnet peering list -g "${RGVMVNET}" --vnet-name "${VMVNET}" -o table
