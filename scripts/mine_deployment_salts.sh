#!/usr/bin/env bash

# Ensure that required environment variables are set
if [ -z "$SALT_MINE_CREATE2_FACTORY_ADDRESS" ]; then
  echo "SALT_MINE_CREATE2_FACTORY_ADDRESS is not set in .env file."
  exit 1
fi
if [ -z "$WALLET_PROXY_INIT_CODE_HASH" ]; then
  echo "WALLET_PROXY_INIT_CODE_HASH is not set in .env file."
  exit 1
fi
if [ -z "$MINTER_PROXY_INIT_CODE_HASH" ]; then
  echo "MINTER_PROXY_INIT_CODE_HASH is not set in .env file."
  exit 1
fi

# Select prefixes based on environment
WALLET_PREFIX=""
MINTER_PREFIX=""

if [[ $ENV == "MAINNET_PROD" ]]
then
  WALLET_PREFIX="7777777"
  MINTER_PREFIX="2222222"
elif [[ $ENV == "TESTNET_PROD" ]]
then
  WALLET_PREFIX="0077777"
  MINTER_PREFIX="0022222"
elif [[ $ENV == "TESTNET_STAGING" ]]
then
  # 5 = "S" for Staging
  WALLET_PREFIX="5577777"
  MINTER_PREFIX="5522222"
elif [[ $ENV == "TESTNET_TESTING" ]]
then
  # 7E = "T" for Testing
  WALLET_PREFIX="7E77777"
  MINTER_PREFIX="7E22222"
fi


# Mine Wallet Proxy salt
echo "****** Mining salt for GatewayWallet proxy... ******"

cast create2 --starts-with "$WALLET_PREFIX" --deployer $SALT_MINE_CREATE2_FACTORY_ADDRESS --init-code-hash $WALLET_PROXY_INIT_CODE_HASH


# Mine Minter Proxy salt
echo -e "\n--------------------------------------------------------------------------------------------------------\n"
echo "****** Mining salt for GatewayMinter proxy... ******"

cast create2 --starts-with "$MINTER_PREFIX" --deployer $SALT_MINE_CREATE2_FACTORY_ADDRESS --init-code-hash $MINTER_PROXY_INIT_CODE_HASH
