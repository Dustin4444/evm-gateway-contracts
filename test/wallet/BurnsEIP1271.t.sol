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

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {BurnIntentLib} from "src/lib/BurnIntentLib.sol";
import {BurnIntent, BurnIntentSet} from "src/lib/BurnIntents.sol";
import {TransferSpec, TRANSFER_SPEC_VERSION} from "src/lib/TransferSpec.sol";
import {Burns} from "src/modules/wallet/Burns.sol";
import {FiatTokenV2_2} from "test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";
import {SignatureTestUtils} from "test/util/SignatureTestUtils.sol";

// Mock EIP-1271 contract for testing
contract MockEIP1271Signer is IERC1271 {
    address public owner;
    mapping(bytes32 => bool) public validSignatures;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        // First check if this specific hash is marked as valid
        if (validSignatures[hash]) {
            return IERC1271.isValidSignature.selector;
        }

        // Otherwise check if signature was made by owner
        address recoveredSigner = ECDSA.recover(hash, signature);
        if (recoveredSigner == owner) {
            return IERC1271.isValidSignature.selector;
        }

        return bytes4(0);
    }
}

// Mock contract that always returns invalid for EIP-1271
contract MockInvalidEIP1271Signer is IERC1271 {
    function isValidSignature(bytes32, bytes calldata) external pure override returns (bytes4) {
        return bytes4(0); // Always invalid
    }
}

contract GatewayWalletBurnsEIP1271Test is SignatureTestUtils, DeployUtils {
    using MessageHashUtils for bytes32;

    uint32 private domain;
    address private owner = makeAddr("owner");
    address private feeRecipient = makeAddr("feeRecipient");
    address private contractOwner = makeAddr("contractOwner");
    uint256 private contractOwnerKey = uint256(keccak256(abi.encodePacked("contractOwner")));
    address private depositor = makeAddr("depositor");
    uint256 private depositorKey = uint256(keccak256(abi.encodePacked("depositor")));
    address private whitelister = makeAddr("whitelister");
    uint256 private burnSignerKey;
    address private burnSigner;

    FiatTokenV2_2 private usdc;
    GatewayWallet private wallet;
    MockEIP1271Signer private validContractSigner;
    MockInvalidEIP1271Signer private invalidContractSigner;

    uint256 private defaultMaxBlockHeightOffset = 100;
    uint256 private defaultMaxFee = 10 ** 6;
    uint256 private depositorInitialBalance = 5000 * 10 ** 6;

    function setUp() public {
        domain = ForkTestUtils.forkVars().domain;
        usdc = FiatTokenV2_2(ForkTestUtils.forkVars().usdc);
        wallet = deployWalletOnly(owner, domain);

        (burnSigner, burnSignerKey) = makeAddrAndKey("burnSigner");

        // Deploy mock EIP-1271 contracts
        validContractSigner = new MockEIP1271Signer(contractOwner);
        invalidContractSigner = new MockInvalidEIP1271Signer();

        vm.startPrank(owner);
        {
            wallet.addSupportedToken(address(usdc));
            wallet.addBurnSigner(burnSigner);
            wallet.updateFeeRecipient(feeRecipient);
            wallet.updateContractSignersWhitelister(whitelister);
        }
        vm.stopPrank();

        // Setup USDC burning capability
        _setupUSDCBurning();

        // Fund depositor and deposit to wallet
        deal(address(usdc), depositor, depositorInitialBalance, true);
        vm.startPrank(depositor);
        {
            usdc.approve(address(wallet), type(uint256).max);
            wallet.deposit(address(usdc), depositorInitialBalance);
            // Add delegate authorization for both contract signers
            wallet.addDelegate(address(usdc), address(validContractSigner));
            wallet.addDelegate(address(usdc), address(invalidContractSigner));
        }
        vm.stopPrank();

        // Whitelist the valid contract signer
        vm.prank(whitelister);
        wallet.whitelistContractSigner(address(validContractSigner));
    }

    function _setupUSDCBurning() internal {
        address masterMinterAddr = usdc.masterMinter();
        if (masterMinterAddr.code.length > 0) {
            // Handle MasterMinter contract
            vm.startPrank(masterMinterAddr);
            try usdc.configureMinter(address(wallet), 0) {}
            catch {
                // If that fails, it might be controlled by a different owner
                vm.stopPrank();
                // Try to get the actual owner and configure through them
                try usdc.owner() returns (address usdcOwner) {
                    vm.startPrank(usdcOwner);
                    usdc.configureMinter(address(wallet), 0);
                    vm.stopPrank();
                } catch {
                    // Last resort: try to configure as the master minter directly
                    vm.startPrank(masterMinterAddr);
                    usdc.configureMinter(address(wallet), 0);
                    vm.stopPrank();
                }
            }
            vm.stopPrank();
        } else {
            // Handle EOA master minter
            vm.startPrank(masterMinterAddr);
            usdc.configureMinter(address(wallet), 0);
            vm.stopPrank();
        }
    }

    function _createBurnIntent(address signer, uint256 value) internal returns (BurnIntent memory) {
        return BurnIntent({
            maxBlockHeight: block.number + defaultMaxBlockHeightOffset,
            maxFee: defaultMaxFee,
            spec: TransferSpec({
                version: TRANSFER_SPEC_VERSION,
                sourceDomain: domain,
                destinationDomain: domain + 1,
                sourceContract: AddressLib._addressToBytes32(address(wallet)),
                destinationContract: AddressLib._addressToBytes32(makeAddr("destContract")),
                sourceToken: AddressLib._addressToBytes32(address(usdc)),
                destinationToken: AddressLib._addressToBytes32(address(usdc)),
                sourceDepositor: AddressLib._addressToBytes32(depositor),
                destinationRecipient: bytes32(uint256(uint160(makeAddr("recipient")))),
                sourceSigner: AddressLib._addressToBytes32(signer),
                destinationCaller: AddressLib._addressToBytes32(makeAddr("caller")),
                value: value,
                salt: keccak256(abi.encode("salt", signer, value)),
                hookData: ""
            })
        });
    }

    function _signIntentWithEIP1271(bytes memory intentOrIntentSet, address /* contractSigner */ )
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(intentOrIntentSet)
        );

        // Sign with the contract owner's key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(contractOwnerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signIntentWithEOA(bytes memory intentOrIntentSet, uint256 signerKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(intentOrIntentSet)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signBurnCall(bytes memory burnCalldata) internal view returns (bytes memory) {
        bytes32 hash = keccak256(burnCalldata).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(burnSignerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _executeBurn(bytes memory intent, bytes memory intentSignature, uint256 fee) internal {
        bytes memory burnCalldata = abi.encode(
            new bytes[](1), // intents array with one element
            new bytes[](1), // signatures array with one element
            new uint256[][](1) // fees array with one sub-array
        );

        // Properly encode the arrays
        bytes[] memory intents = new bytes[](1);
        intents[0] = intent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = intentSignature;

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = fee;

        burnCalldata = abi.encode(intents, signatures, fees);
        bytes memory burnSignature = _signBurnCall(burnCalldata);

        wallet.gatewayBurn(burnCalldata, burnSignature);
    }

    // ===== Basic EIP-1271 Functionality Tests =====

    function test_burnIntent_withWhitelistedContractSigner_success() public {
        // Create burn intent with whitelisted contract as signer
        BurnIntent memory intent = _createBurnIntent(address(validContractSigner), 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Sign with EIP-1271
        bytes memory signature = _signIntentWithEIP1271(encodedIntent, address(validContractSigner));

        // Record initial state
        uint256 initialAvailable = wallet.availableBalance(address(usdc), depositor);
        uint256 initialSupply = usdc.totalSupply();

        // Expect burn event with contract as signer (check all fields except exact hash)
        vm.expectEmit(true, true, false, true);
        emit Burns.GatewayBurned(
            address(usdc),
            depositor,
            bytes32(0), // Skip exact hash check since makeAddr generates different values
            intent.spec.destinationDomain,
            intent.spec.destinationRecipient,
            address(validContractSigner), // Contract should be the signer
            1000e6,
            0.5e6,
            1000.5e6,
            0
        );

        // Execute burn
        _executeBurn(encodedIntent, signature, 0.5e6);

        // Verify balances
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialAvailable - 1000.5e6,
            "Available balance should decrease"
        );

        assertEq(usdc.totalSupply(), initialSupply - 1000e6, "USDC total supply should decrease");
    }

    function test_burnIntent_withNonWhitelistedContract_fallsBackToECDSA() public {
        // Create burn intent with non-whitelisted contract as signer
        BurnIntent memory intent = _createBurnIntent(address(invalidContractSigner), 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Sign with random EOA key (will use ECDSA recovery)
        uint256 randomKey = uint256(keccak256("randomSignerKey"));
        bytes memory signature = _signIntentWithEOA(encodedIntent, randomKey);

        // Get what address the signature would recover to
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(encodedIntent));
        address recoveredSigner = ECDSA.recover(digest, signature);

        // Should revert because source signer in intent != recovered signer from ECDSA
        vm.expectRevert(
            abi.encodeWithSelector(
                Burns.InvalidIntentSourceSignerAtIndex.selector,
                0,
                address(invalidContractSigner), // source signer in intent
                recoveredSigner // recovered from ECDSA
            )
        );

        _executeBurn(encodedIntent, signature, 0.5e6);
    }

    function test_burnIntent_withEOASigner_usesECDSARecovery() public {
        // Create burn intent with EOA as signer
        BurnIntent memory intent = _createBurnIntent(depositor, 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Sign with EOA private key
        bytes memory signature = _signIntentWithEOA(encodedIntent, depositorKey);

        // Record initial state
        uint256 initialAvailable = wallet.availableBalance(address(usdc), depositor);
        uint256 initialSupply = usdc.totalSupply();

        // Expect burn event with EOA as signer (check all fields except exact hash)
        vm.expectEmit(true, true, false, true);
        emit Burns.GatewayBurned(
            address(usdc),
            depositor,
            bytes32(0), // Skip exact hash check since makeAddr generates different values
            intent.spec.destinationDomain,
            intent.spec.destinationRecipient,
            depositor, // EOA should be the signer
            1000e6,
            0.5e6,
            1000.5e6,
            0
        );

        // Execute burn
        _executeBurn(encodedIntent, signature, 0.5e6);

        // Verify balances
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialAvailable - 1000.5e6,
            "Available balance should decrease"
        );

        assertEq(usdc.totalSupply(), initialSupply - 1000e6, "USDC total supply should decrease");
    }

    // ===== Error Cases =====

    function test_burnIntent_withInvalidContractSignature_reverts() public {
        // Create burn intent with whitelisted contract as signer
        BurnIntent memory intent = _createBurnIntent(address(validContractSigner), 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Create invalid signature (wrong key)
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(encodedIntent));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256("wrongKey")), digest);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Should revert with InvalidSignature
        vm.expectRevert(Burns.InvalidSignature.selector);
        _executeBurn(encodedIntent, invalidSignature, 0.5e6);
    }

    function test_burnIntent_withContractThatReturnsInvalid_reverts() public {
        // First whitelist the invalid contract signer
        vm.prank(whitelister);
        wallet.whitelistContractSigner(address(invalidContractSigner));

        // Add delegate authorization
        vm.prank(depositor);
        wallet.addDelegate(address(usdc), address(invalidContractSigner));

        uint256 burnValue = 1000e6;
        uint256 fee = 0.5e6;

        // Create burn intent with invalid contract as signer
        BurnIntent memory intent = _createBurnIntent(address(invalidContractSigner), burnValue);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Sign with any key (contract will return invalid anyway)
        bytes memory signature = _signIntentWithEIP1271(encodedIntent, address(invalidContractSigner));

        // Should revert with InvalidSignature
        vm.expectRevert(Burns.InvalidSignature.selector);
        _executeBurn(encodedIntent, signature, fee);
    }

    // ===== Intent Set Tests =====

    function test_burnIntentSet_withWhitelistedContractSigner_success() public {
        // Create two burn intents with same contract signer
        BurnIntent memory intent1 = _createBurnIntent(address(validContractSigner), 1000e6);
        BurnIntent memory intent2 = _createBurnIntent(address(validContractSigner), 500e6);

        // Modify intent2 to have different recipient to make it unique
        intent2.spec.destinationRecipient = bytes32(uint256(uint160(makeAddr("recipient2"))));
        intent2.spec.salt = keccak256(abi.encode("salt2", address(validContractSigner), 500e6));

        BurnIntent[] memory intents = new BurnIntent[](2);
        intents[0] = intent1;
        intents[1] = intent2;

        BurnIntentSet memory intentSet = BurnIntentSet({intents: intents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        // Sign with EIP-1271
        bytes memory signature = _signIntentWithEIP1271(encodedIntentSet, address(validContractSigner));

        // Record initial state
        uint256 initialAvailable = wallet.availableBalance(address(usdc), depositor);
        uint256 initialSupply = usdc.totalSupply();

        // Execute burn
        bytes[] memory intentArray = new bytes[](1);
        intentArray[0] = encodedIntentSet;

        bytes[] memory signatureArray = new bytes[](1);
        signatureArray[0] = signature;

        uint256[][] memory feeArray = new uint256[][](1);
        feeArray[0] = new uint256[](2);
        feeArray[0][0] = 0.5e6;
        feeArray[0][1] = 0.3e6;

        bytes memory burnCalldata = abi.encode(intentArray, signatureArray, feeArray);
        bytes memory burnSignature = _signBurnCall(burnCalldata);

        wallet.gatewayBurn(burnCalldata, burnSignature);

        // Verify balances - total burn 1500e6, total fee 0.8e6
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialAvailable - 1500.8e6,
            "Available balance should decrease"
        );

        assertEq(usdc.totalSupply(), initialSupply - 1500e6, "USDC total supply should decrease");
    }

    function test_burnIntentSet_withMixedSigners_reverts() public {
        // Create intents with different signers (this should fail)
        BurnIntent memory intent1 = _createBurnIntent(address(validContractSigner), 1000e6);
        BurnIntent memory intent2 = _createBurnIntent(depositor, 500e6); // Different signer

        BurnIntent[] memory intents = new BurnIntent[](2);
        intents[0] = intent1;
        intents[1] = intent2;

        BurnIntentSet memory intentSet = BurnIntentSet({intents: intents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        // Sign with contract (this matches first intent)
        bytes memory signature = _signIntentWithEIP1271(encodedIntentSet, address(validContractSigner));

        // Should revert because second intent has different signer
        vm.expectRevert(
            abi.encodeWithSelector(
                Burns.InvalidIntentSourceSignerAtIndex.selector, 1, depositor, address(validContractSigner)
            )
        );

        _executeBurnIntentSet(encodedIntentSet, signature);
    }

    function _executeBurnIntentSet(bytes memory intentSet, bytes memory signature) internal {
        bytes[] memory intentArray = new bytes[](1);
        intentArray[0] = intentSet;

        bytes[] memory signatureArray = new bytes[](1);
        signatureArray[0] = signature;

        uint256[][] memory feeArray = new uint256[][](1);
        feeArray[0] = new uint256[](2);
        feeArray[0][0] = 0.5e6;
        feeArray[0][1] = 0.3e6;

        bytes memory burnCalldata = abi.encode(intentArray, signatureArray, feeArray);
        bytes memory burnSignature = _signBurnCall(burnCalldata);

        wallet.gatewayBurn(burnCalldata, burnSignature);
    }

    // ===== Helper Function Tests =====

    function test_getSourceSigner_withContractSigner() public {
        BurnIntent memory intent = _createBurnIntent(address(validContractSigner), 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        address sourceSigner = BurnIntentLib.getSourceSigner(encodedIntent);
        assertEq(sourceSigner, address(validContractSigner), "Should return contract signer address");
    }

    function test_getSourceSigner_withEOASigner() public {
        BurnIntent memory intent = _createBurnIntent(depositor, 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        address sourceSigner = BurnIntentLib.getSourceSigner(encodedIntent);
        assertEq(sourceSigner, depositor, "Should return EOA signer address");
    }

    function test_getSourceSigner_withIntentSet() public {
        BurnIntent memory intent1 = _createBurnIntent(address(validContractSigner), 1000e6);
        BurnIntent memory intent2 = _createBurnIntent(address(validContractSigner), 500e6);
        intent2.spec.destinationRecipient = bytes32(uint256(uint160(makeAddr("recipient2"))));
        intent2.spec.salt = keccak256(abi.encode("salt2"));

        BurnIntent[] memory intents = new BurnIntent[](2);
        intents[0] = intent1;
        intents[1] = intent2;

        BurnIntentSet memory intentSet = BurnIntentSet({intents: intents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        address sourceSigner = BurnIntentLib.getSourceSigner(encodedIntentSet);
        assertEq(sourceSigner, address(validContractSigner), "Should return first intent's signer address");
    }
}
