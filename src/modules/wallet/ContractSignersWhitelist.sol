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

/// @title ContractSignersWhitelist
///
/// @notice Manages a whitelist of contract addresses that are allowed to use EIP-1271 signing for burn intents.
contract ContractSignersWhitelist is Initializable, Ownable2StepUpgradeable {
    /// Emitted when a contract is added to the signers whitelist
    ///
    /// @param contractAddr   The contract address that is now allowed to use EIP-1271 signing
    event ContractSignerWhitelisted(address indexed contractAddr);

    /// Emitted when a contract is removed from the signers whitelist
    ///
    /// @param contractAddr   The contract address that is no longer allowed to use EIP-1271 signing
    event ContractSignerUnwhitelisted(address indexed contractAddr);

    /// Emitted when the contract signers whitelister address is updated
    ///
    /// @param oldWhitelister   The old whitelister address
    /// @param newWhitelister   The new whitelister address
    event ContractSignersWhitelisterChanged(address indexed oldWhitelister, address indexed newWhitelister);

    /// Thrown when an unauthorized address attempts to whitelist or un-whitelist contract signers
    ///
    /// @param addr   The unauthorized address
    error UnauthorizedContractSignersWhitelister(address addr);

    /// Thrown when a contract is not whitelisted for EIP-1271 signing
    ///
    /// @param contractAddr   The non-whitelisted contract address
    error ContractSignerNotWhitelisted(address contractAddr);

    /// Thrown when attempting to set the zero address as a contract signer
    error ZeroAddressContractSigner();

    /// Thrown when attempting to set the zero address as the whitelister
    error ZeroAddressWhitelister();

    /// Initializes the `contractSignersWhitelister` role
    ///
    /// @param whitelister_   The initial contract signers whitelister address
    function __ContractSignersWhitelist_init(address whitelister_) internal onlyInitializing {
        updateContractSignersWhitelister(whitelister_);
    }

    /// Restricts access to a function to contracts that are whitelisted for EIP-1271 signing
    ///
    /// @param contractAddr   The contract address to check
    modifier onlyWhitelistedContractSigner(address contractAddr) {
        _ensureWhitelistedContractSigner(contractAddr);
        _;
    }

    /// Restricts the caller to the `contractSignersWhitelister` role, reverting with an error for other callers
    modifier onlyContractSignersWhitelister() {
        if (msg.sender != ContractSignersWhitelistStorage.get().whitelister) {
            revert UnauthorizedContractSignersWhitelister(msg.sender);
        }
        _;
    }

    /// Whether or not a given contract is whitelisted for EIP-1271 signing
    ///
    /// @param contractAddr   The contract address to check
    /// @return               `true` if the contract is whitelisted, `false` otherwise
    function isWhitelistedContractSigner(address contractAddr) public view returns (bool) {
        return ContractSignersWhitelistStorage.get().whitelistMapping[contractAddr];
    }

    /// The address with the `contractSignersWhitelister` role that can modify the whitelist
    ///
    /// @return   The address of the contract signers whitelister
    function contractSignersWhitelister() public view returns (address) {
        return ContractSignersWhitelistStorage.get().whitelister;
    }

    /// Whitelists a contract for EIP-1271 signing of burn intents
    ///
    /// @dev May only be called by the `contractSignersWhitelister` role
    ///
    /// @param contractAddr   The contract address to be whitelisted
    function whitelistContractSigner(address contractAddr) external onlyContractSignersWhitelister {
        _setContractSignerWhitelist(contractAddr, true);
        emit ContractSignerWhitelisted(contractAddr);
    }

    /// Removes a previously-whitelisted contract from the signers whitelist
    ///
    /// @dev May only be called by the `contractSignersWhitelister` role
    ///
    /// @param contractAddr   The contract address to be removed from the whitelist
    function unwhitelistContractSigner(address contractAddr) external onlyContractSignersWhitelister {
        _setContractSignerWhitelist(contractAddr, false);
        emit ContractSignerUnwhitelisted(contractAddr);
    }

    /// Sets the address that is allowed to modify the contract signers whitelist
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param newWhitelister   The new contract signers whitelister address
    function updateContractSignersWhitelister(address newWhitelister) public onlyOwner {
        address oldWhitelister = ContractSignersWhitelistStorage.get().whitelister;
        _setContractSignersWhitelister(newWhitelister);
        emit ContractSignersWhitelisterChanged(oldWhitelister, newWhitelister);
    }

    /// Reverts if the given contract is not whitelisted for EIP-1271 signing
    ///
    /// @param contractAddr   The contract address to check
    function _ensureWhitelistedContractSigner(address contractAddr) internal view {
        if (!isWhitelistedContractSigner(contractAddr)) {
            revert ContractSignerNotWhitelisted(contractAddr);
        }
    }

    /// Sets the whitelist status of a contract address
    ///
    /// @param contractAddr   The contract address to set the whitelist status for
    /// @param whitelisted    Whether or not the contract should be whitelisted
    function _setContractSignerWhitelist(address contractAddr, bool whitelisted) internal {
        if (contractAddr == address(0)) {
            revert ZeroAddressContractSigner();
        }
        ContractSignersWhitelistStorage.get().whitelistMapping[contractAddr] = whitelisted;
    }

    /// Sets the address that is allowed to modify the contract signers whitelist
    ///
    /// @param newWhitelister   The new contract signers whitelister address
    function _setContractSignersWhitelister(address newWhitelister) internal {
        if (newWhitelister == address(0)) {
            revert ZeroAddressWhitelister();
        }
        ContractSignersWhitelistStorage.get().whitelister = newWhitelister;
    }
}

/// @title ContractSignersWhitelistStorage
///
/// @notice Implements the EIP-7201 storage pattern for the `ContractSignersWhitelist` module
library ContractSignersWhitelistStorage {
    /// @custom:storage-location erc7201:circle.gateway.ContractSignersWhitelist
    struct Data {
        /// Mapping of contract addresses to their whitelist status for EIP-1271 signing
        mapping(address contractAddr => bool whitelisted) whitelistMapping;
        /// The address that is allowed to manage the contract signers whitelist
        address whitelister;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.gateway.ContractSignersWhitelist"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x2e53b880d8af994a3dddf5b95440da73953943e43bfb20179225a60d4a188400;

    /// EIP-7201 getter for the storage slot
    ///
    /// @return $   The storage struct for the `ContractSignersWhitelist` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
