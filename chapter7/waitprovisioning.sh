#!/usr/bin/env bash

function retry_installer(){
    local attempts=0
    local max=15
    local delay=25

    while true; do
        ((attempts++))
        "$@" && {
            echo "CLI installed"
            break
        } || {
            if [[ $attempts -lt $max ]]; then
                echo "CLI installation failed. Attempt $attempts/$max."
                sleep $delay;
            else
                echo "CLI installation has failed after $attempts attempts."
                break
            fi
        }
    done
}

function install_azure_cli(){
    install_script="/tmp/azurecli_installer.sh"
    curl -sL https://aka.ms/InstallAzureCLIDeb -o "$install_script"
    retry_installer sudo bash "$install_script"
    rm $install_script
}

if ! command -v az &> /dev/null
then
    echo "azure client not installed"
    install_azure_cli
fi

POOLINGTIME=10

az login --identity

vm_resource_id=$(curl -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-02-01&format=text")

provisioningState="None"
while [ "$provisioning_state" != "Succeeded" ]; do
    provisioning_state=$(az resource show --ids "$vm_resource_id" \
                                          --query 'properties.provisioningState' \
                                          --output tsv)
    echo "$(date +%F-T%T) provisioning state = $provisioning_state"
    sleep "$POOLINGTIME"
done

echo "ready to go!"
