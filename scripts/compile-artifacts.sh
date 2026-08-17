#!/usr/bin/env bash

set -e

echo "======================================"
echo "Compiling Gateway Contract Artifacts"
echo "======================================"

# Clean previous build artifacts
forge clean

echo ""
echo "Step 1: Compiling proxy and placeholder (via_ir=false)..."
echo "-----------------------------------------------------------"

# Compile ERC1967Proxy and UpgradeablePlaceholder WITHOUT via_ir
# These must maintain deterministic addresses across chain deployments
forge build \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol \
  src/UpgradeablePlaceholder.sol \
  --force

# Copy proxy and placeholder artifacts
cp out/ERC1967Proxy.sol/ERC1967Proxy.json \
   script/compiled-contract-artifacts/ERC1967Proxy.json
echo "✓ Copied ERC1967Proxy.json (compiled without via_ir)"

cp out/UpgradeablePlaceholder.sol/UpgradeablePlaceholder.json \
   script/compiled-contract-artifacts/UpgradeablePlaceholder.json
echo "✓ Copied UpgradeablePlaceholder.json (compiled without via_ir)"

echo ""
echo "Step 2: Compiling implementations (via_ir=true)..."
echo "---------------------------------------------------"

# Compile GatewayWallet and GatewayMinter WITH via_ir
# These need via_ir for bytecode size optimization
forge build \
  src/GatewayWallet.sol \
  src/GatewayMinter.sol \
  --via-ir \
  --force

# Copy implementation artifacts
cp out/GatewayMinter.sol/GatewayMinter.json \
   script/compiled-contract-artifacts/GatewayMinter.json
echo "✓ Copied GatewayMinter.json (compiled with via_ir)"

cp out/GatewayWallet.sol/GatewayWallet.json \
   script/compiled-contract-artifacts/GatewayWallet.json
echo "✓ Copied GatewayWallet.json (compiled with via_ir)"

echo ""
echo "======================================"
echo "✓ All artifacts compiled successfully"
echo "======================================"
