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

import {TypedMemView} from "@memview-sol/TypedMemView.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {
    BurnIntent,
    BurnIntentSet,
    BURN_INTENT_MAGIC,
    BURN_INTENT_SET_MAGIC,
    BURN_INTENT_MAGIC_OFFSET,
    BURN_INTENT_MAX_BLOCK_HEIGHT_OFFSET,
    BURN_INTENT_MAX_FEE_OFFSET,
    BURN_INTENT_TRANSFER_SPEC_LENGTH_OFFSET,
    BURN_INTENT_TRANSFER_SPEC_OFFSET,
    BURN_INTENT_SET_NUM_INTENTS_OFFSET,
    BURN_INTENT_SET_INTENTS_OFFSET,
    BURN_INTENT_TYPEHASH,
    BURN_INTENT_SET_TYPEHASH
} from "src/lib/BurnIntents.sol";
import {Cursor} from "src/lib/Cursor.sol";
import {TRANSFER_SPEC_MAGIC} from "src/lib/TransferSpec.sol";
import {TransferSpecLib, BYTES4_BYTES, UINT32_BYTES, UINT256_BYTES} from "src/lib/TransferSpecLib.sol";

/// @title BurnIntentLib
///
/// @notice Library for encoding, validating, and iterating over `BurnIntent` and `BurnIntentSet` structs
///
/// @dev Provides functions to handle single burn intents or sets of them, using `TypedMemView` for efficient
///      memory operations and `Cursor` for unified iteration
library BurnIntentLib {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    /// Checks whether the provided `bytes29` reference is a `BurnIntentSet`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `BurnIntent` or `BurnIntentSet`
    /// @return      `true` if the provided `bytes29` reference is a `BurnIntentSet`, `false` otherwise
    function _isSet(bytes29 ref) private pure returns (bool) {
        return ref.index(0, BYTES4_BYTES) == BURN_INTENT_SET_MAGIC;
    }

    // --- Casting -----------------------------------------------------------------------------------------------------

    /// Creates a typed memory view for a `BurnIntent` or `BurnIntentSet`
    ///
    /// @dev Checks for either `BurnIntent` or `BurnIntentSet` magic
    /// @dev Reverts with `InvalidTransferPayloadMagic` if neither known magic number is present
    /// @dev Reverts if data length is less than 4
    ///
    /// @param data   The raw bytes to create a view into. Must contain at least 4 bytes.
    /// @return ref   A `TypedMemView` reference to `data`, typed according to the magic number found
    function _asIntentOrSetView(bytes memory data) internal pure returns (bytes29 ref) {
        if (data.length < BYTES4_BYTES) {
            revert TransferSpecLib.TransferPayloadDataTooShort(BYTES4_BYTES, data.length);
        }

        bytes29 initialView = data.ref(0);
        bytes4 magic = bytes4(initialView.index(0, BYTES4_BYTES));

        if (magic == BURN_INTENT_MAGIC) {
            ref = initialView.castTo(TransferSpecLib._toMemViewType(BURN_INTENT_MAGIC));
        } else if (magic == BURN_INTENT_SET_MAGIC) {
            ref = initialView.castTo(TransferSpecLib._toMemViewType(BURN_INTENT_SET_MAGIC));
        } else {
            revert TransferSpecLib.InvalidTransferPayloadMagic(magic);
        }
    }

    // --- Validation --------------------------------------------------------------------------------------------------

    /// Validates the structural integrity of an encoded `BurnIntent` memory view
    ///
    /// @notice Validation steps:
    ///   1. Minimum header length check
    ///   2. Total length consistency check (using declared `TransferSpec` length)
    ///
    /// @dev Performs structural validation on a `BurnIntent` view, *excluding* recursive validation of the
    ///      nested `TransferSpec` and its magic number. Reverts on failure. Assumes outer magic number check has passed
    ///      (via casting).
    ///
    /// @param intentView   The `TypedMemView` reference to the encoded `BurnIntent` to validate
    function _validateBurnIntentOuterStructure(bytes29 intentView) private pure {
        // 1. Minimum header length check
        if (intentView.len() < BURN_INTENT_TRANSFER_SPEC_OFFSET) {
            revert TransferSpecLib.TransferPayloadHeaderTooShort(BURN_INTENT_TRANSFER_SPEC_OFFSET, intentView.len());
        }

        // 2. Total length consistency check
        uint32 specLengthDeclaredInIntent = getTransferSpecLength(intentView);
        uint256 expectedIntentLength = BURN_INTENT_TRANSFER_SPEC_OFFSET + specLengthDeclaredInIntent;
        if (intentView.len() != expectedIntentLength) {
            revert TransferSpecLib.TransferPayloadOverallLengthMismatch(expectedIntentLength, intentView.len());
        }
    }

    /// Validates the full structural integrity of a `BurnIntent` view, including the nested `TransferSpec`
    ///
    /// @notice Validation includes:
    ///   1. Wrapper structure validation (header length, total length consistency).
    ///   2. Full recursive validation of the nested `TransferSpec` structure.
    ///
    /// @dev Performs structural validation on a `BurnIntent` view. Reverts on failure. Assumes the view has the
    ///      correct `BurnIntent` magic number (e.g., validated by `_asIntentOrSetView`).
    /// @dev Reverts with specific errors (e.g., `TransferPayloadHeaderTooShort`, `TransferPayloadOverallLengthMismatch`,
    ///      `InvalidTransferSpecMagic`, `TransferSpecHeaderTooShort`, `TransferSpecOverallLengthMismatch`) if the
    ///      structure is invalid
    ///
    /// @param intentView   The `TypedMemView` reference to the encoded `BurnIntent` to validate
    function _validateBurnIntent(bytes29 intentView) internal pure {
        _validateBurnIntentOuterStructure(intentView);

        bytes29 specView = getTransferSpec(intentView);
        TransferSpecLib._validateTransferSpecStructure(specView);
    }

    /// Validates the full structural integrity of an encoded `BurnIntentSet` memory view
    ///
    /// @notice Validation includes:
    ///   1. Minimum header length check.
    ///   2. Reading declared intent count.
    ///   3. Iterating through declared intents:
    ///      a. Checking bounds based on previously declared lengths.
    ///      b. Checking the magic number of each intent.
    ///      c. Performing full recursive validation on each intent using `_validateBurnIntent`.
    ///   4. Final total length consistency check.
    ///
    /// @dev Performs structural validation on a `BurnIntentSet` view. Reverts on failure. Assumes the view has
    ///      the correct `BurnIntentSet` magic number (e.g., checked via `_as...Set`).
    /// @dev Reverts with errors relating to set/element structure, bounds, magic numbers, and nested validation
    ///      (see `_validateBurnIntent`)
    ///
    /// @param setView   The `TypedMemView` reference to the encoded `BurnIntentSet` to validate
    function _validateBurnIntentSet(bytes29 setView) internal pure {
        // 1. Minimum header length check
        if (setView.len() < BURN_INTENT_SET_INTENTS_OFFSET) {
            revert TransferSpecLib.TransferPayloadSetHeaderTooShort(BURN_INTENT_SET_INTENTS_OFFSET, setView.len());
        }

        // 2. Read declared count
        uint32 numIntents = getNumIntents(setView);
        uint256 currentOffset = BURN_INTENT_SET_INTENTS_OFFSET;

        // 3. Iterate and validate each element
        for (uint32 i = 0; i < numIntents; i++) {
            uint256 requiredOffsetForHeader = currentOffset + BURN_INTENT_TRANSFER_SPEC_OFFSET;

            // 3a. Check bounds for header read
            if (setView.len() < requiredOffsetForHeader) {
                revert TransferSpecLib.TransferPayloadSetElementHeaderTooShort(
                    i, setView.len(), requiredOffsetForHeader
                );
            }

            // Read spec length to determine current intent total length
            uint32 specLength =
                uint32(setView.indexUint(currentOffset + BURN_INTENT_TRANSFER_SPEC_LENGTH_OFFSET, UINT32_BYTES));
            uint256 currentIntentTotalLength = BURN_INTENT_TRANSFER_SPEC_OFFSET + specLength;
            uint256 requiredOffsetForElement = currentOffset + currentIntentTotalLength;

            // Check bounds for full intent read
            if (setView.len() < requiredOffsetForElement) {
                revert TransferSpecLib.TransferPayloadSetElementTooShort(i, setView.len(), requiredOffsetForElement);
            }

            // 3b. Check magic number of the current element slice
            bytes4 elementMagic = bytes4(setView.index(currentOffset + BURN_INTENT_MAGIC_OFFSET, BYTES4_BYTES));
            if (elementMagic != BURN_INTENT_MAGIC) {
                revert TransferSpecLib.TransferPayloadSetInvalidElementMagic(i, elementMagic);
            }

            // 3c. Create view and perform full recursive validation on the element
            bytes29 intentView = setView.slice(
                currentOffset, currentIntentTotalLength, TransferSpecLib._toMemViewType(BURN_INTENT_MAGIC)
            );
            _validateBurnIntent(intentView);

            // Update offset for the next iteration
            currentOffset += currentIntentTotalLength;
        }

        // 4. Final total length consistency check
        if (currentOffset != setView.len()) {
            revert TransferSpecLib.TransferPayloadSetOverallLengthMismatch(currentOffset, setView.len());
        }
    }

    /// Validates the structural integrity of either a `BurnIntent` or a `BurnIntentSet`
    ///
    /// @dev First casts the data using `_asIntentOrSetView`, then calls the appropriate specific validation function
    ///      (`_validateBurnIntent` or `_validateBurnIntentSet`). Reverts with specific errors if casting
    ///      or validation fails.
    ///
    /// @param data   The raw bytes representing either an encoded `BurnIntent` or `BurnIntentSet`
    /// @return ref   A `TypedMemView` reference to `data`, typed according to the magic number found
    function _validate(bytes memory data) internal pure returns (bytes29 ref) {
        ref = _asIntentOrSetView(data);

        if (_isSet(ref)) {
            _validateBurnIntentSet(ref);
        } else {
            _validateBurnIntent(ref);
        }
    }

    // --- Iteration ---------------------------------------------------------------------------------------------------

    /// Validates `data` and returns a cursor that can uniformly iterate over any burn intents it contains
    ///
    /// @dev For a single `BurnIntent`, the cursor will yield that single element. For a `BurnIntentSet`,
    ///      it iterates through each contained `BurnIntent`. Sets the 'done' flag immediately if the set
    ///      contains zero intents.
    /// @dev Reverts with `TransferPayloadDataTooShort` or `InvalidTransferPayloadMagic` if casting fails
    ///
    /// @param data   The raw bytes representing either an encoded `BurnIntent` or `BurnIntentSet`
    /// @return c     An initialized `Cursor` struct
    function cursor(bytes memory data) internal pure returns (Cursor memory c) {
        bytes29 ref = _validate(data);
        c.memView = ref;
        c.index = 0;

        if (!_isSet(ref)) {
            c.offset = 0;
            c.numElements = 1;
            c.done = false; // There's one element to process
            return c;
        }

        uint32 numIntents = getNumIntents(ref);
        c.offset = BURN_INTENT_SET_INTENTS_OFFSET;
        c.numElements = numIntents;
        c.done = (numIntents == 0); // If the set is empty, the cursor is immediately done
    }

    /// Gets the `TypedMemView` reference to the next element and advances the cursor
    ///
    /// @dev Updates the cursor's internal state (`offset`, `index`, `done`). Reverts with `CursorOutOfBounds` if called
    ///      when no elements are remaining.
    ///
    /// @param c      The `Cursor` struct
    /// @return ref   The element the cursor was pointing at immediately before this function was called
    function next(Cursor memory c) internal pure returns (bytes29 ref) {
        if (c.done) {
            revert TransferSpecLib.CursorOutOfBounds();
        }

        uint32 currentSpecLength =
            uint32(c.memView.indexUint(c.offset + BURN_INTENT_TRANSFER_SPEC_LENGTH_OFFSET, UINT32_BYTES));
        uint256 currentIntentTotalLength = BURN_INTENT_TRANSFER_SPEC_OFFSET + currentSpecLength;

        ref = c.memView.slice(c.offset, currentIntentTotalLength, TransferSpecLib._toMemViewType(BURN_INTENT_MAGIC));

        c.offset += currentIntentTotalLength;
        c.index++;

        if (c.index >= c.numElements) {
            c.done = true;
        }
    }

    // --- Field accessors ---------------------------------------------------------------------------------------------

    /// Extract the max block height from an encoded `BurnIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `BurnIntent`
    /// @return      The `maxBlockHeight` field
    function getMaxBlockHeight(bytes29 ref) internal pure returns (uint256) {
        return ref.indexUint(BURN_INTENT_MAX_BLOCK_HEIGHT_OFFSET, UINT256_BYTES);
    }

    /// Extract the max fee from an encoded BurnIntent
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `BurnIntent`
    /// @return      The `maxFee` field
    function getMaxFee(bytes29 ref) internal pure returns (uint256) {
        return ref.indexUint(BURN_INTENT_MAX_FEE_OFFSET, UINT256_BYTES);
    }

    /// Extract the transfer spec length from an encoded `BurnIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `BurnIntent`
    /// @return      The transfer spec length
    function getTransferSpecLength(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(BURN_INTENT_TRANSFER_SPEC_LENGTH_OFFSET, UINT32_BYTES));
    }

    /// Extract the transfer spec from an encoded `BurnIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `BurnIntent`
    /// @return      A `TypedMemView` reference to the `TransferSpec` portion
    function getTransferSpec(bytes29 ref) internal pure returns (bytes29) {
        uint32 specLength = getTransferSpecLength(ref);
        bytes29 specRef =
            ref.slice(BURN_INTENT_TRANSFER_SPEC_OFFSET, specLength, TransferSpecLib._toMemViewType(TRANSFER_SPEC_MAGIC));

        // Validate that the slice contains a valid TransferSpec
        bytes4 specMagic = bytes4(specRef.index(0, BYTES4_BYTES));
        if (specMagic != TRANSFER_SPEC_MAGIC) {
            revert TransferSpecLib.InvalidTransferSpecMagic(specMagic);
        }

        return specRef;
    }

    /// Extract the number of intents from an encoded `BurnIntentSet`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `BurnIntentSet`
    /// @return      The number of intents in the set
    function getNumIntents(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(BURN_INTENT_SET_NUM_INTENTS_OFFSET, UINT32_BYTES));
    }

    // --- Encoding ----------------------------------------------------------------------------------------------------

    /// Encode a `BurnIntent` struct into bytes
    ///
    /// @param intent   The `BurnIntent` to encode
    /// @return         The encoded bytes
    function encodeBurnIntent(BurnIntent memory intent) internal pure returns (bytes memory) {
        bytes memory specBytes = TransferSpecLib.encodeTransferSpec(intent.spec);

        return abi.encodePacked(
            BURN_INTENT_MAGIC,
            intent.maxBlockHeight,
            intent.maxFee,
            uint32(specBytes.length), // 4 bytes
            specBytes
        );
    }

    /// Encode a `BurnIntentSet` struct into bytes
    ///
    /// @param intentSet   The `BurnIntentSet` to encode
    /// @return            The encoded bytes
    function encodeBurnIntentSet(BurnIntentSet memory intentSet) internal pure returns (bytes memory) {
        uint256 numIntents = intentSet.intents.length;

        // Ensure the declared number of intents is within the bounds of a uint32
        if (numIntents > type(uint32).max) {
            revert TransferSpecLib.TransferPayloadSetTooManyElements(type(uint32).max);
        }

        // Calculate total size of all encoded intents
        uint256 totalSize = 0;
        bytes[] memory encodedIntents = new bytes[](numIntents);
        for (uint256 i = 0; i < numIntents; i++) {
            encodedIntents[i] = encodeBurnIntent(intentSet.intents[i]);
            totalSize += encodedIntents[i].length;
        }

        // Create header with magic and intent count
        bytes memory header = abi.encodePacked(
            BURN_INTENT_SET_MAGIC,
            uint32(numIntents) // 4 bytes
        );

        // Combine header and all encoded intents
        bytes memory result = new bytes(header.length + totalSize);

        // Copy header into result
        for (uint256 i = 0; i < header.length; i++) {
            result[i] = header[i];
        }

        // Copy each encoded intent into result
        uint256 position = header.length;
        for (uint256 i = 0; i < numIntents; i++) {
            bytes memory intent = encodedIntents[i];
            for (uint256 j = 0; j < intent.length; j++) {
                result[position] = intent[j];
                position++;
            }
        }

        return result;
    }

    // --- Hashing -----------------------------------------------------------------------------------------------------

    /// Computes the EIP-712 typed data hash for a burn intent or burn intent set
    ///
    /// @param intent   The encoded burn intent or burn intent set
    /// @return         The EIP-712 typed data hash
    function getTypedDataHash(bytes memory intent) internal view returns (bytes32) {
        bytes29 ref = _asIntentOrSetView(intent);
        if (_isSet(ref)) {
            return _getBurnIntentSetTypedDataHash(ref);
        } else {
            return _getBurnIntentTypedDataHash(ref);
        }
    }

    /// Computes the EIP-712 typed data hash for a single burn intent
    ///
    /// @param intent         A `TypedMemView` reference to the encoded burn intent
    /// @return structHash   The EIP-712 typed data hash of the burn intent
    function _getBurnIntentTypedDataHash(bytes29 intent) private view returns (bytes32 structHash) {
        uint256 maxBlockHeight = getMaxBlockHeight(intent);
        uint256 maxFee = getMaxFee(intent);
        bytes29 transferSpec = getTransferSpec(intent);
        bytes32 transferSpecHash = TransferSpecLib.getTypedDataHash(transferSpec);

        assembly {
            // Get the free memory pointer
            let ptr := mload(0x40)

            // Store BURN_INTENT_TYPEHASH at ptr
            mstore(ptr, BURN_INTENT_TYPEHASH)
            // Store maxBlockHeight at ptr + 32
            mstore(add(ptr, 32), maxBlockHeight)
            // Store maxFee at ptr + 64
            mstore(add(ptr, 64), maxFee)
            // Get and store transferSpec hash at ptr + 96
            mstore(add(ptr, 96), transferSpecHash)

            // Hash the full data (128 bytes total)
            structHash := keccak256(ptr, 128)
        }
    }

    /// Computes the EIP-712 typed data hash for a burn intent set
    ///
    /// @param setView   A `TypedMemView` reference to the encoded burn intent set
    /// @return          The EIP-712 typed data hash of the burn intent set
    function _getBurnIntentSetTypedDataHash(bytes29 setView) private view returns (bytes32) {
        uint32 numIntents = getNumIntents(setView);
        uint256 currentOffset = BURN_INTENT_SET_INTENTS_OFFSET;
        bytes32[] memory intentHashes = new bytes32[](numIntents);

        // Iterate through each intent in the set and compute its hash
        for (uint32 i = 0; i < numIntents; i++) {
            // Read spec length to determine current intent total length
            uint32 specLength =
                uint32(setView.indexUint(currentOffset + BURN_INTENT_TRANSFER_SPEC_LENGTH_OFFSET, UINT32_BYTES));
            uint256 currentIntentTotalLength = BURN_INTENT_TRANSFER_SPEC_OFFSET + specLength;

            bytes29 intentView = setView.slice(
                currentOffset, currentIntentTotalLength, TransferSpecLib._toMemViewType(BURN_INTENT_MAGIC)
            );
            intentHashes[i] = _getBurnIntentTypedDataHash(intentView);

            // Update offset for the next iteration
            currentOffset += currentIntentTotalLength;
        }

        return keccak256(abi.encodePacked(BURN_INTENT_SET_TYPEHASH, keccak256(abi.encodePacked(intentHashes))));
    }

    /// Extracts the source signer from a burn intent or burn intent set
    ///
    /// @dev For a burn intent set, returns the source signer from the first intent
    ///      (all intents in a set must have the same signer)
    ///
    /// @param intent   The encoded burn intent or burn intent set
    /// @return         The source signer address
    function getSourceSigner(bytes memory intent) internal pure returns (address) {
        bytes29 ref = _asIntentOrSetView(intent);
        bytes29 transferSpec;

        if (_isSet(ref)) {
            // For intent sets, get the first intent's transfer spec
            Cursor memory c = cursor(intent);
            bytes29 firstIntent = next(c);
            transferSpec = getTransferSpec(firstIntent);
        } else {
            // For single intents, get the transfer spec directly
            transferSpec = getTransferSpec(ref);
        }

        // Extract and convert the source signer from bytes32 to address
        bytes32 signerBytes = TransferSpecLib.getSourceSigner(transferSpec);
        return AddressLib._bytes32ToAddress(signerBytes);
    }
}
