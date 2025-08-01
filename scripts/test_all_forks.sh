#!/usr/bin/env bash

chains=(
  local
  ethereum
  ethereum_sepolia
  arbitrum
  arbitrum_sepolia
  base
  base_sepolia
)

for chain in ${chains[@]}; do
  forge_test_args=($@)

  if [[ ${chain} != "local" ]]; then
    rpc=$(forge config --json | jq -r ".rpc_endpoints.${chain}")

    if [[ ${rpc} == "null" ]]; then
      echo "RPC not configured for ${chain}"
      exit 1
    fi

    forge_test_args+=(--fork-url ${rpc})

    if [[ ${CI} != "true" ]]; then
      block=$(jq ".${chain}" block-numbers.json)
      forge_test_args+=(--fork-block-number ${block})
    fi

    # Skip multi-chain integration tests if not running on local network
    forge_test_args+=(--no-match-path="test/integration/*.t.sol")
  fi

  # Skip bytecode match test
  forge_test_args+=(--no-match-test="BytecodeMatch")

  echo "=== Running tests on chain: ${chain} ==="
  echo

  forge test ${forge_test_args[@]}
  result=$?

  if [[ ${result} != 0 ]]; then
    echo
    echo "--- Tests failed on chain: ${chain} ---"
    exit ${result}
  fi

  echo
done
