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
import {EnvSelector, EnvConfig} from "script/000_Constants.sol";
import {BaseBytecodeDeployScript} from "script/BaseBytecodeDeployScript.sol";

/// @title UpgradeGatewayWallet
/// @notice Upgrade script for GatewayWallet implementation
/// @dev Deploys a new implementation and upgrades the proxy to use it
contract UpgradeGatewayWallet is BaseBytecodeDeployScript {
    /// @dev Environment selector for multi-environment deployment
    EnvSelector private envSelector;

    constructor() {
        envSelector = new EnvSelector();
    }

    /// @notice Main upgrade function that deploys new implementation and upgrades the proxy
    /// @dev Upgrade process:
    ///      1. Deploy new GatewayWallet implementation
    ///      2. Call upgradeToAndCall on the proxy to upgrade to new implementation
    ///      3. Update contract signers allowlister
    function run() public returns (address newImplAddress) {
        // Get the proxy address from environment variable
        address gatewayWalletProxy = vm.envAddress("GATEWAYMINTER_WALLET_ADDRESS");

        // Get the owner address who can perform upgrades
        address gatewayWalletOwner = vm.envAddress("GATEWAYWALLET_OWNER_ADDRESS");

        // Get environment configuration
        EnvConfig memory config = envSelector.getEnvironmentConfig();

        // Use environment-specific values
        address deployer = config.deployerAddress;
        address factory = config.factoryAddress;

        // Use the same salt as the original deployment
        // CREATE2 will automatically generate a different address because the bytecode has changed
        bytes32 newWalletImplSalt = config.walletSalt;

        // First, validate that the owner is properly configured
        require(gatewayWalletOwner != address(0), "GATEWAYWALLET_OWNER_ADDRESS not set");

        // Step 1: Deploy new GatewayWallet implementation (using deployer)
        vm.startBroadcast(deployer);
        newImplAddress = deploy(factory, "GatewayWallet.json", newWalletImplSalt, hex"");
        console.log("New GatewayWallet implementation address", newImplAddress);
        vm.stopBroadcast();

        // Step 2: Upgrade the proxy to the new implementation (using owner)
        vm.startBroadcast(gatewayWalletOwner);

        // In OpenZeppelin v5, we must use upgradeToAndCall even for simple upgrades
        // Pass empty data since we don't need to call any initialization function
        bytes memory upgradeCallData = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplAddress, hex"");

        // Execute the upgrade through the proxy
        (bool success, bytes memory returnData) = gatewayWalletProxy.call(upgradeCallData);
        require(success, string(abi.encodePacked("Upgrade failed: ", returnData)));

        console.log("Successfully upgraded GatewayWallet proxy to new implementation");
        console.log("Proxy address:", gatewayWalletProxy);
        console.log("New implementation address:", newImplAddress);

        vm.stopBroadcast();

        // Step 3: Update contract signers allowlister
        address contractSignersAllowlister = vm.envAddress("GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS");
        require(contractSignersAllowlister != address(0), "GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS not set");
        
        console.log("\nUpdating contract signers allowlister...");
        console.log("New allowlister address:", contractSignersAllowlister);
        
        // Start broadcast for the allowlister update
        vm.startBroadcast(gatewayWalletOwner);
        
        bytes memory updateAllowlisterCallData = abi.encodeWithSignature("updateContractSignersAllowlister(address)", contractSignersAllowlister);
        (bool updateSuccess, bytes memory updateReturnData) = gatewayWalletProxy.call(updateAllowlisterCallData);
        require(updateSuccess, string(abi.encodePacked("updateContractSignersAllowlister failed: ", updateReturnData)));
        
        console.log("Successfully updated contract signers allowlister");
        
        vm.stopBroadcast();
    }
}
