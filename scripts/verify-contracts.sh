#!/bin/bash

set -e

# For each environment, put the wallet address first and the minter address second
declare -A contract_addresses=(
  [staging]="0x557777735b1Dd18194F1b84256be2A3CDee6CB6F 0x552222279206Cb0434128e0caE4558a25779c79F"
  [testnet]="0x0077777d7EBA4688BDeF3E311b846F25870A19B9 0x0022222ABE238Cc2C7Bb1f21003F0a260052475B"
  [mainnet]="0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE 0x2222222d7164433c4C09B0b0D809a9b52C04C205"
)

# For each network, list the environments that are deployed
declare -A networks=(
  [ethereum]="mainnet"
  [ethereum_sepolia]="staging testnet"
  [base]="mainnet"
  [base_sepolia]="staging testnet"
  [avalanche]="mainnet"
  [avalanche_fuji]="staging testnet"
  [arbitrum]="mainnet"
  [arbitrum_sepolia]="staging"
  [polygon]="mainnet"
  [unichain]="mainnet"
  [optimism]="mainnet"
)

# Map to the names needed for the verification calls
declare -A verifier_networks=(
  [ethereum]="mainnet"
  [ethereum_sepolia]="sepolia"
  [base]="base"
  [base_sepolia]="base-sepolia"
  [avalanche]="avalanche"
  [avalanche_fuji]="fuji"
  [polygon]="polygon"
  [unichain]="unichain"
  [optimism]="optimism"
  [arbitrum_sepolia]="arbitrum-sepolia"
  [arbitrum]="arbitrum"
)

if [ -z "${ETHERSCAN_KEY}" ]; then
  echo "Please set the ETHERSCAN_KEY environment variable"
  exit 1
fi

for network in "${!networks[@]}"; do
  RPC="-r $(forge config --json | jq -r ".rpc_endpoints.$network")"

  environments=(${networks[$network]})
  for environment in "${environments[@]}"; do
    read -r Wallet_address Minter_address <<< "${contract_addresses[$environment]}"
    for Contract in Wallet Minter; do
      address_var="${Contract}_address"
      proxy_address=${!address_var}
      contract_name="Gateway${Contract}"

      if ! proxy_code=$(cast code $RPC $proxy_address 2> /dev/null) || [ "$proxy_code" = "0x" ]; then
        echo -e "\e[33m=== Skipping $environment $contract_name on $network (proxy: $proxy_address), not deployed yet\e[0m"
        continue
      fi

      impl_address=$(cast impl $RPC $proxy_address)

      echo -e "\e[34m=== Verifying $environment $contract_name on $network (proxy: $proxy_address, impl: $impl_address)\e[0m"

      verifier_network=${verifier_networks[$network]:-$network}
      chain_id=$(cast chain-id $RPC)
      creation_bytecode=$(curl -s "https://api.etherscan.io/v2/api?chainid=${chain_id}&module=contract&action=getcontractcreation&contractaddresses=${proxy_address}&apikey=${ETHERSCAN_KEY}" | jq -r '.result[0].creationBytecode')
      init_bytecode=$(cat script/compiled-contract-artifacts/ERC1967Proxy.json | jq -r .bytecode.object)
      constructor_args=$(echo $creation_bytecode | sed "s/$init_bytecode//")

      # Verify proxy with sourcify
      echo -e "\e[32m--- Verifying proxy with sourcify\e[0m"
      forge verify-contract --verifier sourcify -c $verifier_network $proxy_address ERC1967Proxy --constructor-args "0x$constructor_args"

      # Verify implementation with sourcify
      echo -e "\e[32m--- Verifying implementation with sourcify\e[0m"
      forge verify-contract --verifier sourcify -c $verifier_network $impl_address $contract_name

      # Verify proxy with etherscan
      echo -e "\e[32m--- Verifying proxy with etherscan\e[0m"
      curl -s -d "address=$proxy_address" "https://api.etherscan.io/v2/api?chainid=${chain_id}&module=contract&action=verifyproxycontract&apikey=${ETHERSCAN_KEY}" > /dev/null
      forge verify-contract $RPC --verifier etherscan -c $verifier_network $proxy_address ERC1967Proxy -e $ETHERSCAN_KEY --constructor-args "0x$constructor_args" --watch

      # Verify implementation with etherscan
      echo -e "\e[32m--- Verifying implementation with etherscan\e[0m"
      forge verify-contract --verifier etherscan -c $verifier_network $impl_address $contract_name -e $ETHERSCAN_KEY --watch
    done
  done
done
