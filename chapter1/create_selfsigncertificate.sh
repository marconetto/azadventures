#!/bin/bash


ROOT_CERTIFICATE_PATH=tmp_cert_base64
ROOT_CERT_NAME=rootcertificate

PASSWORD="mypassword"
USERNAME="myusername"

# PASSWORD="$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' < /dev/urandom | head -c 16)"

echo $PASSWORD


RG="myrg"
GWNAME="myrgvnet1gw"

# be careful with the openssl implementation/version in mac to avoid issues with
# p12 importing process
OPENSSL=/usr/bin/openssl

set -x

function install_dependencies(){

    brew install strongswan
}

function generate_ca_certificate(){

    ipsec pki --gen --outform pem > caKey.pem
    ipsec pki --self --in caKey.pem --dn "CN=VPN CA" --ca --outform pem > caCert.pem

    $OPENSSL x509 -in caCert.pem -outform der | base64 > $ROOT_CERTIFICATE_PATH
}

function generate_p12_file(){

    ipsec pki --gen --outform pem > "${USERNAME}Key.pem"
    ipsec pki --pub --in "${USERNAME}Key.pem" | ipsec pki --issue \
          --cacert caCert.pem \
          --cakey caKey.pem \
          --dn "CN=${USERNAME}" \
          --san "${USERNAME}" \
          --flag clientAuth \
          --outform pem > "${USERNAME}Cert.pem"

    echo "PASS=$PASSWORD"
    echo "USER=$USERNAME"

    $OPENSSL pkcs12 -in "${USERNAME}Cert.pem" \
               -inkey "${USERNAME}Key.pem" \
               -certfile caCert.pem \
               -export -out "${USERNAME}.p12" \
               -password "pass:${PASSWORD}"

}

function add_certificate_gateway(){

    az network vnet-gateway root-cert create --resource-group $RG \
                                             --gateway-name $GWNAME  \
                                             --name $ROOT_CERT_NAME  \
                                             --public-cert-data $ROOT_CERTIFICATE_PATH  \
                                             --output none
}

function get_vpnclient_info(){

    VPN_CLIENT=$(az network vnet-gateway vpn-client generate \
    --resource-group $RG \
    --name $GWNAME \
    --authentication-method EAPTLS | tr -d '"')

    curl $VPN_CLIENT --output vpnClient.zip

    unzip ./vpnClient.zip

    VPN_SERVER=$(xmllint --xpath "string(/VpnProfile/VpnServer)" Generic/VpnSettings.xml)

    VPN_TYPE=$(xmllint --xpath "string(/VpnProfile/VpnType)" Generic/VpnSettings.xml | tr '[:upper:]' '[:lower:]')

    ROUTES=$(xmllint --xpath "string(/VpnProfile/Routes)" Generic/VpnSettings.xml)

    echo "VPN_SERVER=$VPN_SERVER"
    echo "VPN_TYPE=$VPN_TYPE"
    echo "ROUTES=$ROUTES"
}


function show_macos_install_instructions(){


    echo "------------MACOS INSTRUCTIONS----------"
    echo "1. Double-click on the p12 file, and you will be prompted for the password (macos and certificate password)"
    echo "2. Go to network settings of macos and use VpnServer as Server address and Remote ID."
    echo "3. For Local ID use USERNAME specified in this script, which is the name in the p12 bundle"
    echo "4. The certificate is the one call USERNAME that will be in a list of other imported certificates."
    echo "----------------------------------------"

}

install_dependencies

generate_ca_certificate

generate_p12_file

add_certificate_gateway

get_vpnclient_info

show_macos_install_instructions
