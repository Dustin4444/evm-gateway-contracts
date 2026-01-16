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

import {Test} from "forge-std/Test.sol";
import {DeployGatewayWallet} from "script/001_DeployGatewayWallet.sol";
import {Create2Factory} from "script/Create2Factory.sol";

contract DeployGatewayWalletTest is Test {
    DeployGatewayWallet private deployer;

    function setUp() public {
        // Setup test environment variables
        vm.setEnv("ENV", "LOCAL");

        // Create a factory for deterministic deployments
        address deployerAddress = makeAddr("deployer");
        Create2Factory factory = new Create2Factory(deployerAddress);

        // Set required environment variables
        vm.setEnv("LOCAL_CREATE2_FACTORY_ADDRESS", vm.toString(address(factory)));
        vm.setEnv("LOCAL_DEPLOYER_ADDRESS", vm.toString(deployerAddress));
        vm.setEnv("GATEWAYWALLET_OWNER_ADDRESS", vm.toString(makeAddr("walletOwner")));
        vm.setEnv("GATEWAYWALLET_PAUSER_ADDRESS", vm.toString(makeAddr("walletPauser")));
        vm.setEnv("GATEWAYWALLET_DENYLISTER_ADDRESS", vm.toString(makeAddr("walletDenylister")));
        vm.setEnv("GATEWAYWALLET_MINTER_ADDRESS", vm.toString(makeAddr("walletMinter")));
        vm.setEnv("GATEWAYWALLET_SUPPORTED_TOKEN_1", vm.toString(makeAddr("token1")));
        vm.setEnv("GATEWAYWALLET_DOMAIN", "1");
        vm.setEnv("GATEWAYWALLET_WITHDRAWAL_DELAY", "86400"); // 1 day
        vm.setEnv("GATEWAYWALLET_BURNSIGNER_ADDRESS", vm.toString(makeAddr("burnSigner")));
        vm.setEnv("GATEWAYWALLET_FEERECIPIENT_ADDRESS", vm.toString(makeAddr("feeRecipient")));
        vm.setEnv(
            "GATEWAYWALLET_CONTRACT_SIGNERS_ALLOWLISTER_ADDRESS", vm.toString(makeAddr("contractSignersAllowlister"))
        );
        vm.setEnv("GATEWAYWALLET_BATCHSIGNER_ADDRESS", vm.toString(makeAddr("batchSigner")));

        // Initialize the deployer script
        deployer = new DeployGatewayWallet();
    }

    function testDeployGatewayWallet() public {
        // Execute the deployment script and verify the addresses.
        (address placeholderAddress, address implAddress, address proxyAddress) = deployer.run();
        assertEq(placeholderAddress, 0x863dBa32816075Df59609319718449618Eeb6Eb7);
        assertEq(implAddress, 0xD6c2F4aB2ff242834dBeC5a304Bf4BA35fE4889e);
        assertEq(proxyAddress, 0x82315cB7F3598180ED882904D1bDf4ee68139db5);
    }
}
