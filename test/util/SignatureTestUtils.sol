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
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Test} from "forge-std/Test.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {AttestationLib} from "src/lib/AttestationLib.sol";
import {Attestation, AttestationSet} from "src/lib/Attestations.sol";
import {BurnIntentLib} from "src/lib/BurnIntentLib.sol";
import {BurnIntent, BurnIntentSet} from "src/lib/BurnIntents.sol";
import {TransferSpec} from "src/lib/TransferSpec.sol";

/// @notice Mock EIP-1271 contract signer for testing
contract MockEIP1271Signer is IERC1271 {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address recoveredSigner = ECDSA.recover(hash, signature);
        if (recoveredSigner == owner) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0);
    }
}

contract SignatureTestUtils is Test {
    using MessageHashUtils for bytes32;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 private constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 private constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    function _signPermit(address token, address spender, uint256 value, uint256 deadline, uint256 privateKey)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                vm.addr(privateKey),
                spender,
                value,
                IERC20Permit(token).nonces(vm.addr(privateKey)),
                deadline
            )
        );
        bytes32 domainSeparator = IERC20Permit(token).DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function _signReceiveWithAuthorization(
        address token,
        address to,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint256 value,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                RECEIVE_WITH_AUTHORIZATION_TYPEHASH, vm.addr(privateKey), to, value, validAfter, validBefore, nonce
            )
        );
        bytes32 domainSeparator = IERC20Permit(token).DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function _signCancelAuthorization(address token, bytes32 nonce, uint256 privateKey)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, vm.addr(privateKey), nonce));
        bytes32 domainSeparator = IERC20Permit(token).DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function _signBurnIntentWithTransferSpec(TransferSpec memory transferSpec, GatewayWallet wallet, uint256 signerKey)
        internal
        view
        returns (bytes memory encodedIntent, bytes memory signature)
    {
        BurnIntent[] memory intents = new BurnIntent[](1);
        intents[0] = _createBurnIntent(transferSpec);
        return _signBurnIntents(intents, wallet, signerKey);
    }

    function _signBurnIntentSetWithTransferSpec(
        TransferSpec[] memory transferSpecs,
        GatewayWallet wallet,
        uint256 signerKey
    ) internal view returns (bytes memory encodedIntent, bytes memory signature) {
        BurnIntent[] memory intents = new BurnIntent[](transferSpecs.length);
        for (uint256 i = 0; i < transferSpecs.length; i++) {
            intents[i] = _createBurnIntent(transferSpecs[i]);
        }
        return _signBurnIntents(intents, wallet, signerKey);
    }

    function _signAttestationWithTransferSpec(TransferSpec memory transferSpec, uint256 signerKey)
        internal
        view
        returns (bytes memory encodedAttestation, bytes memory signature)
    {
        Attestation[] memory attestations = new Attestation[](1);
        attestations[0] = _createAttestation(transferSpec);
        return _signAttestations(attestations, signerKey);
    }

    function _signAttestationSetWithTransferSpec(TransferSpec[] memory transferSpecs, uint256 signerKey)
        internal
        view
        returns (bytes memory encodedAttestation, bytes memory signature)
    {
        Attestation[] memory attestations = new Attestation[](transferSpecs.length);
        for (uint256 i = 0; i < transferSpecs.length; i++) {
            attestations[i] = _createAttestation(transferSpecs[i]);
        }
        return _signAttestations(attestations, signerKey);
    }

    function _signBurnIntents(
        bytes[] memory intents,
        bytes[] memory signatures,
        uint256[][] memory fees,
        uint256 signerKey
    ) internal pure returns (bytes memory burnerSignature) {
        // Generate a random address and key for the burn signer
        bytes memory encodedCalldata = abi.encode(intents, signatures, fees);

        // Sign the calldata hash as the burn signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, keccak256(encodedCalldata).toEthSignedMessageHash());
        burnerSignature = abi.encodePacked(r, s, v);
    }

    function _createBurnIntent(TransferSpec memory spec) internal view returns (BurnIntent memory) {
        return BurnIntent({
            maxBlockHeight: block.number + 5, // ~1 minute expiry
            maxFee: 1e6, // 1 USDC max fee
            spec: spec
        });
    }

    function _createAttestation(TransferSpec memory spec) private view returns (Attestation memory) {
        return Attestation({
            maxBlockHeight: block.number + 5, // ~1 minute expiry
            spec: spec
        });
    }

    function _signBurnIntents(BurnIntent[] memory intents, GatewayWallet wallet, uint256 signerKey)
        internal
        view
        returns (bytes memory encodedIntent, bytes memory signature)
    {
        encodedIntent = intents.length == 1
            ? BurnIntentLib.encodeBurnIntent(intents[0])
            : BurnIntentLib.encodeBurnIntentSet(BurnIntentSet({intents: intents}));
        bytes32 domainSeparator = wallet.domainSeparator();
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(domainSeparator, BurnIntentLib.getTypedDataHash(encodedIntent));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _signAttestations(Attestation[] memory attestations, uint256 signerKey)
        private
        pure
        returns (bytes memory encodedAttestation, bytes memory signature)
    {
        if (attestations.length == 1) {
            encodedAttestation = AttestationLib.encodeAttestation(attestations[0]);
        } else {
            AttestationSet memory attestationSet = AttestationSet({attestations: attestations});
            encodedAttestation = AttestationLib.encodeAttestationSet(attestationSet);
        }
        signature = _sign(signerKey, encodedAttestation);
    }

    function _sign(uint256 signerKey, bytes memory data) private pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, keccak256(data).toEthSignedMessageHash());
        signature = abi.encodePacked(r, s, v);
    }
}
