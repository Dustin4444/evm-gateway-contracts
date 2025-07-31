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
import {Burns} from "src/modules/wallet/Burns.sol";
import {ContractSignersAllowlist} from "src/modules/wallet/ContractSignersAllowlist.sol";
import {Deposits} from "src/modules/wallet/Deposits.sol";
import {Withdrawals} from "src/modules/wallet/Withdrawals.sol";

/// @title GatewayWallet
///
/// @notice This contract allows users to deposit supported tokens. Once deposits are observed in a finalized block by
/// the operator, the user may request an attestation to instantly mint those funds on another chain. Minted funds are
/// then burned on the chain where they were deposited.
///
/// @notice The available balance is the amount the user has deposited that may be used instantly on any chain, subject
/// to finality observed by the operator and an attestation obtained from the API. To obtain an attestation, the user
/// must provide the operator with a signed message containing the desired parameters, which acts as a burn intent that
/// will allow the operator to burn those funds once the mint is observed on the destination chain.
///
/// @notice To mint funds on another chain, the user may use an attestation obtained from the API to call `gatewayMint`
/// on the `GatewayMinter` contract on the desired chain. This will mint the funds to the requested destination, and may
/// be composed with other actions via a multicall contract or SCA implementation. A fee is deducted from the user's
/// balance within the `GatewayWallet` contract in addition to the requested amount.
///
/// @notice For same-chain withdrawals, users can obtain an attestation from the API similar to cross-chain mints. They
/// then call `gatewayMint` on the `GatewayMinter` contract to receive their funds at their specified address, while
/// their original deposit in the `GatewayWallet` contract is subsequently burned. A fee is deducted from the user's
/// balance within the `GatewayWallet` contract in addition to the requested amount, since Circle incurs gas costs
/// for the burn operation.
///
/// @notice To ensure funds are withdrawable even if the API is unavailable, users may withdraw permissionlessly using a
/// two-step process. First, the user must call `initiateWithdrawal` with the desired withdrawal amount. After a delay,
/// the user may call `withdraw` to complete the withdrawal and receive the funds. This delay ensures that no
/// double-spends are possible and that the operator has time to burn any funds that are minted. The amount that is in
/// the process of being withdrawn will no longer be available as soon as the withdrawal initiation is observed by the
/// operator in a finalized block. If a double-spend was attempted, the contract will burn the user's funds from both
/// their `available` and `withdrawing` balances.
contract GatewayWallet is GatewayCommon, Deposits, Withdrawals, ContractSignersAllowlist, Burns {
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
    /// @param pauser_                        The address to initialize the `pauser` role
    /// @param denylister_                    The address to initialize the `denylister` role
    /// @param supportedTokens_               The list of tokens to support initially
    /// @param domain_                        The operator-issued identifier for this chain
    /// @param withdrawalDelay_               The initial value for `withdrawalDelay`, in blocks
    /// @param burnSigner_                    The address to initialize the `burnSigner` role
    /// @param feeRecipient_                  The address to initialize the `feeRecipient` role
    /// @param contractSignersAllowlister_    The address to initialize the `contractSignersAllowlister` role
    function initialize(
        address pauser_,
        address denylister_,
        address[] calldata supportedTokens_,
        uint32 domain_,
        uint256 withdrawalDelay_,
        address burnSigner_,
        address feeRecipient_,
        address contractSignersAllowlister_
    ) external reinitializer(2) {
        __GatewayCommon_init(pauser_, denylister_, supportedTokens_, domain_);
        __Withdrawals_init(withdrawalDelay_);
        __ContractSignersAllowlist_init(contractSignersAllowlister_);
        __Burns_init(burnSigner_, feeRecipient_);
    }
}
