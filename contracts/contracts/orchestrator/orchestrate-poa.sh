#!/bin/bash

######################################################################################################
# Orchestrates POA. It generates node identity for validator nodes . It stores passphrarases of
# validator nodes in key vault and create a lease record in azure blob.
#######################################################################################################

# Include utility script
. orchestrate-util.sh

#set -x

start_parity_devmode_rpc() {
	parity --chain dev --base-path "$DEV_PARITY_DIRECTORY" --jsonrpc-apis "eth,net,web3,personal,parity,parity_accounts" >> "$CONFIG_LOG_FILE_PATH" 2>&1 &
	if [ $? -ne 0 ]; then unsuccessful_exit "Failed to start parity node in dev mode." 25; fi
	echo "===== Started parity in dev mode =====";
	sleep 10;
}


# Shutdown parity process
shutdown_parity()
{
    kill -9 $(ps aux | grep '[p]arity -' | awk '{print $2}');
    # Give time for the process to stop
    sleep 5;
}

setup_cli_certificates()
{
	if [ ! -z $SPN_APPID ]; then
		sudo cp /var/lib/waagent/Certificates.pem /usr/local/share/ca-certificates/azsCertificate.crt
		sudo update-ca-certificates
		export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
		sudo sed -i -e "\$aREQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" /etc/environment
	fi

	if [[ ! -z "$IS_ADFS" ]]; then
		#if [[ $SPN_KEY != *"servicePrincipalCertificate.pem"* ]]; then
		spCertName="$SPN_KEY.crt"
		spCertKey="$SPN_KEY.prv"
		sudo cp /var/lib/waagent/$spCertName /home/
		sudo cp /var/lib/waagent/$spCertKey /home/
		sudo cat /home/$spCertName /home/$spCertKey > /home/servicePrincipalCertificate.pem
		sudo chmod 644 /home/servicePrincipalCertificate.pem
		#SPN_KEY=/home/servicePrincipalCertificate.pem
		az cloud register -n AzureStackCloud --endpoint-resource-manager "https://management.$ENDPOINTS_FQDN" --suffix-storage-endpoint "$ENDPOINTS_FQDN" --suffix-keyvault-dns ".vault.$ENDPOINTS_FQDN"
		az cloud set -n AzureStackCloud
		az cloud update --profile 2018-03-01-hybrid
		az login --service-principal -u $SPN_APPID -p /home/servicePrincipalCertificate.pem --tenant $AAD_TENANTID
		#fi
	else
		az cloud register -n AzureStackCloud --endpoint-resource-manager "https://management.$ENDPOINTS_FQDN" --suffix-storage-endpoint "$ENDPOINTS_FQDN" --suffix-keyvault-dns ".vault.$ENDPOINTS_FQDN"
		az cloud set -n AzureStackCloud
		az cloud update --profile 2018-03-01-hybrid
		az login --service-principal -u $SPN_APPID -p $SPN_KEY --tenant $AAD_TENANTID
	fi
}

configure_endpoints()
{
    az cloud register -n AzureStackCloud --endpoint-resource-manager "https://management.$ENDPOINTS_FQDN" --suffix-storage-endpoint "$ENDPOINTS_FQDN" --suffix-keyvault-dns ".vault.$ENDPOINTS_FQDN"
    az cloud set -n AzureStackCloud
    az cloud update --profile 2018-03-01-hybrid
	az login --service-principal -u $SPN_APPID -p $SPN_KEY --tenant $AAD_TENANTID
}

####################################################################################
# Parameters : Validate that all arguments are supplied
####################################################################################
if [ $# -lt 12 ]; then unsuccessful_exit "Insufficient parameters supplied." 21; fi

NodeCount=$1
Mode=$2
KEY_VAULT_BASE_URL=$3
STORAGE_ACCOUNT=$4
CONTAINER_NAME=$5
STORAGE_ACCOUNT_KEY=$6
ETH_NETWORK_ID=$7
INITIAL_VALIDATOR_ADMIN_ACCOUNT=$8
CONSORTIUM_DATA_URL=$9
ACCESS_TOKEN=${10}
CONFIG_LOG_FILE_PATH=${11}
TRANSACTION_PERMISSION_CONTRACT=${12}

AAD_TENANTID=${13}
SPN_KEY=${14}
SPN_APPID=${15}
RG_NAME=${16}
KV_NAME=${17}
ENDPOINTS_FQDN=${18}
IS_ADFS=${19} 

# Constants
ADDRESS_LIST="";
ADDRESS_LIST_FOR_CONTRACT="";
NOTRIES=3;
PREFUND_ACCOUNT_ADDRESS=""

DEV_PARITY_DIRECTORY="/tmp/parity";

echo "NodeCount= $NodeCount" >> "$CONFIG_LOG_FILE_PATH"
echo "Mode= $Mode" >> "$CONFIG_LOG_FILE_PATH"
echo "KEY_VAULT_BASE_URL= $KEY_VAULT_BASE_URL" >> "$CONFIG_LOG_FILE_PATH"
echo "STORAGE_ACCOUNT= $STORAGE_ACCOUNT" >> "$CONFIG_LOG_FILE_PATH"
echo "CONTAINER_NAME= $CONTAINER_NAME" >> "$CONFIG_LOG_FILE_PATH"
echo "STORAGE_ACCOUNT_KEY= $STORAGE_ACCOUNT_KEY" >> "$CONFIG_LOG_FILE_PATH"
echo "ETH_NETWORK_ID= $ETH_NETWORK_ID" >> "$CONFIG_LOG_FILE_PATH"
echo "INITIAL_VALIDATOR_ADMIN_ACCOUNT= $INITIAL_VALIDATOR_ADMIN_ACCOUNT" >> "$CONFIG_LOG_FILE_PATH"
echo "CONSORTIUM_DATA_URL= $CONSORTIUM_DATA_URL" >> "$CONFIG_LOG_FILE_PATH"
echo "ACCESS_TOKEN= $ACCESS_TOKEN" >> "$CONFIG_LOG_FILE_PATH"
echo "CONFIG_LOG_FILE_PATH= $CONFIG_LOG_FILE_PATH" >> "$CONFIG_LOG_FILE_PATH"
echo "TRANSACTION_PERMISSION_CONTRACT= $TRANSACTION_PERMISSION_CONTRACT" >> "$CONFIG_LOG_FILE_PATH"
echo "AAD_TENANTID= $AAD_TENANTID" >> "$CONFIG_LOG_FILE_PATH"
echo "SPN_KEY= $SPN_KEY" >> "$CONFIG_LOG_FILE_PATH"
echo "SPN_APPID= $SPN_APPID" >> "$CONFIG_LOG_FILE_PATH"
echo "RG_NAME= $RG_NAME" >> "$CONFIG_LOG_FILE_PATH"
echo "KV_NAME= $KV_NAME" >> "$CONFIG_LOG_FILE_PATH"
echo "ENDPOINTS_FQDN= $ENDPOINTS_FQDN" >> "$CONFIG_LOG_FILE_PATH"
echo "IS_ADFS = $IS_ADFS" >> "$CONFIG_LOG_FILE_PATH"

################################################
# Copy required certificates for Azure CLI
################################################
setup_cli_certificates

################################################
# Configure Cloud Endpoints in Azure CLI
################################################
#configure_endpoints

############################################################################
# Start party in dev mode
############################################################################
start_parity_devmode_rpc

#############################################################################################################
# Generate passphrases and addreses. Store passphrases in key vault and upload key vault uri in azure blob
#############################################################################################################

if [[ ! -z "$IS_ADFS" ]]; then
	grant_keyvault_access $SPN_APPID "/home/servicePrincipalCertificate.pem" $AAD_TENANTID $KV_NAME $RG_NAME
else
	grant_keyvault_access $SPN_APPID $SPN_KEY $AAD_TENANTID $KV_NAME $RG_NAME
fi


for i in `seq 0 $(($NodeCount - 1))`; do
	passphrase=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32);
	account=$(curl --data '{"jsonrpc":"2.0","method":"parity_newAccountFromPhrase","params":["'$passphrase'", "'$passphrase'"],"id":0}' -H "Content-Type: application/json" -X POST localhost:8545);
	if [ $? -ne 0  ] || [ -z $account ]; then
		unsuccessful_exit "Unable to generate account address from recovery phrase." 22
	fi
	address=$(echo $account | jq -r ".result");

	# Store passphrase in key vault and upload key vault uri to azure blob
	# TODO: Add retry logic on failure to set keyvault secret or upload blob
	passphraseUri=""
	if [[ ! -z "$IS_ADFS" ]]; then
		passphraseUri=$(set_secret_in_keyvault "$KEY_VAULT_BASE_URL" "passphrase-$i" "$passphrase" "$ACCESS_TOKEN" "$AAD_TENANTID" "/home/servicePrincipalCertificate.pem" "$SPN_APPID" "$RG_NAME" "$KV_NAME" );
	else
		passphraseUri=$(set_secret_in_keyvault "$KEY_VAULT_BASE_URL" "passphrase-$i" "$passphrase" "$ACCESS_TOKEN" "$AAD_TENANTID" "$SPN_KEY" "$SPN_APPID" "$RG_NAME" "$KV_NAME" );
	fi
	echo "======================="
	echo $passphraseUri
	echo "======================="
	if [ -z "$passphraseUri" ]; then
		unsuccessful_exit "Unable to set a secret for passphrase in azure KeyVault." 23;
	fi
	upload_uri_to_blob $STORAGE_ACCOUNT $CONTAINER_NAME $STORAGE_ACCOUNT_KEY "passphrase-$i.json" $passphraseUri

	# Keep track of generated address for injecting to smart contract and for admin approval
	if [ -z "$ADDRESS_LIST" ]; then
		ADDRESS_LIST="\"$address\"";
		ADDRESS_LIST_FOR_CONTRACT="address($address)";
	else
		ADDRESS_LIST+=",\"$address\"";
		ADDRESS_LIST_FOR_CONTRACT+=", address($address)"
	fi

done

echo "address list: $ADDRESS_LIST";
echo "smart contract address list: $ADDRESS_LIST_FOR_CONTRACT";

# Sanity check on generated address list
if [ -z "$ADDRESS_LIST" ] || [ -z "$ADDRESS_LIST_FOR_CONTRACT" ];  then
	unsuccessful_exit "Generated address list should not be empty or null." 24;
fi

##################################################################################################
# Generate spec.json and admin list ( member deployment) 
# and upload to storage container
##################################################################################################
if [ "$Mode" == "Leader" ] || [ "$Mode" == "Single" ]; then
	generate_poa_spec "$ADDRESS_LIST_FOR_CONTRACT" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$STORAGE_ACCOUNT_KEY" "$ETH_NETWORK_ID" "$NodeCount" "$INITIAL_VALIDATOR_ADMIN_ACCOUNT" "$TRANSACTION_PERMISSION_CONTRACT"
else
	make_address_list_available_for_download "$ADDRESS_LIST" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$STORAGE_ACCOUNT_KEY"
	host_network_info_from_leader "$CONSORTIUM_DATA_URL"
fi

#################################################################
# Shutdown parity
################################################################
shutdown_parity

############### Orchestration Completed #########################
echo "Orchestration succeeded. Exiting";
exit 0;
