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

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Contract Signer Allowlist Status
///
/// @notice Represents the possible states of a contract signer's allowlist status.
enum ContractSignerAllowlistStatus {
    /// The contract signer has never been allowlisted
    Unallowlisted,
    /// The contract signer is allowlisted
    Allowlisted,
    /// The contract signer was previously allowlisted, but the allowlist has been revoked. This state is distinct from
    /// `Unallowlisted` to handle specific scenarios like signed burn intents.
    Revoked
}

/// @title ContractSignersAllowlist
///
/// @notice Manages an allowlist of contract addresses that can use EIP-1271 signing for burn intents.
contract ContractSignersAllowlist is Initializable, Ownable2StepUpgradeable {
    /// Emitted when a contract is added to the signers allowlist
    ///
    /// @param contractAddr   The contract address that is now allowed to use EIP-1271 signing
    event ContractSignerAllowlisted(address indexed contractAddr);

    /// Emitted when a contract is removed from the signers allowlist
    ///
    /// @param contractAddr   The contract address that is no longer allowed to use EIP-1271 signing
    event ContractSignerDisallowed(address indexed contractAddr);

    /// Emitted when the contract signers allowlister address is updated
    ///
    /// @param oldAllowlister   The old allowlister address
    /// @param newAllowlister   The new allowlister address
    event ContractSignersAllowlisterChanged(address indexed oldAllowlister, address indexed newAllowlister);

    /// Thrown when an unauthorized address attempts to allowlist or disallow contract signers
    ///
    /// @param addr   The unauthorized address
    error UnauthorizedContractSignerAllowlister(address addr);

    /// Thrown when attempting to set the zero address as a contract signer
    error ZeroAddressContractSigner();

    /// Thrown when attempting to set the zero address as the allowlister
    error ZeroAddressAllowlister();

    /// Initializes the `contractSignersAllowlister` role
    ///
    /// @param allowlister_   The initial contract signers allowlister address
    function __ContractSignersAllowlist_init(address allowlister_) internal onlyInitializing {
        updateContractSignersAllowlister(allowlister_);
    }

    /// Restricts the caller to the `contractSignersAllowlister` role, reverting with an error for other callers
    modifier onlyContractSignersAllowlister() {
        if (msg.sender != ContractSignersAllowlistStorage.get().allowlister) {
            revert UnauthorizedContractSignerAllowlister(msg.sender);
        }
        _;
    }

    /// Whether or not a given contract is allowlisted for EIP-1271 signing
    ///
    /// @param contractAddr   The contract address to check
    /// @return               `true` if the contract is allowlisted, `false` otherwise
    function isAllowlistedContractSigner(address contractAddr) public view returns (bool) {
        return ContractSignersAllowlistStorage.get().allowlistMapping[contractAddr] == ContractSignerAllowlistStatus.Allowlisted;
    }

    /// The address with the `contractSignersAllowlister` role that can modify the allowlist
    ///
    /// @return   The address of the contract signers allowlister
    function contractSignersAllowlister() public view returns (address) {
        return ContractSignersAllowlistStorage.get().allowlister;
    }

    /// Allowlists a contract for EIP-1271 signing of burn intents
    ///
    /// @dev May only be called by the `contractSignersAllowlister` role
    ///
    /// @param contractAddr   The contract address to be allowlisted
    function allowlistContractSigner(address contractAddr) external onlyContractSignersAllowlister {
        _setContractSignerAllowlist(contractAddr, ContractSignerAllowlistStatus.Allowlisted);
        emit ContractSignerAllowlisted(contractAddr);
    }

    /// Removes a previously-allowlisted contract from the signers allowlist
    ///
    /// @dev May only be called by the `contractSignersAllowlister` role
    ///
    /// @param contractAddr   The contract address to be removed from the allowlist
    function disallowContractSigner(address contractAddr) external onlyContractSignersAllowlister {
        _setContractSignerAllowlist(contractAddr, ContractSignerAllowlistStatus.Revoked);
        emit ContractSignerDisallowed(contractAddr);
    }

    /// Sets the address that is allowed to modify the contract signers allowlist
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param newAllowlister   The new contract signers allowlister address
    function updateContractSignersAllowlister(address newAllowlister) public onlyOwner {
        address oldAllowlister = ContractSignersAllowlistStorage.get().allowlister;
        _setContractSignersAllowlister(newAllowlister);
        emit ContractSignersAllowlisterChanged(oldAllowlister, newAllowlister);
    }

    /// Sets the allowlist status of a contract address
    ///
    /// @param contractAddr   The contract address to set the allowlist status for
    /// @param status         The new allowlist status
    function _setContractSignerAllowlist(address contractAddr, ContractSignerAllowlistStatus status) internal {
        if (contractAddr == address(0)) {
            revert ZeroAddressContractSigner();
        }
        ContractSignersAllowlistStorage.get().allowlistMapping[contractAddr] = status;
    }

    /// Sets the address that is allowed to modify the contract signers allowlist
    ///
    /// @param newAllowlister   The new contract signers allowlister address
    function _setContractSignersAllowlister(address newAllowlister) internal {
        if (newAllowlister == address(0)) {
            revert ZeroAddressAllowlister();
        }
        ContractSignersAllowlistStorage.get().allowlister = newAllowlister;
    }

    /// Check if an address has ever been allowlisted for EIP-1271 signing. This includes both currently-valid and
    /// revoked allowlists.
    ///
    /// @param contractAddr   The contract address to check
    /// @return               `true` if the address has ever been allowlisted, `false` otherwise
    function _wasEverAllowlisted(address contractAddr)
        internal
        view
        returns (bool)
    {
        // A contract is always allowlisted for its own balance
        if (contractAddr == address(0)) return true;

        // Otherwise, check that the stored allowlist status is either `Allowlisted` or `RevokedAllowlist`
        ContractSignerAllowlistStatus status = ContractSignersAllowlistStorage.get().allowlistMapping[contractAddr];
        return status != ContractSignerAllowlistStatus.Unallowlisted;
    }
}

/// @title ContractSignersAllowlistStorage
///
/// @notice Implements the EIP-7201 storage pattern for the `ContractSignersAllowlist` module
library ContractSignersAllowlistStorage {
    /// @custom:storage-location erc7201:circle.gateway.ContractSignersAllowlist
    struct Data {
        /// Mapping of contract addresses to their allowlist status for EIP-1271 signing
        mapping(address contractAddr => ContractSignerAllowlistStatus status) allowlistMapping;
        /// The address that is allowed to manage the contract signers allowlist
        address allowlister;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.gateway.ContractSignersAllowlist"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x58960da9f0adf5297f1849efa99efb3521e67c0d073415e0a1fffdf74f3c3400;

    /// EIP-7201 getter for the storage slot
    ///
    /// @return $   The storage struct for the `ContractSignersAllowlist` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
