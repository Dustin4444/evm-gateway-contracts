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
import {GatewayWallet, GatewayWalletInitConfig} from "src/GatewayWallet.sol";

/// @title DeployGatewayWallet
/// @notice Deployment script for GatewayWallet implementation and proxy with initialization
/// @dev Deploys in sequence:
///      1. UpgradeablePlaceholder implementation (temporary implementation)
///      2. GatewayWallet implementation (actual implementation)
///      3. ERC1967Proxy pointing to placeholder, then upgrades to actual implementation
contract DeployGatewayWallet is BaseBytecodeDeployScript {
    /// @dev Environment selector for multi-environment deployment
    EnvSelector private envSelector;

    constructor() {
        envSelector = new EnvSelector();
    }

    /// @dev Prepares initialization data for GatewayWallet
    /// @return Encoded initialization call data including all configuration parameters
    function prepareInitData() internal view returns (bytes memory) {
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = vm.envAddress("GATEWAYWALLET_SUPPORTED_TOKEN_1");

        GatewayWalletInitConfig memory config = GatewayWalletInitConfig({
            pauser: vm.envAddress("GATEWAYWALLET_PAUSER_ADDRESS"),
            denylister: vm.envAddress("GATEWAYWALLET_DENYLISTER_ADDRESS"),
            supportedTokens: supportedTokens,
            domain: uint32(vm.envUint("GATEWAYWALLET_DOMAIN")),
            withdrawalDelay: vm.envUint("GATEWAYWALLET_WITHDRAWAL_DELAY"),
            burnSigner: vm.envAddress("GATEWAYWALLET_BURNSIGNER_ADDRESS"),
            feeRecipient: vm.envAddress("GATEWAYWALLET_FEERECIPIENT_ADDRESS"),
            contractSignersAllowlister: vm.envAddress("GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS"),
            contractSignersDisallowlister: vm.envAddress("GATEWAYWALLET_CONTRACT_SIGNERS_DISALLOWLISTER_ADDRESS"),
            contractSignatureSigner: vm.envAddress("GATEWAYWALLET_CONTRACT_SIGNATURE_SIGNER_ADDRESS"),
            batchSigner: vm.envAddress("GATEWAYWALLET_BATCHSIGNER_ADDRESS")
        });

        return abi.encodeCall(GatewayWallet.initialize, (config));
    }

    /// @notice Main deployment function that sets up the entire GatewayWallet system
    /// @dev Deployment process:
    ///      1. Deploy placeholder implementation (minimal implementation for proxy initialization)
    ///      2. Deploy actual GatewayWallet implementation
    ///      3. Prepare proxy deployment data
    ///      4. Deploy and initialize proxy with prepared calls
    function run() public returns (address placeholderAddress, address implAddress, address proxyAddress) {
        address gatewayWalletOwner = vm.envAddress("GATEWAYWALLET_OWNER_ADDRESS");

        // Get environment configuration
        EnvConfig memory config = envSelector.getEnvironmentConfig();

        // Use environment-specific values
        address deployer = config.deployerAddress;
        address factory = config.factoryAddress;
        bytes32 walletPlaceholderSalt = config.walletSalt;
        bytes32 walletImplSalt = config.walletSalt;
        bytes32 walletProxySalt = config.walletProxySalt;

        vm.startBroadcast(deployer);

        // Step 1: Deploy placeholder implementation (minimal implementation for proxy initialization)
        placeholderAddress = deploy(factory, "UpgradeablePlaceholder.json", walletPlaceholderSalt, hex"");
        console.log("GatewayWallet placeholder address", placeholderAddress);

        // Step 2: Deploy actual GatewayWallet implementation
        implAddress = deploy(factory, "GatewayWallet.json", walletImplSalt, hex"");
        console.log("GatewayWallet implementation address", implAddress);

        // Step 3: Prepare proxy deployment data

        // Prepare UpgradeablePlaceholder constructor call data for initialization
        bytes memory constructorCallData =
            abi.encode(placeholderAddress, abi.encodeWithSignature("initialize(address)", factory));

        bytes[] memory proxyMultiCallData = new bytes[](2);
        // First call: Upgrade to actual implementation with initialization
        proxyMultiCallData[0] =
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", implAddress, prepareInitData());

        // Second call: Transfer ownership to final owner
        proxyMultiCallData[1] = abi.encodeWithSignature("transferOwnership(address)", gatewayWalletOwner);

        // Step 4: Deploy and initialize proxy with prepared calls
        proxyAddress =
            deployAndMultiCall(factory, "ERC1967Proxy.json", walletProxySalt, constructorCallData, proxyMultiCallData);
        console.log("GatewayWallet proxy address", proxyAddress);
        vm.stopBroadcast();
    }
}
