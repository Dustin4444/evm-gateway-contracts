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

/**
 * @title Constants
 * @notice Library containing environment-specific constants for deployment
 * @dev Defines constants for four environments: TESTNET_TESTING, TESTNET_STAGING, TESTNET_PROD and MAINNET_PROD
 */
library Constants {
    // Local environment constants
    bytes32 internal constant LOCAL_WALLET_SALT = bytes32(uint256(0));
    bytes32 internal constant LOCAL_MINTER_SALT = bytes32(uint256(1));
    bytes32 internal constant LOCAL_WALLET_PROXY_SALT = bytes32(uint256(0));
    bytes32 internal constant LOCAL_MINTER_PROXY_SALT = bytes32(uint256(1));

    // Testnet testing environment constants
    bytes32 internal constant TESTNET_TESTING_WALLET_SALT = bytes32(uint256(50));
    bytes32 internal constant TESTNET_TESTING_MINTER_SALT = bytes32(uint256(60));
    bytes32 internal constant TESTNET_TESTING_WALLET_PROXY_SALT =
        0xa4bfe213eb409980792c6ed28e67b1c200ae7b70ef17e8dbd9bb71dc40aeb3b5;
    bytes32 internal constant TESTNET_TESTING_MINTER_PROXY_SALT =
        0xe6f063b15e86756dc58c6434d88a1c5ab5b6a6f2dcf1fa3e039aa64508cd216c;
    address internal constant TESTNET_TESTING_CREATE2FACTORY_ADDRESS = 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2;
    address internal constant TESTNET_TESTING_DEPLOYER_ADDRESS = 0xD1e4098de8667a491Eb2Bf5acf09ED7F67260BCA;

    // Testnet staging environment constants
    bytes32 internal constant TESTNET_STAGING_WALLET_SALT = bytes32(uint256(10));
    bytes32 internal constant TESTNET_STAGING_MINTER_SALT = bytes32(uint256(20));
    bytes32 internal constant TESTNET_STAGING_WALLET_PROXY_SALT =
        0x3d21bf46d1a413d4915423a85add52e6df8923c76ec13fbc0a664cfe8d7f2304;
    bytes32 internal constant TESTNET_STAGING_MINTER_PROXY_SALT =
        0x7474fa96ff71c561dd1e5cb33805fa64a03b7bed60c04f53ad67b2cb19f8f433;
    address internal constant TESTNET_STAGING_CREATE2FACTORY_ADDRESS = 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2;
    address internal constant TESTNET_STAGING_DEPLOYER_ADDRESS = 0xD1e4098de8667a491Eb2Bf5acf09ED7F67260BCA;

    // Testnet prod environment constants
    bytes32 internal constant TESTNET_PROD_WALLET_SALT = bytes32(uint256(30));
    bytes32 internal constant TESTNET_PROD_MINTER_SALT = bytes32(uint256(40));
    bytes32 internal constant TESTNET_PROD_WALLET_PROXY_SALT =
        0x2773766c22eb359b605cbfffc7491bab3abe5c6d8ef9c3193e7226605a809ae1;
    bytes32 internal constant TESTNET_PROD_MINTER_PROXY_SALT =
        0x28e5e07be0c6c7ee178fca3ce72763253a5ddacdd2542cd38507d48c49a616f0;
    address internal constant TESTNET_PROD_CREATE2FACTORY_ADDRESS = 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2;
    address internal constant TESTNET_PROD_DEPLOYER_ADDRESS = 0xD1e4098de8667a491Eb2Bf5acf09ED7F67260BCA;

    // Mainnet prod environment constants
    bytes32 internal constant MAINNET_PROD_WALLET_SALT = bytes32(uint256(4));
    bytes32 internal constant MAINNET_PROD_MINTER_SALT = bytes32(uint256(5));
    bytes32 internal constant MAINNET_PROD_WALLET_PROXY_SALT =
        0x7ca52db4fc3f0e0f1f0af08e43e70f149bfbe314de9a1ab13acbe1fc122e8238;
    bytes32 internal constant MAINNET_PROD_MINTER_PROXY_SALT =
        0x6df87339f2bf63538063427ae112ca61dad04e4d35f7f4984fa3f924f7207d67;
    address internal constant MAINNET_PROD_CREATE2FACTORY_ADDRESS = 0xe7b84D8846c96Bb83155Da5537625c75e42d6E42;
    address internal constant MAINNET_PROD_DEPLOYER_ADDRESS = 0xadB384F7fa7486422051D2a896417EAAb9E5A9D1;
}

/**
 * @title EnvConfig
 * @notice Configuration struct that holds all environment-specific parameters
 * @dev Used to pass environment configuration between contracts in a structured way
 * @param walletSalt The base salt value used for non proxy contract deployment
 * @param minterSalt The base salt value used for non proxy contract deployment
 * @param walletProxySalt The salt value used for GatewayWallet proxy deployment
 * @param minterProxySalt The salt value used for GatewayMinter proxy deployment
 * @param factoryAddress The CREATE2 factory address for deterministic deployment
 * @param deployerAddress The address that will deploy the contracts
 */
struct EnvConfig {
    bytes32 walletSalt;
    bytes32 minterSalt;
    bytes32 walletProxySalt;
    bytes32 minterProxySalt;
    address factoryAddress;
    address deployerAddress;
}

/**
 * @title EnvSelector
 * @notice Helper contract to select environment configuration based on ENV variable
 * @dev Provides configuration for different deployment environments (LOCAL, TESTNET_TESTING, TESTNET_STAGING, TESTNET_PROD, MAINNET_PROD)
 *      The environment is selected by setting the ENV environment variable before running the script
 *      Default environment is LOCAL if ENV is not specified
 */
contract EnvSelector is Script {
    /**
     * @notice Get configuration for the selected environment
     * @dev Reads ENV environment variable and returns the appropriate configuration
     * @return config EnvConfig struct containing environment-specific parameters
     */
    function getEnvironmentConfig() public view returns (EnvConfig memory config) {
        // Read environment from forge environment variable, default to LOCAL
        string memory env = vm.envOr("ENV", string("LOCAL"));
        console.log("Selected environment:", env);

        // Select environment configuration based on ENV value
        if (keccak256(bytes(env)) == keccak256(bytes("LOCAL"))) {
            config = getLocalConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("TESTNET_TESTING"))) {
            config = getTestnetTestingConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("TESTNET_STAGING"))) {
            config = getTestnetStagingConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("TESTNET_PROD"))) {
            config = getTestnetProdConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("MAINNET_PROD"))) {
            config = getMainnetProdConfig();
        }
    }

    /**
     * @notice Get configuration for the LOCAL environment
     * @dev Salt values for LOCAL development environment
     * @return EnvConfig with LOCAL-specific values
     */
    function getLocalConfig() public view returns (EnvConfig memory) {
        address localCreate2Factory = vm.envAddress("LOCAL_CREATE2_FACTORY_ADDRESS");
        address localDeployer = vm.envAddress("LOCAL_DEPLOYER_ADDRESS");

        return EnvConfig({
            walletSalt: Constants.LOCAL_WALLET_SALT,
            minterSalt: Constants.LOCAL_MINTER_SALT,
            walletProxySalt: Constants.LOCAL_WALLET_PROXY_SALT,
            minterProxySalt: Constants.LOCAL_MINTER_PROXY_SALT,
            factoryAddress: localCreate2Factory,
            deployerAddress: localDeployer
        });
    }

    /**
     * @notice Get configuration for the TESTNET_TESTING environment
     * @return EnvConfig with TESTNET_TESTING-specific values
     */
    function getTestnetTestingConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            walletSalt: Constants.TESTNET_TESTING_WALLET_SALT,
            minterSalt: Constants.TESTNET_TESTING_MINTER_SALT,
            walletProxySalt: Constants.TESTNET_TESTING_WALLET_PROXY_SALT,
            minterProxySalt: Constants.TESTNET_TESTING_MINTER_PROXY_SALT,
            factoryAddress: Constants.TESTNET_TESTING_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.TESTNET_TESTING_DEPLOYER_ADDRESS
        });
    }

    /**
     * @notice Get configuration for the TESTNET_STAGING environment
     * @dev Salt value for TESTNET_STAGING is 0
     * @return EnvConfig with TESTNET_STAGING-specific values
     */
    function getTestnetStagingConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            walletSalt: Constants.TESTNET_STAGING_WALLET_SALT,
            minterSalt: Constants.TESTNET_STAGING_MINTER_SALT,
            walletProxySalt: Constants.TESTNET_STAGING_WALLET_PROXY_SALT,
            minterProxySalt: Constants.TESTNET_STAGING_MINTER_PROXY_SALT,
            factoryAddress: Constants.TESTNET_STAGING_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.TESTNET_STAGING_DEPLOYER_ADDRESS
        });
    }

    /**
     * @notice Get configuration for the TESTNET_PROD environment
     * @dev Salt value for TESTNET_PROD is 1
     * @return EnvConfig with TESTNET_PROD-specific values
     */
    function getTestnetProdConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            walletSalt: Constants.TESTNET_PROD_WALLET_SALT,
            minterSalt: Constants.TESTNET_PROD_MINTER_SALT,
            walletProxySalt: Constants.TESTNET_PROD_WALLET_PROXY_SALT,
            minterProxySalt: Constants.TESTNET_PROD_MINTER_PROXY_SALT,
            factoryAddress: Constants.TESTNET_PROD_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.TESTNET_PROD_DEPLOYER_ADDRESS
        });
    }

    /**
     * @notice Get configuration for the PROD environment
     * @dev Salt value for PROD is 2
     * @return EnvConfig with PROD-specific values
     */
    function getMainnetProdConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            walletSalt: Constants.MAINNET_PROD_WALLET_SALT,
            minterSalt: Constants.MAINNET_PROD_MINTER_SALT,
            walletProxySalt: Constants.MAINNET_PROD_WALLET_PROXY_SALT,
            minterProxySalt: Constants.MAINNET_PROD_MINTER_PROXY_SALT,
            factoryAddress: Constants.MAINNET_PROD_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.MAINNET_PROD_DEPLOYER_ADDRESS
        });
    }
}
