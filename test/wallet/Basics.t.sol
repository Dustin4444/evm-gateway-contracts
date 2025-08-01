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

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {Burns} from "src/modules/wallet/Burns.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";
import {OwnershipTest} from "test/util/OwnershipTest.sol";

/// Tests ownership and initialization functionality of GatewayWallet
contract GatewayWalletBasicsTest is OwnershipTest, DeployUtils {
    uint32 private domain = 99;

    GatewayWallet private wallet;

    /// Used by OwnershipTest
    function _subject() internal view override returns (address) {
        return address(wallet);
    }

    function setUp() public {
        wallet = deployWalletOnly(owner, ForkTestUtils.forkVars().domain);
    }

    function test_initialize_revertWhenReinitialized() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        wallet.initialize(address(0), address(0), new address[](0), uint32(0), 1, address(0), address(0), address(0));
    }

    function test_addBurnSigner_revertWhenNotOwner() public {
        address randomCaller = makeAddr("random");
        address newBurnSigner = makeAddr("newBurnSigner");

        vm.startPrank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomCaller));
        wallet.addBurnSigner(newBurnSigner);
        vm.stopPrank();
    }

    function test_removeBurnSigner_revertWhenNotOwner() public {
        address randomCaller = makeAddr("random");
        address oldBurnSigner = wallet.owner(); // owner is the initial burn signer

        vm.startPrank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomCaller));
        wallet.removeBurnSigner(oldBurnSigner);
        vm.stopPrank();
    }

    function test_addBurnSigner_revertWhenZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        wallet.addBurnSigner(address(0));
        vm.stopPrank();
    }

    function test_removeBurnSigner_revertWhenZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        wallet.removeBurnSigner(address(0));
        vm.stopPrank();
    }

    function test_addBurnSigner_success(address newBurnSigner) public {
        vm.assume(newBurnSigner != address(0));

        vm.expectEmit(true, false, false, false, address(wallet));
        emit Burns.BurnSignerAdded(newBurnSigner);

        vm.startPrank(owner);
        wallet.addBurnSigner(newBurnSigner);
        vm.stopPrank();

        assertTrue(wallet.isBurnSigner(newBurnSigner));
    }

    function test_removeBurnSigner_success() public {
        address oldBurnSigner = wallet.owner(); // owner is the initial burn signer

        vm.expectEmit(true, false, false, false, address(wallet));
        emit Burns.BurnSignerRemoved(oldBurnSigner);

        vm.startPrank(owner);
        wallet.removeBurnSigner(oldBurnSigner);
        vm.stopPrank();

        assertFalse(wallet.isBurnSigner(oldBurnSigner));
    }

    function test_addBurnSigner_idempotent() public {
        address newBurnSigner = makeAddr("newBurnSigner");

        vm.startPrank(owner);
        wallet.addBurnSigner(newBurnSigner); // first update
        assertTrue(wallet.isBurnSigner(newBurnSigner));

        vm.expectEmit(true, false, false, false, address(wallet));
        emit Burns.BurnSignerAdded(newBurnSigner);
        wallet.addBurnSigner(newBurnSigner); // second update
        vm.stopPrank();

        assertTrue(wallet.isBurnSigner(newBurnSigner));
    }

    function test_removeBurnSigner_idempotent() public {
        address oldBurnSigner = wallet.owner(); // owner is the initial burn signer

        vm.startPrank(owner);
        wallet.removeBurnSigner(oldBurnSigner); // first update
        assertFalse(wallet.isBurnSigner(oldBurnSigner));

        vm.expectEmit(true, false, false, false, address(wallet));
        emit Burns.BurnSignerRemoved(oldBurnSigner);
        wallet.removeBurnSigner(oldBurnSigner); // second update
        vm.stopPrank();

        assertFalse(wallet.isBurnSigner(oldBurnSigner));
    }

    function test_updateFeeRecipient_revertWhenNotOwner() public {
        address randomCaller = makeAddr("random");
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.prank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomCaller));
        wallet.updateFeeRecipient(newFeeRecipient);
    }

    function test_updateFeeRecipient_revertWhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        wallet.updateFeeRecipient(address(0));
    }

    function test_updateFeeRecipient_success(address newFeeRecipient) public {
        vm.assume(newFeeRecipient != address(0));

        address oldFeeRecipient = wallet.feeRecipient();

        vm.expectEmit(true, true, false, false, address(wallet));
        emit Burns.FeeRecipientChanged(oldFeeRecipient, newFeeRecipient);

        vm.prank(owner);
        wallet.updateFeeRecipient(newFeeRecipient);

        assertEq(wallet.feeRecipient(), newFeeRecipient);
    }

    function test_updateFeeRecipient_idempotent() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        vm.startPrank(owner);
        wallet.updateFeeRecipient(newFeeRecipient); // first update
        assertEq(wallet.feeRecipient(), newFeeRecipient);

        vm.expectEmit(true, true, false, false, address(wallet));
        emit Burns.FeeRecipientChanged(newFeeRecipient, newFeeRecipient);
        wallet.updateFeeRecipient(newFeeRecipient); // second update

        assertEq(wallet.feeRecipient(), newFeeRecipient);
    }
}
