/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity ^0.8.29;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

import {GatewayWallet} from "src/GatewayWallet.sol";

/// @title UpgradeGatewayWallet
/// @notice Generic upgrade script for GatewayWallet - always upgrades to the latest implementation
/// @dev This script upgrades an existing GatewayWallet proxy to the latest implementation.
///      Uses bytecode deployment from compiled artifacts to ensure consistent bytecode across chains.
///
///      Upgrade process:
///      1. Deploy new GatewayWallet implementation from compiled bytecode
///      2. Call upgradeToAndCall on the proxy to upgrade to new implementation
///      3. (Optional) Update contract signers allowlister if GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS is set
///      4. (Optional) Update contract signers disallowlister if GATEWAYWALLET_CONTRACT_SIGNERS_DISALLOWLISTER_ADDRESS
///         is set
///      5. (Optional) Add contract signature signer if GATEWAYWALLET_CONTRACT_SIGNATURE_SIGNER_ADDRESS is set
///      6. (Optional) Add batch signer if GATEWAYWALLET_BATCHSIGNER_ADDRESS is set
///      7. Validate deployed state
///
///      Required environment variables:
///      - GATEWAYMINTER_WALLET_ADDRESS: The proxy address to upgrade
///      - GATEWAYWALLET_OWNER_ADDRESS: The owner who can upgrade and set roles
///      - GATEWAYWALLET_DEPLOYER_ADDRESS: The address that deploys the new implementation
///
///      Optional environment variables (set if needed):
///      - GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS: Address for contract signers allowlister role
///      - GATEWAYWALLET_CONTRACT_SIGNERS_DISALLOWLISTER_ADDRESS: Address for contract signers disallowlister role
///      - GATEWAYWALLET_CONTRACT_SIGNATURE_SIGNER_ADDRESS: Address to add as contract signature signer (TEE signer)
///      - GATEWAYWALLET_BATCHSIGNER_ADDRESS: Address to add as batch signer
///
///      Usage:
///      # Dry run (simulation)
///      forge script script/004_UpgradeGatewayWallet.sol --rpc-url $RPC_URL -vvvv
///
///      # Broadcast to network
///      forge script script/004_UpgradeGatewayWallet.sol --rpc-url $RPC_URL --broadcast -vvvv \
///        --account deployer --account owner
contract UpgradeGatewayWallet is Script {
    /// @notice Main upgrade function that deploys new implementation and upgrades the proxy
    /// @return newImplAddress The address of the newly deployed implementation
    function run() public returns (address newImplAddress) {
        // Required environment variables
        address gatewayWalletProxy = vm.envAddress("GATEWAYMINTER_WALLET_ADDRESS");
        address gatewayWalletOwner = vm.envAddress("GATEWAYWALLET_OWNER_ADDRESS");
        address deployer = vm.envAddress("GATEWAYWALLET_DEPLOYER_ADDRESS");

        // Optional environment variables (default to 0x0 if not set)
        address contractSignersAllowlister = vm.envOr("GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS", address(0));
        address contractSignersDisallowlister =
            vm.envOr("GATEWAYWALLET_CONTRACT_SIGNERS_DISALLOWLISTER_ADDRESS", address(0));
        address contractSignatureSigner = vm.envOr("GATEWAYWALLET_CONTRACT_SIGNATURE_SIGNER_ADDRESS", address(0));
        address batchSigner = vm.envOr("GATEWAYWALLET_BATCHSIGNER_ADDRESS", address(0));

        // Validation
        require(gatewayWalletProxy != address(0), "GATEWAYMINTER_WALLET_ADDRESS not set");
        require(gatewayWalletOwner != address(0), "GATEWAYWALLET_OWNER_ADDRESS not set");
        require(deployer != address(0), "GATEWAYWALLET_DEPLOYER_ADDRESS not set");

        console.log("\n=== GatewayWallet Upgrade Configuration ===");
        console.log("Proxy address:", gatewayWalletProxy);
        console.log("Owner address:", gatewayWalletOwner);
        console.log("Deployer address:", deployer);
        if (contractSignersAllowlister != address(0)) {
            console.log("Contract Signers Allowlister:", contractSignersAllowlister);
        } else {
            console.log("Contract Signers Allowlister: (not set, skipping)");
        }
        if (contractSignersDisallowlister != address(0)) {
            console.log("Contract Signers Disallowlister:", contractSignersDisallowlister);
        } else {
            console.log("Contract Signers Disallowlister: (not set, skipping)");
        }
        if (contractSignatureSigner != address(0)) {
            console.log("Contract Signature Signer:", contractSignatureSigner);
        } else {
            console.log("Contract Signature Signer: (not set, skipping)");
        }
        if (batchSigner != address(0)) {
            console.log("Batch Signer:", batchSigner);
        } else {
            console.log("Batch Signer: (not set, skipping)");
        }

        // Log current state before upgrade
        console.log("\n=== Pre-Upgrade State ===");
        _logCurrentState(gatewayWalletProxy);

        // Step 1: Deploy new GatewayWallet implementation from bytecode
        console.log("\n=== Step 1: Deploy new implementation ===");
        vm.startBroadcast(deployer);
        newImplAddress = _deployFromBytecode("GatewayWallet.json");
        console.log("New GatewayWallet implementation address:", newImplAddress);
        vm.stopBroadcast();

        // Step 2: Upgrade the proxy to the new implementation
        console.log("\n=== Step 2: Upgrade proxy to new implementation ===");
        vm.startBroadcast(gatewayWalletOwner);

        bytes memory upgradeCallData = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplAddress, hex"");
        (bool upgradeSuccess, bytes memory upgradeReturnData) = gatewayWalletProxy.call(upgradeCallData);
        require(upgradeSuccess, string(abi.encodePacked("Upgrade failed: ", upgradeReturnData)));

        console.log("Successfully upgraded GatewayWallet proxy to new implementation");
        vm.stopBroadcast();

        // Step 3: Update contract signers allowlister (optional)
        if (contractSignersAllowlister != address(0)) {
            console.log("\n=== Step 3: Update contract signers allowlister ===");
            vm.startBroadcast(gatewayWalletOwner);

            bytes memory updateAllowlisterCallData =
                abi.encodeWithSignature("updateContractSignersAllowlister(address)", contractSignersAllowlister);
            (bool allowlisterSuccess, bytes memory allowlisterReturnData) =
                gatewayWalletProxy.call(updateAllowlisterCallData);
            require(
                allowlisterSuccess,
                string(abi.encodePacked("updateContractSignersAllowlister failed: ", allowlisterReturnData))
            );

            console.log("Successfully updated contract signers allowlister to:", contractSignersAllowlister);
            vm.stopBroadcast();
        } else {
            console.log("\n=== Step 3: Update contract signers allowlister (skipped - not set) ===");
        }

        // Step 4: Update contract signers disallowlister (optional)
        if (contractSignersDisallowlister != address(0)) {
            console.log("\n=== Step 4: Update contract signers disallowlister ===");
            vm.startBroadcast(gatewayWalletOwner);

            bytes memory updateDisallowlisterCallData =
                abi.encodeWithSignature("updateContractSignersDisallowlister(address)", contractSignersDisallowlister);
            (bool disallowlisterSuccess, bytes memory disallowlisterReturnData) =
                gatewayWalletProxy.call(updateDisallowlisterCallData);
            require(
                disallowlisterSuccess,
                string(abi.encodePacked("updateContractSignersDisallowlister failed: ", disallowlisterReturnData))
            );

            console.log("Successfully updated contract signers disallowlister to:", contractSignersDisallowlister);
            vm.stopBroadcast();
        } else {
            console.log("\n=== Step 4: Update contract signers disallowlister (skipped - not set) ===");
        }

        // Step 5: Add contract signature signer (optional)
        if (contractSignatureSigner != address(0)) {
            console.log("\n=== Step 5: Add contract signature signer ===");
            vm.startBroadcast(gatewayWalletOwner);

            bytes memory addContractSignatureSignerCallData =
                abi.encodeWithSignature("addContractSignatureSigner(address)", contractSignatureSigner);
            (bool contractSignatureSignerSuccess, bytes memory contractSignatureSignerReturnData) =
                gatewayWalletProxy.call(addContractSignatureSignerCallData);
            require(
                contractSignatureSignerSuccess,
                string(abi.encodePacked("addContractSignatureSigner failed: ", contractSignatureSignerReturnData))
            );

            console.log("Successfully added contract signature signer:", contractSignatureSigner);
            vm.stopBroadcast();
        } else {
            console.log("\n=== Step 5: Add contract signature signer (skipped - not set) ===");
        }

        // Step 6: Add batch signer (optional)
        if (batchSigner != address(0)) {
            console.log("\n=== Step 6: Add batch signer ===");
            vm.startBroadcast(gatewayWalletOwner);

            bytes memory addBatchSignerCallData = abi.encodeWithSignature("addBatchSigner(address)", batchSigner);
            (bool batchSignerSuccess, bytes memory batchSignerReturnData) =
                gatewayWalletProxy.call(addBatchSignerCallData);
            require(batchSignerSuccess, string(abi.encodePacked("addBatchSigner failed: ", batchSignerReturnData)));

            console.log("Successfully added batch signer:", batchSigner);
            vm.stopBroadcast();
        } else {
            console.log("\n=== Step 6: Add batch signer (skipped - not set) ===");
        }

        // Step 7: Validate deployed state
        console.log("\n=== Step 7: Validate post-upgrade state ===");
        _validateUpgrade(
            gatewayWalletProxy,
            newImplAddress,
            gatewayWalletOwner,
            contractSignersAllowlister,
            contractSignersDisallowlister,
            contractSignatureSigner,
            batchSigner
        );

        // Summary
        console.log("\n=== GatewayWallet Upgrade Complete ===");
        console.log("Proxy address:", gatewayWalletProxy);
        console.log("New implementation:", newImplAddress);
        if (contractSignersAllowlister != address(0)) {
            console.log("Contract signers allowlister:", contractSignersAllowlister);
        }
        if (contractSignersDisallowlister != address(0)) {
            console.log("Contract signers disallowlister:", contractSignersDisallowlister);
        }
        if (contractSignatureSigner != address(0)) {
            console.log("Contract signature signer:", contractSignatureSigner);
        }
        if (batchSigner != address(0)) {
            console.log("Batch signer:", batchSigner);
        }
    }

    /// @notice Deploys a contract from compiled bytecode artifact using CREATE
    /// @dev Reads bytecode from JSON artifact and deploys using inline assembly
    /// @param contractFileName Name of the contract's compiled artifact file (e.g., "GatewayWallet.json")
    /// @return addr The deployed contract address
    function _deployFromBytecode(string memory contractFileName) internal returns (address addr) {
        // Get project root directory and construct path to compiled contract artifact
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/compiled-contract-artifacts/", contractFileName);
        string memory json = vm.readFile(path);

        // Extract bytecode from the compiled contract artifact
        bytes memory bytecode = abi.decode(vm.parseJson(json, ".bytecode.object"), (bytes));

        // Deploy using CREATE opcode (not CREATE2)
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "Deployment failed");
    }

    /// @notice Logs the current state of the GatewayWallet before upgrade
    function _logCurrentState(address proxyAddress) internal view {
        GatewayWallet wallet = GatewayWallet(proxyAddress);

        console.log("Current owner:", wallet.owner());
        console.log("Current paused:", wallet.paused());
        console.log("Current domain:", wallet.domain());

        // Get current implementation from ERC1967 slot
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implBytes = vm.load(proxyAddress, implSlot);
        address currentImpl = address(uint160(uint256(implBytes)));
        console.log("Current implementation:", currentImpl);
    }

    /// @notice Validates the GatewayWallet state after upgrade
    function _validateUpgrade(
        address proxyAddress,
        address expectedImpl,
        address expectedOwner,
        address expectedAllowlister,
        address expectedDisallowlister,
        address expectedContractSignatureSigner,
        address expectedBatchSigner
    ) internal view {
        GatewayWallet wallet = GatewayWallet(proxyAddress);

        // Validate implementation was updated
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implBytes = vm.load(proxyAddress, implSlot);
        address actualImpl = address(uint160(uint256(implBytes)));
        require(actualImpl == expectedImpl, "Implementation address mismatch");
        console.log("[OK] Implementation updated to:", actualImpl);

        // Validate owner is unchanged
        address actualOwner = wallet.owner();
        require(actualOwner == expectedOwner, "Owner changed unexpectedly");
        console.log("[OK] Owner unchanged:", actualOwner);

        // Validate contract is not paused
        bool paused = wallet.paused();
        require(!paused, "Contract should not be paused after upgrade");
        console.log("[OK] Contract not paused");

        // Validate contract signers allowlister (if it was set)
        if (expectedAllowlister != address(0)) {
            address actualAllowlister = wallet.contractSignersAllowlister();
            require(actualAllowlister == expectedAllowlister, "Contract signers allowlister mismatch");
            console.log("[OK] Contract signers allowlister set to:", actualAllowlister);
        }

        // Validate contract signers disallowlister (if it was set)
        if (expectedDisallowlister != address(0)) {
            address actualDisallowlister = wallet.contractSignersDisallowlister();
            require(actualDisallowlister == expectedDisallowlister, "Contract signers disallowlister mismatch");
            console.log("[OK] Contract signers disallowlister set to:", actualDisallowlister);
        }

        // Validate contract signature signer was added (if it was set)
        if (expectedContractSignatureSigner != address(0)) {
            bool isContractSignatureSigner = wallet.isContractSignatureSigner(expectedContractSignatureSigner);
            require(isContractSignatureSigner, "Contract signature signer not registered");
            console.log("[OK] Contract signature signer registered:", expectedContractSignatureSigner);
        }

        // Validate batch signer was added (if it was set)
        if (expectedBatchSigner != address(0)) {
            bool isBatchSigner = wallet.isBatchSigner(expectedBatchSigner);
            require(isBatchSigner, "Batch signer not registered");
            console.log("[OK] Batch signer registered:", expectedBatchSigner);
        }

        // Validate domain is still set
        uint32 domain = wallet.domain();
        require(domain != 0, "Domain should be set");
        console.log("[OK] Domain:", domain);

        console.log("\nAll validations passed!");
    }
}
