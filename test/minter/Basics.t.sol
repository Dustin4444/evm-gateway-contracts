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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GatewayMinter} from "src/GatewayMinter.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {TokenSupport} from "src/modules/common/TokenSupport.sol";
import {Mints} from "src/modules/minter/Mints.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";
import {OwnershipTest} from "test/util/OwnershipTest.sol";

/// Tests ownership and initialization functionality of GatewayMinter
contract GatewayMinterBasicsTest is OwnershipTest, DeployUtils {
    uint32 private domain = 99;

    GatewayMinter private minter;

    /// Used by OwnershipTest
    function _subject() internal view override returns (address) {
        return address(minter);
    }

    function setUp() public {
        minter = deployMinterOnly(owner, ForkTestUtils.forkVars().domain);
    }

    function test_initialize_revertWhenReinitialized() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        minter.initialize(address(0), address(0), new address[](0), uint32(0), address(0), new address[](0));
    }

    function test_initialize_revertWhenTokenAndAuthorityLengthMismatch() public {
        // Deploy a new GatewayMinter implementation
        GatewayMinter minterImpl = new GatewayMinter();

        // Deploy a placeholder and then a proxy for it
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(UpgradeablePlaceholder.initialize, owner));

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = makeAddr("token1");

        address[] memory tokenMintAuthorities = new address[](2);
        tokenMintAuthorities[0] = makeAddr("authority1");
        tokenMintAuthorities[1] = makeAddr("authority2");

        // Prepare the calldata for the initialize function
        // Using 'owner' for the various addresses, since they don't matter for this test
        bytes memory initializeCalldata = abi.encodeCall(
            GatewayMinter.initialize, (owner, owner, supportedTokens, domain, owner, tokenMintAuthorities)
        );

        vm.startPrank(owner);
        vm.expectRevert(GatewayMinter.MismatchedLengthTokenAndTokenMintAuthorities.selector);
        UpgradeablePlaceholder(address(proxy)).upgradeToAndCall(address(minterImpl), initializeCalldata);
        vm.stopPrank();
    }

    function test_updateMintAuthority_revertWhenNotOwner() public {
        address randomCaller = makeAddr("random");
        address token = makeAddr("token");
        address newMintAuthority = makeAddr("newMintAuthority");

        vm.startPrank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomCaller));
        minter.updateMintAuthority(token, newMintAuthority);
    }

    function test_updateMintAuthority_revertWhenTokenNotSupported() public {
        address token = makeAddr("token");
        address newMintAuthority = makeAddr("newMintAuthority");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, token));
        minter.updateMintAuthority(token, newMintAuthority);
    }

    function test_updateMintAuthority_revertWhenZeroAddress() public {
        address token = makeAddr("token");

        // Add token support first
        vm.startPrank(owner);
        minter.addSupportedToken(token);

        vm.expectRevert(abi.encodeWithSelector(AddressLib.InvalidAddress.selector));
        minter.updateMintAuthority(token, address(0));
    }

    function test_updateMintAuthority_successFuzz(address token, address newMintAuthority) public {
        vm.assume(newMintAuthority != address(0));
        address oldMintAuthority = minter.tokenMintAuthority(token);

        // Add token support first
        vm.startPrank(owner);
        minter.addSupportedToken(token);

        vm.expectEmit(true, true, true, false, address(minter));
        emit Mints.MintAuthorityChanged(token, oldMintAuthority, newMintAuthority);

        minter.updateMintAuthority(token, newMintAuthority);
        assertEq(minter.tokenMintAuthority(token), newMintAuthority);
    }

    function test_updateMintAuthority_idempotent() public {
        address token = makeAddr("token");
        address mintAuthority = makeAddr("mintAuthority");

        // Add token support and set initial mint authority
        vm.startPrank(owner);
        minter.addSupportedToken(token);
        minter.updateMintAuthority(token, mintAuthority);

        // Update to same address again
        vm.expectEmit(true, true, true, false, address(minter));
        emit Mints.MintAuthorityChanged(token, mintAuthority, mintAuthority);
        minter.updateMintAuthority(token, mintAuthority);

        assertEq(minter.tokenMintAuthority(token), mintAuthority);
    }

    function test_addAttestationSigner_revertWhenNotOwner() public {
        address randomCaller = makeAddr("random");
        address newAttestationSigner = makeAddr("newAttestationSigner");

        vm.startPrank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomCaller));
        minter.addAttestationSigner(newAttestationSigner);
        vm.stopPrank();
    }

    function test_removeAttestationSigner_revertWhenNotOwner() public {
        address randomCaller = makeAddr("random");
        address oldAttestationSigner = minter.owner(); // owner is the initial attestation signer

        vm.startPrank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomCaller));
        minter.removeAttestationSigner(oldAttestationSigner);
        vm.stopPrank();
    }

    function test_addAttestationSigner_revertWhenZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        minter.addAttestationSigner(address(0));
        vm.stopPrank();
    }

    function test_removeAttestationSigner_revertWhenZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        minter.removeAttestationSigner(address(0));
        vm.stopPrank();
    }

    function test_addAttestationSigner_success(address newAttestationSigner) public {
        vm.assume(newAttestationSigner != address(0));

        vm.expectEmit(true, false, false, false, address(minter));
        emit Mints.AttestationSignerAdded(newAttestationSigner);

        vm.startPrank(owner);
        minter.addAttestationSigner(newAttestationSigner);
        vm.stopPrank();

        assertTrue(minter.isAttestationSigner(newAttestationSigner));
    }

    function test_removeAttestationSigner_success() public {
        address oldAttestationSigner = minter.owner(); // owner is the initial attestation signer

        vm.expectEmit(true, false, false, false, address(minter));
        emit Mints.AttestationSignerRemoved(oldAttestationSigner);

        vm.startPrank(owner);
        minter.removeAttestationSigner(oldAttestationSigner);
        vm.stopPrank();

        assertFalse(minter.isAttestationSigner(oldAttestationSigner));
    }

    function test_addAttestationSigner_idempotent() public {
        address newAttestationSigner = makeAddr("newAttestationSigner");

        vm.startPrank(owner);
        minter.addAttestationSigner(newAttestationSigner); // first update
        assertTrue(minter.isAttestationSigner(newAttestationSigner));

        vm.expectEmit(true, false, false, false, address(minter));
        emit Mints.AttestationSignerAdded(newAttestationSigner);
        minter.addAttestationSigner(newAttestationSigner); // second update
        vm.stopPrank();

        assertTrue(minter.isAttestationSigner(newAttestationSigner));
    }

    function test_removeAttestationSigner_idempotent() public {
        address oldAttestationSigner = minter.owner(); // owner is the initial attestation signer

        vm.startPrank(owner);
        minter.removeAttestationSigner(oldAttestationSigner); // first update
        assertFalse(minter.isAttestationSigner(oldAttestationSigner));

        vm.expectEmit(true, false, false, false, address(minter));
        emit Mints.AttestationSignerRemoved(oldAttestationSigner);
        minter.removeAttestationSigner(oldAttestationSigner); // second update
        vm.stopPrank();

        assertFalse(minter.isAttestationSigner(oldAttestationSigner));
    }

    function test_renounceOwnership_isDisabled() public {
        vm.prank(owner);
        vm.expectRevert(GatewayMinter.RenounceOwnershipDisabled.selector);
        minter.renounceOwnership();
    }
}
