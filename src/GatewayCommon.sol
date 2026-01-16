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
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Denylist} from "src/modules/common/Denylist.sol";
import {Domain} from "src/modules/common/Domain.sol";
import {Pausing} from "src/modules/common/Pausing.sol";
import {TokenSupport} from "src/modules/common/TokenSupport.sol";
import {TransferSpecHashes} from "src/modules/common/TransferSpecHashes.sol";

/// @title GatewayCommon
///
/// @notice Contains functionality that is common between `GatewayWallet` and `GatewayMinter`
contract GatewayCommon is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    Pausing,
    Denylist,
    TokenSupport,
    TransferSpecHashes,
    Domain
{
    /// Emitted when the depositor does not have a sufficient balance to cover what needs to be burned or spent. This should
    /// never happen under normal circumstances.
    ///
    /// @param token                The token being burned
    /// @param depositor            The depositor who owns the balance
    /// @param value                The amount that needed to be burned
    /// @param availableBalance     The amount that was present in the `available` balance
    /// @param withdrawingBalance   The amount that was present in the `withdrawing` balance
    event InsufficientBalance(
        address indexed token,
        address indexed depositor,
        uint256 value,
        uint256 availableBalance,
        uint256 withdrawingBalance
    );

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
    /// @param pauser_            The address to initialize the pauser role
    /// @param denylister_        The address to initialize the denylister role
    /// @param supportedTokens_   The list of tokens to support initially
    /// @param domain_            The operator-issued identifier for this chain
    function __GatewayCommon_init(
        address pauser_,
        address denylister_,
        address[] calldata supportedTokens_,
        uint32 domain_
    ) internal onlyInitializing {
        __Pausing_init(pauser_);
        __Denylist_init(denylister_);
        __TokenSupport_init(supportedTokens_);
        __Domain_init(domain_);
    }

    /// Implements the UUPS upgrade pattern by restricting upgrades to the owner
    ///
    /// @param newImplementation   The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
