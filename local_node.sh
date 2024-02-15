#!/usr/bin/env bash

# Set the sources
source .env
source $BLOCKCHAIN_ENV_FILE

# Test if anvil is already running
if (! pgrep -x "anvil" > /dev/null) || !(ls .anvil.json > /dev/null)
then
    fuser -k $ANVIL_PORT/tcp
    echo "Starting anvil..."
    echo "Forking $NETWORK network..."
    # Start anvil and generate the config file
    anvil --fork-url https://$FORK.infura.io/v3/$INFURA_KEY --port $ANVIL_PORT --config-out .anvil.json &
    sleep 10
else
    echo "Anvil is running..."
fi

echo "Reading the anvil config file..."
# Generate the anvil env file by reading the output of the anvil command
PRIVATE_KEY=$(cat .anvil.json | jq -r '.private_keys[0]')
echo "Private key generated: $PRIVATE_KEY"

# Generate the .env file
echo "PRIVATE_KEY=$PRIVATE_KEY" > .anvil.env
# RPC URL
echo "RPC_URL=http://localhost:$ANVIL_PORT" >> .anvil.env

source .anvil.env

# Running the deployment script
echo "Running the deployment script..."
forge script ./deployment/Deploy.sol --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --via-ir > ./.log
echo "Deployment succeeded!"

# Echo the logs
cat ./.log

strings ./.log | grep -E '[[0-9]+/[0-9]+\] - .*: 0x[a-fA-F0-9]{40}' | awk -F'-' '{print $2}' | sed 's/deployed at/ /' | sed 's/ *: */=/' >> ./.anvil.env
rm ./.log

# End
echo ".anvil.env file generated and ready to use!"
echo "-----------------------------------"
cat ./.anvil.env
echo "-----------------------------------"
echo "Kill anvil with the following command:"
echo "fuser -k $ANVIL_PORT/tcp"
