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

import {TransferSpec} from "src/lib/TransferSpec.sol";
import {MultichainTestUtils} from "test/util/MultichainTestUtils.sol";

contract BurnWithTEESignatureTest is MultichainTestUtils {
    ChainSetup private ethereum;
    ChainSetup private arbitrum;

    address private teeContractSignatureSigner;
    uint256 private teeContractSignatureSignerKey;
    address private customerContract = makeAddr("customerContract");

    function setUp() public {
        // Setup Ethereum fork
        ethereum = _initializeGatewayContracts("ethereum");

        // Setup Arbitrum fork
        arbitrum = _initializeGatewayContracts("arbitrum");

        // Create TEE contract signature signer
        (teeContractSignatureSigner, teeContractSignatureSignerKey) = makeAddrAndKey("teeContractSignatureSigner");

        // Add TEE contract signature signer on Ethereum
        vm.selectFork(ethereum.forkId);
        vm.prank(ethereum.wallet.owner());
        ethereum.wallet.addContractSignatureSigner(teeContractSignatureSigner);
    }

    // ============================================
    // 12. testEndToEndBurnWithTEESignature
    // ============================================
    function test_endToEndBurnWithTEESignature() public {
        // On Ethereum: Customer contract deposits its own USDC
        _depositToChain(ethereum, customerContract, DEPOSIT_AMOUNT);

        // Offchain: Generate burn intent where customerContract burns its OWN balance
        // No delegation needed since sourceDepositor == sourceSigner
        TransferSpec memory transferSpec = _createTransferSpec(
            ethereum, arbitrum, MINT_AMOUNT, customerContract, recipient, customerContract, destinationCaller
        );

        // TEE signs the burn intent with ECDSA
        (bytes memory encodedBurnIntent, bytes memory burnSignature) =
            _signBurnIntentWithTransferSpec(transferSpec, ethereum.wallet, teeContractSignatureSignerKey);

        // Offchain: Generate attestation given burn intent
        vm.selectFork(arbitrum.forkId);
        (bytes memory encodedAttestation, bytes memory attestationSignature) =
            _signAttestationWithTransferSpec(transferSpec, arbitrum.minterAttestationSignerKey);

        // On Arbitrum: Mint using attestation
        _mintFromChain(arbitrum, encodedAttestation, attestationSignature, MINT_AMOUNT /* expected minted amount */ );

        // On Ethereum: Burn used amount
        _burnFromChain(
            ethereum,
            encodedBurnIntent,
            burnSignature,
            customerContract,
            MINT_AMOUNT, /* expected total burnt amount */
            FEE_AMOUNT /* expected total fee amount */
        );

        // Verify recipient received tokens on Arbitrum
        vm.selectFork(arbitrum.forkId);
        assertEq(arbitrum.usdc.balanceOf(recipient), MINT_AMOUNT, "Recipient should receive minted tokens");

        // Verify customer contract's balance decreased on Ethereum
        vm.selectFork(ethereum.forkId);
        assertEq(
            ethereum.wallet.availableBalance(address(ethereum.usdc), customerContract),
            DEPOSIT_AMOUNT - MINT_AMOUNT - FEE_AMOUNT,
            "Customer contract's available balance should decrease"
        );
    }

    // ============================================
    // 13. testBurnIntentSetWithTEESignature
    // ============================================
    function test_burnIntentSetWithTEESignature() public {
        // On Ethereum: Customer contract deposits its own USDC (double amount for 2 burns)
        _depositToChain(ethereum, customerContract, DEPOSIT_AMOUNT * 2);

        // Offchain: Create multiple transfer specs where customerContract burns its OWN balance
        // No delegation needed since sourceDepositor == sourceSigner
        address recipient2 = makeAddr("recipient2");
        TransferSpec[] memory specs = new TransferSpec[](2);
        specs[0] = _createTransferSpec(
            ethereum, arbitrum, MINT_AMOUNT, customerContract, recipient, customerContract, destinationCaller
        );
        specs[1] = _createTransferSpec(
            ethereum, arbitrum, MINT_AMOUNT, customerContract, recipient2, customerContract, destinationCaller
        );

        // TEE signs the burn intent set
        (bytes memory encodedBurnIntentSet, bytes memory burnSignature) =
            _signBurnIntentSetWithTransferSpec(specs, ethereum.wallet, teeContractSignatureSignerKey);

        // Offchain: Generate attestations
        vm.selectFork(arbitrum.forkId);
        (bytes memory encodedAttestation1, bytes memory attestationSignature1) =
            _signAttestationWithTransferSpec(specs[0], arbitrum.minterAttestationSignerKey);
        (bytes memory encodedAttestation2, bytes memory attestationSignature2) =
            _signAttestationWithTransferSpec(specs[1], arbitrum.minterAttestationSignerKey);

        // On Arbitrum: Mint using attestations
        _mintFromChain(arbitrum, encodedAttestation1, attestationSignature1, recipient, MINT_AMOUNT);
        _mintFromChain(arbitrum, encodedAttestation2, attestationSignature2, recipient2, MINT_AMOUNT);

        // On Ethereum: Burn both intents
        _burnFromChain(ethereum, encodedBurnIntentSet, burnSignature, customerContract, MINT_AMOUNT * 2, FEE_AMOUNT * 2);

        // Verify both recipients received tokens on Arbitrum
        vm.selectFork(arbitrum.forkId);
        assertEq(arbitrum.usdc.balanceOf(recipient), MINT_AMOUNT, "Recipient 1 should receive minted tokens");
        assertEq(arbitrum.usdc.balanceOf(recipient2), MINT_AMOUNT, "Recipient 2 should receive minted tokens");

        // Verify customer contract's balance decreased on Ethereum
        vm.selectFork(ethereum.forkId);
        assertEq(
            ethereum.wallet.availableBalance(address(ethereum.usdc), customerContract),
            DEPOSIT_AMOUNT * 2 - MINT_AMOUNT * 2 - FEE_AMOUNT * 2,
            "Customer contract's available balance should decrease by total"
        );
    }

    // ============================================
    // 14. testTEESignatureWithDelegation (Special Case)
    // ============================================
    // This test covers a special case where customerContract burns ANOTHER entity's balance
    // Typical case: customerContract burns its own balance (no delegation needed)
    // Special case: customerContract burns depositor's balance (requires delegation)
    function test_teeSignatureWithDelegation() public {
        // On Ethereum: EOA depositor deposits USDC
        _depositToChain(ethereum, depositor, DEPOSIT_AMOUNT);

        // Depositor delegates to customerContract (authorizes contract to spend depositor's balance)
        vm.selectFork(ethereum.forkId);
        vm.prank(depositor);
        ethereum.wallet.addDelegate(address(ethereum.usdc), customerContract);

        // Verify delegation
        assertTrue(
            ethereum.wallet.isAuthorizedForBalance(address(ethereum.usdc), depositor, customerContract),
            "Customer contract should be authorized delegate for depositor's balance"
        );

        // Offchain: Generate burn intent where customerContract burns depositor's balance (not its own)
        // sourceDepositor = depositor (owns the balance)
        // sourceSigner = customerContract (authorized via delegation)
        TransferSpec memory transferSpec = _createTransferSpec(
            ethereum, arbitrum, MINT_AMOUNT, depositor, recipient, customerContract, destinationCaller
        );

        // TEE signs the burn intent vouching for customerContract
        (bytes memory encodedBurnIntent, bytes memory burnSignature) =
            _signBurnIntentWithTransferSpec(transferSpec, ethereum.wallet, teeContractSignatureSignerKey);

        // Offchain: Generate attestation
        vm.selectFork(arbitrum.forkId);
        (bytes memory encodedAttestation, bytes memory attestationSignature) =
            _signAttestationWithTransferSpec(transferSpec, arbitrum.minterAttestationSignerKey);

        // On Arbitrum: Mint using attestation
        _mintFromChain(arbitrum, encodedAttestation, attestationSignature, MINT_AMOUNT);

        // On Ethereum: Burn using delegated authorization
        vm.selectFork(ethereum.forkId);
        uint256 initialAvailable = ethereum.wallet.availableBalance(address(ethereum.usdc), depositor);

        _burnFromChain(ethereum, encodedBurnIntent, burnSignature, MINT_AMOUNT, FEE_AMOUNT);

        // Verify balances
        vm.selectFork(ethereum.forkId);
        assertEq(
            ethereum.wallet.availableBalance(address(ethereum.usdc), depositor),
            initialAvailable - MINT_AMOUNT - FEE_AMOUNT,
            "Depositor's balance should decrease even though contract signed"
        );

        vm.selectFork(arbitrum.forkId);
        assertEq(arbitrum.usdc.balanceOf(recipient), MINT_AMOUNT, "Recipient should receive tokens");
    }
}
