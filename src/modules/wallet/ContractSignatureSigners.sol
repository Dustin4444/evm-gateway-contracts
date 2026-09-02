/**
 * Copyright 2026 Circle Internet Group, Inc. All rights reserved.
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

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AddressLib} from "src/lib/AddressLib.sol";

/// @title ContractSignatureSigners
///
/// @notice Manages a registry of TEE signers that can vouch for contract signatures on burn intents.
/// TEE signers perform off-chain validation and sign burn intents with ECDSA on behalf of contracts.
abstract contract ContractSignatureSigners is Initializable, Ownable2StepUpgradeable {
    /// Emitted when a contract signature signer is added
    ///
    /// @param signer   The contract signature signer address that was added
    event ContractSignatureSignerAdded(address indexed signer);

    /// Emitted when a contract signature signer is removed
    ///
    /// @param signer   The contract signature signer address that was removed
    event ContractSignatureSignerRemoved(address indexed signer);

    /// Initializes a contract signature signer
    ///
    /// @param contractSignatureSigner_     The address to initialize the `contractSignatureSigner` role
    function __ContractSignatureSigners_init(address contractSignatureSigner_) internal onlyInitializing {
        addContractSignatureSigner(contractSignatureSigner_);
    }

    /// Return whether an address is a registered contract signature signer (TEE signer)
    ///
    /// @param signer  The address to check
    /// @return        `true` if the address is a valid contract signature signer, `false` otherwise
    function isContractSignatureSigner(address signer) public view returns (bool) {
        return ContractSignatureSignersStorage.get().contractSignatureSigners[signer];
    }

    /// Adds an address that may sign burn intents on behalf of contracts (TEE signer)
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param signer  The contract signature signer address to add
    function addContractSignatureSigner(address signer) public onlyOwner {
        AddressLib._checkNotZeroAddress(signer);

        ContractSignatureSignersStorage.get().contractSignatureSigners[signer] = true;
        emit ContractSignatureSignerAdded(signer);
    }

    /// Removes an address from the set of valid contract signature signers
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param signer   The contract signature signer address to remove
    function removeContractSignatureSigner(address signer) public onlyOwner {
        AddressLib._checkNotZeroAddress(signer);

        ContractSignatureSignersStorage.get().contractSignatureSigners[signer] = false;
        emit ContractSignatureSignerRemoved(signer);
    }
}

/// @title ContractSignatureSignersStorage
///
/// @notice Implements the EIP-7201 storage pattern for contract signature signers
library ContractSignatureSignersStorage {
    /// @custom:storage-location erc7201:circle.gateway.ContractSignatureSigners
    struct Data {
        /// Addresses authorized to sign burn intents on behalf of contracts (TEE signers)
        mapping(address signer => bool valid) contractSignatureSigners;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.gateway.ContractSignatureSigners"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0xbaa373b8fef48c49e97baf12bc34fd53c221e00d7b2d626e2814bf0e0a885000;

    /// EIP-7201 getter for the storage slot
    ///
    /// @return $   The storage struct for contract signature signers
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
