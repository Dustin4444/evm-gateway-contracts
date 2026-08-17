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

import {GatewayCommon} from "src/GatewayCommon.sol";
import {Mints} from "src/modules/minter/Mints.sol";

/// @title GatewayMinter
///
/// @notice This contract allows the minting of funds deposited in the GatewayWallet contract, either on the same chain
/// or on a different chain. Either operation requires a signed attestation from the `attestationSigner` configured in
/// the contract. See the documentation for the `GatewayWallet` contract for more details.
contract GatewayMinter is GatewayCommon, Mints {
    /// Thrown when attempting to renounce ownership
    error RenounceOwnershipDisabled();

    /// Thrown when the length of `supportedTokens_` and `tokenMintAuthorities_` do not match
    error MismatchedLengthTokenAndTokenMintAuthorities();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Ensure that the implementation contract cannot be initialized, only the proxy
        _disableInitializers();
    }

    /// Initializes the contract and all of its modules, in the order of inheritance
    ///
    /// @dev Assumes the contract is being deployed behind a proxy and that the proxy has already been initialized using
    ///      the `UpgradeablePlaceholder` contract
    ///
    /// @param pauser_                 The address to initialize the `pauser` role
    /// @param denylister_             The address to initialize the `denylister` role
    /// @param supportedTokens_        The list of tokens to support initially
    /// @param domain_                 The operator-issued identifier for this chain
    /// @param attestationSigner_      The address to initialize the `attestationSigner` role
    /// @param tokenMintAuthorities_   The list of initial token mint authorities (use the zero address for none)
    function initialize(
        address pauser_,
        address denylister_,
        address[] calldata supportedTokens_,
        uint32 domain_,
        address attestationSigner_,
        address[] calldata tokenMintAuthorities_
    ) external reinitializer(2) {
        if (supportedTokens_.length != tokenMintAuthorities_.length) {
            revert MismatchedLengthTokenAndTokenMintAuthorities();
        }

        __GatewayCommon_init(pauser_, denylister_, supportedTokens_, domain_);
        __Mints_init(attestationSigner_, supportedTokens_, tokenMintAuthorities_);
    }

    /// @notice Renouncing ownership is disabled to prevent accidental loss of contract control
    /// @dev Overrides OwnableUpgradeable.renounceOwnership() to always revert
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }
}
