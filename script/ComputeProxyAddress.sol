// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.29;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title ComputeProxyAddress
 * @notice Verification script that computes expected proxy addresses for all environments
 * @dev This script reads compiled artifacts and verifies that proxy addresses match expected values
 *      for TESTNET_TESTING, TESTNET_STAGING, TESTNET_PROD, and MAINNET_PROD environments.
 *
 *      Usage: forge script script/ComputeProxyAddress.sol -vvv
 *
 *      Expected: All environments show SUCCESS for both wallet and minter proxies
 */
contract ComputeProxyAddress is Script {
    struct Environment {
        string name;
        address factory;
        bytes32 walletSalt;
        bytes32 walletProxySalt;
        address expectedWalletProxy;
        bytes32 minterSalt;
        bytes32 minterProxySalt;
        address expectedMinterProxy;
    }

    function run() public view {
        // Get project root directory and construct paths
        string memory root = vm.projectRoot();
        string memory proxyPath = string.concat(root, "/script/compiled-contract-artifacts/ERC1967Proxy.json");
        string memory placeholderPath =
            string.concat(root, "/script/compiled-contract-artifacts/UpgradeablePlaceholder.json");

        bytes memory proxyInitCode = abi.decode(vm.parseJson(vm.readFile(proxyPath), ".bytecode.object"), (bytes));
        bytes memory placeholderInitCode =
            abi.decode(vm.parseJson(vm.readFile(placeholderPath), ".bytecode.object"), (bytes));

        bytes32 placeholderHash = keccak256(placeholderInitCode);

        // Define all environments
        Environment[4] memory environments;

        // TESTNET_TESTING
        environments[0] = Environment({
            name: "TESTNET_TESTING",
            factory: 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2,
            walletSalt: bytes32(uint256(50)),
            walletProxySalt: 0xa4bfe213eb409980792c6ed28e67b1c200ae7b70ef17e8dbd9bb71dc40aeb3b5,
            expectedWalletProxy: 0x7E77777D8b52A0a702530890F3C34DBA0d9E7877,
            minterSalt: bytes32(uint256(60)),
            minterProxySalt: 0xe6f063b15e86756dc58c6434d88a1c5ab5b6a6f2dcf1fa3e039aa64508cd216c,
            expectedMinterProxy: 0x7E22222B9698cCEDb763bEA18F8E6a09FD4e7138
        });

        // TESTNET_STAGING
        environments[1] = Environment({
            name: "TESTNET_STAGING",
            factory: 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2,
            walletSalt: bytes32(uint256(10)),
            walletProxySalt: 0x3d21bf46d1a413d4915423a85add52e6df8923c76ec13fbc0a664cfe8d7f2304,
            expectedWalletProxy: 0x557777735b1Dd18194F1b84256be2A3CDee6CB6F,
            minterSalt: bytes32(uint256(20)),
            minterProxySalt: 0x7474fa96ff71c561dd1e5cb33805fa64a03b7bed60c04f53ad67b2cb19f8f433,
            expectedMinterProxy: 0x552222279206Cb0434128e0caE4558a25779c79F
        });

        // TESTNET_PROD
        environments[2] = Environment({
            name: "TESTNET_PROD",
            factory: 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2,
            walletSalt: bytes32(uint256(30)),
            walletProxySalt: 0x2773766c22eb359b605cbfffc7491bab3abe5c6d8ef9c3193e7226605a809ae1,
            expectedWalletProxy: 0x0077777d7EBA4688BDeF3E311b846F25870A19B9,
            minterSalt: bytes32(uint256(40)),
            minterProxySalt: 0x28e5e07be0c6c7ee178fca3ce72763253a5ddacdd2542cd38507d48c49a616f0,
            expectedMinterProxy: 0x0022222ABE238Cc2C7Bb1f21003F0a260052475B
        });

        // MAINNET_PROD
        environments[3] = Environment({
            name: "MAINNET_PROD",
            factory: 0xe7b84D8846c96Bb83155Da5537625c75e42d6E42,
            walletSalt: bytes32(uint256(4)),
            walletProxySalt: 0x7ca52db4fc3f0e0f1f0af08e43e70f149bfbe314de9a1ab13acbe1fc122e8238,
            expectedWalletProxy: 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE,
            minterSalt: bytes32(uint256(5)),
            minterProxySalt: 0x6df87339f2bf63538063427ae112ca61dad04e4d35f7f4984fa3f924f7207d67,
            expectedMinterProxy: 0x2222222d7164433c4C09B0b0D809a9b52C04C205
        });

        console.log("===========================================");
        console.log("Verifying Proxy Addresses for All Environments");
        console.log("===========================================");
        console.log("");

        // Verify all environments
        for (uint256 i = 0; i < environments.length; i++) {
            verifyEnvironment(environments[i], proxyInitCode, placeholderHash);
            if (i < environments.length - 1) {
                console.log("");
                console.log("-------------------------------------------");
                console.log("");
            }
        }
    }

    function verifyEnvironment(Environment memory env, bytes memory proxyInitCode, bytes32 placeholderHash)
        internal
        pure
    {
        console.log(string.concat("Environment: ", env.name));
        console.log("===========================================");

        // Verify wallet proxy
        address walletPlaceholderAddr = computeCreate2Address(env.factory, env.walletSalt, placeholderHash);
        bytes memory walletConstructorArgs =
            abi.encode(walletPlaceholderAddr, abi.encodeWithSignature("initialize(address)", env.factory));
        bytes32 walletProxyInitCodeHash = keccak256(abi.encodePacked(proxyInitCode, walletConstructorArgs));
        address walletProxyAddr = computeCreate2Address(env.factory, env.walletProxySalt, walletProxyInitCodeHash);

        console.log("Computed wallet proxy:", walletProxyAddr);
        console.log("Expected wallet proxy:", env.expectedWalletProxy);
        if (walletProxyAddr == env.expectedWalletProxy) {
            console.log("SUCCESS: Wallet proxy address matches!");
        } else {
            console.log("MISMATCH: Wallet proxy address does not match");
        }

        console.log("");

        // Verify minter proxy
        address minterPlaceholderAddr = computeCreate2Address(env.factory, env.minterSalt, placeholderHash);
        bytes memory minterConstructorArgs =
            abi.encode(minterPlaceholderAddr, abi.encodeWithSignature("initialize(address)", env.factory));
        bytes32 minterProxyInitCodeHash = keccak256(abi.encodePacked(proxyInitCode, minterConstructorArgs));
        address minterProxyAddr = computeCreate2Address(env.factory, env.minterProxySalt, minterProxyInitCodeHash);

        console.log("Computed minter proxy:", minterProxyAddr);
        console.log("Expected minter proxy:", env.expectedMinterProxy);
        if (minterProxyAddr == env.expectedMinterProxy) {
            console.log("SUCCESS: Minter proxy address matches!");
        } else {
            console.log("MISMATCH: Minter proxy address does not match");
        }
    }

    function computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
