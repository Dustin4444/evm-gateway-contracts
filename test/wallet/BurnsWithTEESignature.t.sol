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

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {BurnIntentLib} from "src/lib/BurnIntentLib.sol";
import {BurnIntent} from "src/lib/BurnIntents.sol";
import {TransferSpec, TRANSFER_SPEC_VERSION} from "src/lib/TransferSpec.sol";
import {Burns} from "src/modules/wallet/Burns.sol";
import {FiatTokenV2_2} from "test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";
import {MockEIP1271Signer, SignatureTestUtils} from "test/util/SignatureTestUtils.sol";

// solhint-disable-next-line max-states-count
contract GatewayWalletBurnsWithTEESignatureTest is SignatureTestUtils, DeployUtils {
    using MessageHashUtils for bytes32;

    uint32 private domain;
    address private owner = makeAddr("owner");
    address private feeRecipient = makeAddr("feeRecipient");
    address private depositor = makeAddr("depositor");
    uint256 private depositorKey = uint256(keccak256(abi.encodePacked("depositor")));
    address private contractSigner = makeAddr("contractSigner"); // The contract being vouched for
    address private allowlister = makeAddr("allowlister");

    // TEE signer setup
    uint256 private teeSignerKey;
    address private teeSigner;
    uint256 private teeSigner2Key;
    address private teeSigner2;

    uint256 private burnSignerKey;
    address private burnSigner;

    FiatTokenV2_2 private usdc;
    GatewayWallet private wallet;
    MockEIP1271Signer private eip1271ContractSigner;

    uint256 private defaultMaxBlockHeightOffset = 100;
    uint256 private defaultMaxFee = 10 ** 6;
    uint256 private depositorInitialBalance = 5000 * 10 ** 6;

    function setUp() public {
        domain = ForkTestUtils.forkVars().domain;
        usdc = FiatTokenV2_2(ForkTestUtils.forkVars().usdc);
        wallet = deployWalletOnly(owner, domain);

        (burnSigner, burnSignerKey) = makeAddrAndKey("burnSigner");
        (teeSigner, teeSignerKey) = makeAddrAndKey("teeSigner");
        (teeSigner2, teeSigner2Key) = makeAddrAndKey("teeSigner2");

        // Deploy mock EIP-1271 contract
        uint256 eip1271OwnerKey = uint256(keccak256(abi.encodePacked("eip1271Owner")));
        address eip1271Owner = vm.addr(eip1271OwnerKey);
        eip1271ContractSigner = new MockEIP1271Signer(eip1271Owner);

        vm.startPrank(owner);
        {
            wallet.addSupportedToken(address(usdc));
            wallet.addBurnSigner(burnSigner);
            wallet.updateFeeRecipient(feeRecipient);
            wallet.updateContractSignersAllowlister(allowlister);
            // Add TEE signer
            wallet.addContractSignatureSigner(teeSigner);
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
            // Add delegate authorization for contract signer
            wallet.addDelegate(address(usdc), contractSigner);
        }
        vm.stopPrank();
    }

    function _setupUSDCBurning() internal {
        address masterMinterAddr = usdc.masterMinter();
        if (masterMinterAddr.code.length > 0) {
            vm.startPrank(masterMinterAddr);
            try usdc.configureMinter(address(wallet), 0) {}
            catch {
                vm.stopPrank();
                try usdc.owner() returns (address usdcOwner) {
                    vm.startPrank(usdcOwner);
                    usdc.configureMinter(address(wallet), 0);
                    vm.stopPrank();
                } catch {
                    vm.startPrank(masterMinterAddr);
                    usdc.configureMinter(address(wallet), 0);
                    vm.stopPrank();
                }
            }
            vm.stopPrank();
        } else {
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

    function _signIntentWithTEE(bytes memory intentOrIntentSet, uint256 teeKey) internal view returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(intentOrIntentSet)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(teeKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signBurnCall(bytes memory burnCalldata) internal view returns (bytes memory) {
        bytes32 hash = keccak256(burnCalldata).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(burnSignerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _executeBurn(bytes memory intent, bytes memory intentSignature, uint256 fee) internal {
        bytes[] memory intents = new bytes[](1);
        intents[0] = intent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = intentSignature;

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = fee;

        bytes memory burnCalldata = abi.encode(intents, signatures, fees);
        bytes memory burnSignature = _signBurnCall(burnCalldata);

        wallet.gatewayBurn(burnCalldata, burnSignature);
    }

    // ============================================
    // 8. testTEESignerCanVouchForContract
    // ============================================
    function test_teeSignerCanVouchForContract() public {
        // Create burn intent with contract address as sourceSigner
        BurnIntent memory intent = _createBurnIntent(contractSigner, 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // TEE signs the burn intent with ECDSA
        bytes memory signature = _signIntentWithTEE(encodedIntent, teeSignerKey);

        // Record initial state
        uint256 initialAvailable = wallet.availableBalance(address(usdc), depositor);
        uint256 initialSupply = usdc.totalSupply();

        // Expect burn event with contractSigner as signer (not TEE address)
        vm.expectEmit(true, true, false, true);
        emit Burns.GatewayBurned(
            address(usdc),
            depositor,
            bytes32(0), // Skip exact hash check
            intent.spec.destinationDomain,
            intent.spec.destinationRecipient,
            contractSigner, // Should be contractSigner, NOT teeSigner
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

    // ============================================
    // 9. testInvalidTEESignerCannotVouch
    // ============================================
    function test_invalidTEESignerCannotVouch_unregistered() public {
        // Create a random unregistered TEE signer
        (address unregisteredTEE, uint256 unregisteredKey) = makeAddrAndKey("unregisteredTEE");

        // Create burn intent
        BurnIntent memory intent = _createBurnIntent(contractSigner, 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Unregistered TEE attempts to sign
        bytes memory signature = _signIntentWithTEE(encodedIntent, unregisteredKey);

        // Should revert because recovered signer (unregisteredTEE) doesn't match sourceSigner (contractSigner)
        // and unregisteredTEE is not a registered TEE signer
        vm.expectRevert(
            abi.encodeWithSelector(Burns.InvalidIntentSourceSignerAtIndex.selector, 0, contractSigner, unregisteredTEE)
        );

        _executeBurn(encodedIntent, signature, 0.5e6);
    }

    function test_invalidTEESignerCannotVouch_removed() public {
        // Remove the TEE signer
        vm.prank(owner);
        wallet.removeContractSignatureSigner(teeSigner);

        // Verify it's removed
        assertFalse(wallet.isContractSignatureSigner(teeSigner), "TEE signer should be removed");

        // Create burn intent
        BurnIntent memory intent = _createBurnIntent(contractSigner, 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Removed TEE attempts to sign
        bytes memory signature = _signIntentWithTEE(encodedIntent, teeSignerKey);

        // Should revert because teeSigner is no longer registered
        vm.expectRevert(
            abi.encodeWithSelector(Burns.InvalidIntentSourceSignerAtIndex.selector, 0, contractSigner, teeSigner)
        );

        _executeBurn(encodedIntent, signature, 0.5e6);
    }

    // ============================================
    // 10. testAllowlistedContractCanStillUseEIP1271WithTEESignerPresent
    // ============================================
    function test_allowlistedContractCanStillUseEIP1271WithTEESignerPresent() public {
        // Setup: Allowlist the EIP-1271 contract
        vm.prank(allowlister);
        wallet.allowlistContractSigner(address(eip1271ContractSigner));

        // Setup: Add delegation for EIP-1271 contract
        vm.prank(depositor);
        wallet.addDelegate(address(usdc), address(eip1271ContractSigner));

        // TEE signer is already registered in setUp()
        assertTrue(wallet.isContractSignatureSigner(teeSigner), "TEE signer should be registered");

        // Create burn intent with EIP-1271 contract as signer
        BurnIntent memory intent = _createBurnIntent(address(eip1271ContractSigner), 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // Sign with EIP-1271 contract's owner (should use Path 3, not TEE path)
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(encodedIntent));
        uint256 eip1271OwnerKey = uint256(keccak256(abi.encodePacked("eip1271Owner")));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eip1271OwnerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Record initial state
        uint256 initialAvailable = wallet.availableBalance(address(usdc), depositor);

        // Expect burn event with EIP-1271 contract as signer
        vm.expectEmit(true, true, false, true);
        emit Burns.GatewayBurned(
            address(usdc),
            depositor,
            bytes32(0),
            intent.spec.destinationDomain,
            intent.spec.destinationRecipient,
            address(eip1271ContractSigner), // EIP-1271 contract should be signer
            1000e6,
            0.5e6,
            1000.5e6,
            0
        );

        // Execute burn - should use Path 3 (EIP-1271), not Path 2 (TEE)
        _executeBurn(encodedIntent, signature, 0.5e6);

        // Verify balances
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialAvailable - 1000.5e6,
            "Available balance should decrease"
        );
    }

    // ============================================
    // 11. testSourceSignerMatchesDownstreamValidation
    // ============================================
    function test_sourceSignerMatchesDownstreamValidation() public {
        // This test verifies the complete validation flow:
        // 1. TEE signature recovery returns TEE address
        // 2. isContractSignatureSigner(teeSigner) returns true
        // 3. _validateSignatureAndGetSigner returns sourceSigner (not TEE address)
        // 4. Downstream validation checks sourceSigner == signer from TransferSpec

        // Create burn intent with contractSigner as sourceSigner
        BurnIntent memory intent = _createBurnIntent(contractSigner, 1000e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);

        // TEE signs the intent
        bytes memory signature = _signIntentWithTEE(encodedIntent, teeSignerKey);

        // Verify the signature would recover to teeSigner
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(encodedIntent));
        address recoveredSigner = ECDSA.recover(digest, signature);
        assertEq(recoveredSigner, teeSigner, "Signature should recover to TEE signer");

        // Verify TEE signer is registered
        assertTrue(wallet.isContractSignatureSigner(teeSigner), "TEE signer should be registered");

        // Execute burn - this implicitly tests that:
        // - _validateSignatureAndGetSigner returns contractSigner (not teeSigner)
        // - _validateBurnIntentTransferSpec checks contractSigner == signer and passes
        // - Delegation check validates contractSigner was authorized for depositor
        _executeBurn(encodedIntent, signature, 0.5e6);

        // If we get here without reverting, all validations passed correctly
    }

    // ============================================
    // Additional edge case tests
    // ============================================
    function test_multipleTEESignersCanVouch() public {
        // Add second TEE signer
        vm.prank(owner);
        wallet.addContractSignatureSigner(teeSigner2);

        address contractSigner2 = makeAddr("contractSigner2");

        // Add delegation for second contract
        vm.prank(depositor);
        wallet.addDelegate(address(usdc), contractSigner2);

        // First TEE vouches for first contract
        BurnIntent memory intent1 = _createBurnIntent(contractSigner, 500e6);
        bytes memory encodedIntent1 = BurnIntentLib.encodeBurnIntent(intent1);
        bytes memory signature1 = _signIntentWithTEE(encodedIntent1, teeSignerKey);

        // Second TEE vouches for second contract
        BurnIntent memory intent2 = _createBurnIntent(contractSigner2, 500e6);
        bytes memory encodedIntent2 = BurnIntentLib.encodeBurnIntent(intent2);
        bytes memory signature2 = _signIntentWithTEE(encodedIntent2, teeSigner2Key);

        uint256 initialBalance = wallet.availableBalance(address(usdc), depositor);

        // Execute both burns
        _executeBurn(encodedIntent1, signature1, 0.5e6);
        _executeBurn(encodedIntent2, signature2, 0.5e6);

        // Verify total deductions
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialBalance - 1001e6, // 500.5 + 500.5
            "Available balance should decrease by total"
        );
    }

    function test_singleTEESignerCanVouchForMultipleContracts() public {
        address contractSigner2 = makeAddr("contractSigner2");

        // Add delegation for second contract
        vm.prank(depositor);
        wallet.addDelegate(address(usdc), contractSigner2);

        // Same TEE vouches for two different contracts
        BurnIntent memory intent1 = _createBurnIntent(contractSigner, 500e6);
        bytes memory encodedIntent1 = BurnIntentLib.encodeBurnIntent(intent1);
        bytes memory signature1 = _signIntentWithTEE(encodedIntent1, teeSignerKey);

        BurnIntent memory intent2 = _createBurnIntent(contractSigner2, 500e6);
        bytes memory encodedIntent2 = BurnIntentLib.encodeBurnIntent(intent2);
        bytes memory signature2 = _signIntentWithTEE(encodedIntent2, teeSignerKey);

        uint256 initialBalance = wallet.availableBalance(address(usdc), depositor);

        // Execute both burns
        _executeBurn(encodedIntent1, signature1, 0.5e6);
        _executeBurn(encodedIntent2, signature2, 0.5e6);

        // Verify total deductions
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialBalance - 1001e6, // 500.5 + 500.5
            "Available balance should decrease by total"
        );
    }

    // ============================================
    // Test: TEE can vouch for previously EIP-1271 allowlisted contract
    // ============================================
    // This test verifies the reordered path logic where ECDSA recovery happens first,
    // enabling TEE vouch to work even for contracts that were previously EIP-1271 allowlisted.
    // This supports migration from EIP-1271 to TEE vouching.
    function test_teeCanVouchForPreviouslyAllowlistedContract() public {
        // Create a key for the EIP-1271 contract owner
        uint256 eip1271OwnerKey = uint256(keccak256(abi.encodePacked("eip1271Owner")));
        address eip1271Owner = vm.addr(eip1271OwnerKey);

        // Deploy an EIP-1271 contract and allowlist it
        MockEIP1271Signer eip1271Contract = new MockEIP1271Signer(eip1271Owner);

        vm.prank(allowlister);
        wallet.allowlistContractSigner(address(eip1271Contract));

        assertTrue(
            wallet.isAllowlistedContractSigner(address(eip1271Contract)), "Contract should be allowlisted for EIP-1271"
        );

        // Add delegation for the EIP-1271 contract
        vm.prank(depositor);
        wallet.addDelegate(address(usdc), address(eip1271Contract));

        // Now TEE vouches for this allowlisted contract using ECDSA
        // With the reordered logic (ECDSA recovery first), this should work
        BurnIntent memory intent = _createBurnIntent(address(eip1271Contract), 500e6);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);
        bytes memory signature = _signIntentWithTEE(encodedIntent, teeSignerKey);

        uint256 initialBalance = wallet.availableBalance(address(usdc), depositor);

        // Execute burn - should succeed with new path ordering
        // Path 2 (TEE vouch) is checked before Path 3 (EIP-1271)
        _executeBurn(encodedIntent, signature, 0.5e6);

        // Verify burn succeeded
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            initialBalance - 500.5e6,
            "TEE should be able to vouch for previously allowlisted contract"
        );
    }
}
