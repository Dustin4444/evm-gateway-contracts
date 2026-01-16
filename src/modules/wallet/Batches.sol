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
import {GatewayCommon} from "src/GatewayCommon.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {BatchedDelta} from "src/lib/BatchedDelta.sol";
import {TokenSupport} from "src/modules/common/TokenSupport.sol";
import {Balances} from "src/modules/wallet/Balances.sol";

/// @title Batches
///
/// @notice Manages batching for the `GatewayWallet` contract
contract Batches is TokenSupport, GatewayCommon, Balances {
    using MessageHashUtils for bytes32;

    /// Emitted when a batch signer is added
    ///
    /// @param signer   The batch signer address that was added
    event BatchSignerAdded(address indexed signer);

    /// Emitted when a batch signer is removed
    ///
    /// @param signer   The batch signer address that was removed
    event BatchSignerRemoved(address indexed signer);

    /// Emitted when a batch is processed
    ///
    /// @param batchId      The batch id that was processed
    /// @param signer       The signer who signed the batch
    /// @param tokenAddress The token address for the batch
    event BatchProcessed(bytes32 indexed batchId, address indexed signer, address indexed tokenAddress);

    /// Thrown when the domain for a batch does not match this domain.
    error WrongDomain();

    /// Thrown when the target gateway wallet address for a batch does not match this contract.
    error WrongGatewayContract();

    /// Thrown when the calldata for `submitBatch` is not signed by a valid batch signer
    error InvalidBatchSigner();

    /// Thrown when a batch id has already been used for a batch.
    error BatchIdUsed(bytes32 batchId);

    /// Thrown when a batch does not contain any deltas.
    error MustHaveAtLeastOneDelta();

    /// Thrown when a batch does not net to 0.
    error MustNetToZero(int256 totalDelta);

    /// Thrown when a delta is 0.
    error DeltaMustBeNonZero(address depositor);

    /// Initializes a batch signer
    ///
    /// @param batchSigner_     The address to initialize the `batchSigner` role
    function __Batches_init(address batchSigner_) internal onlyInitializing {
        addBatchSigner(batchSigner_);
    }

    /// Return whether or not batchSigner is a registered batchSigner.
    ///
    /// @param signer  The address to check
    /// @return        `true` if the address is a valid batch signer, `false` otherwise.
    function isBatchSigner(address signer) public view returns (bool) {
        return BatchesStorage.get().batchSigners[signer];
    }

    /// Adds an address that may sign batches for processing.
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param signer  The batch signer address to add
    function addBatchSigner(address signer) public onlyOwner {
        AddressLib._checkNotZeroAddress(signer);

        BatchesStorage.get().batchSigners[signer] = true;
        emit BatchSignerAdded(signer);
    }

    /// Removes an address from the set of valid batch signers
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param signer   The batch signer address to remove
    function removeBatchSigner(address signer) public onlyOwner {
        AddressLib._checkNotZeroAddress(signer);

        BatchesStorage.get().batchSigners[signer] = false;
        emit BatchSignerRemoved(signer);
    }

    /// Called by the operator to process a batch of transactions, which to Gateway appear to just
    /// be a list of money movements for a given token.
    /// @dev The `calldataBytes` input must be an ABI-encoded tuple with `deltas`, `batchId`,
    // `domain`, `tokenAddress`, and `gatewayWalletAddress`.
    /// @dev See `lib/BatchedDelta.sol` for encoding details.
    ///
    /// @param calldataBytes   ABI-encoded tuple of the above fields.
    /// @param signature       The signature from a valid batchSigner on `calldataBytes`
    function submitBatch(bytes calldata calldataBytes, bytes calldata signature) external whenNotPaused {
        // Verify that the calldata was signed by a valid batch signer
        address recoveredSigner = _verifyBatchSignerSignature(calldataBytes, signature);

        // Decode the calldata into the various fields
        (
            BatchedDelta[] memory deltas,
            bytes32 batchId,
            uint32 domain,
            address tokenAddress,
            address gatewayWalletAddress
        ) = abi.decode(calldataBytes, (BatchedDelta[], bytes32, uint32, address, address));

        // Make sure that this is signed for the domain we're running on...
        if (!_isCurrentDomain(domain)) {
            revert WrongDomain();
        }

        // ...and for this gateway contract.  As a reminder, `this` will be the address of the proxy
        // (which is good so that the batch signer doesn't have to know the address of the implementation
        // contract).
        if (gatewayWalletAddress != address(this)) {
            revert WrongGatewayContract();
        }

        // Make sure we can use this batch id.
        _checkAndMarkBatchIdUsed(batchId);

        // Batch is verified, so we can apply the deltas
        _processBatch(deltas, tokenAddress);

        // Emit an event that we successfully processed it
        emit BatchProcessed(batchId, recoveredSigner, tokenAddress);
    }

    /// Verifies the signature for the calldata of `submitBatch`
    ///
    /// @dev Recovers the signer from the signature and ensures it is a valid batch signer
    ///
    /// @param calldataBytes   Calldata that includes all of the batch information.
    /// @param signature       The signature on the `calldataBytes` from a valid batch signer
    function _verifyBatchSignerSignature(bytes calldata calldataBytes, bytes calldata signature)
        internal
        view
        returns (address)
    {
        address recoveredSigner = ECDSA.recover(keccak256(calldataBytes).toEthSignedMessageHash(), signature);
        if (!isBatchSigner(recoveredSigner)) {
            revert InvalidBatchSigner();
        }

        return recoveredSigner;
    }

    /// Asserts that the given batch id has not been used, reverting if it has, and marks it as used.
    ///
    /// @param batchId  The batch id to check and mark
    function _checkAndMarkBatchIdUsed(bytes32 batchId) internal {
        BatchesStorage.Data storage $ = BatchesStorage.get();

        // Make sure the batch id hasn't been used before
        if ($.usedBatchIds[batchId]) {
            revert BatchIdUsed(batchId);
        }

        // It hasn't, so mark it as used.
        $.usedBatchIds[batchId] = true;
    }

    /// Processes a batch by performing the given deltas over the given token address.
    ///
    /// @param deltas       The deltas to process
    /// @param tokenAddress The token to perform the deltas for.
    function _processBatch(BatchedDelta[] memory deltas, address tokenAddress) internal tokenSupported(tokenAddress) {
        // Ensure there is at least one delta, otherwise this doesn't make sense to do
        if (deltas.length == 0) {
            revert MustHaveAtLeastOneDelta();
        }

        // The deltas must net to 0 by the end, otherwise we're creating or destroying money (bad).
        int256 totalDelta = 0;

        // Process each delta
        for (uint256 i = 0; i < deltas.length; i++) {
            BatchedDelta memory delta = deltas[i];

            // Credit or debit as appropriate.
            if (delta.value > 0) {
                // It's a credit, so add to the balance.  No further validation needed.
                // We just tested that delta.value > 0, so its top bit is 0, and so casting to uint256 is safe.
                Balances._increaseAvailableBalance(tokenAddress, delta.depositor, uint256(delta.value));
            } else if (delta.value < 0) {
                // It's a debit, so subtract from the balance.  This follows the same semantics as processing burns:
                // we subtract as much balance as we can, and if we could not deduct the full amount, emit an event
                // with the details.  This should not happen under normal circumstances and indicates a failure, but
                // we want to continue and burn what we can rather than holding up the full batch.

                // Do the deduction.  Note that _reduceBalance thinks in uints (ie, 123 means deduct 123), so
                // we need to flip the sign on delta.value and then make it a uint.
                uint256 amountToDeduct = uint256(-delta.value);
                (uint256 fromAvailable, uint256 fromWithdrawing) =
                    _reduceBalance(tokenAddress, delta.depositor, amountToDeduct);

                // See if we deducted enough, and if not emit a log, but keep going
                if ((fromAvailable + fromWithdrawing) < amountToDeduct) {
                    emit InsufficientBalance(
                        tokenAddress, delta.depositor, amountToDeduct, fromAvailable, fromWithdrawing
                    );
                }
            } else {
                // delta.value == 0 so it shouldn't have been included; complain.
                revert DeltaMustBeNonZero(delta.depositor);
            }

            // Add to the total delta
            totalDelta += delta.value;
        }

        // Make sure everything netted to zero
        if (totalDelta != 0) {
            revert MustNetToZero(totalDelta);
        }
    }
}

/// @title BatchesStorage
///
/// @notice Implements the EIP-7201 storage pattern for the `Batches` modules
library BatchesStorage {
    /// @custom:storage-location erc7201:circle.gateway.Batches
    struct Data {
        /// The addresses that we trust to submit batch requests.
        mapping(address signer => bool valid) batchSigners;
        /// Whether or not a given batch id has been used
        mapping(bytes32 batchId => bool used) usedBatchIds;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.gateway.Batches"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x0e6c5e45c8a8c20a4b7640db1ad9d6bc08eb78e01fa319b166e7a60871192000;

    /// EIP-7201 getter for the storage slot
    ///
    /// @return $   The storage struct for the `Batches` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
