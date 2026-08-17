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
import {Test} from "forge-std/Test.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {
    ContractSignatureSigners, ContractSignatureSignersStorage
} from "src/modules/wallet/ContractSignatureSigners.sol";

contract ContractSignatureSignersHarness is ContractSignatureSigners {
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
    }
}

contract ContractSignatureSignersTest is Test {
    address private owner = makeAddr("owner");
    address private teeSigner = makeAddr("teeSigner");
    address private teeSigner2 = makeAddr("teeSigner2");
    address private unauthorized = makeAddr("unauthorized");

    ContractSignatureSignersHarness private signersContract;

    function setUp() public {
        signersContract = new ContractSignatureSignersHarness();
        signersContract.initialize(owner);
    }

    // ============================================
    // 1. testAddContractSignatureSigner
    // ============================================
    function test_addContractSignatureSigner_success() public {
        vm.expectEmit(true, false, false, true);
        emit ContractSignatureSigners.ContractSignatureSignerAdded(teeSigner);

        vm.prank(owner);
        signersContract.addContractSignatureSigner(teeSigner);

        assertTrue(signersContract.isContractSignatureSigner(teeSigner), "TEE signer should be registered after adding");
    }

    function test_addContractSignatureSigner_isIdempotent() public {
        // Add TEE signer first time
        vm.expectEmit(true, false, false, true);
        emit ContractSignatureSigners.ContractSignatureSignerAdded(teeSigner);

        vm.prank(owner);
        signersContract.addContractSignatureSigner(teeSigner);

        assertTrue(signersContract.isContractSignatureSigner(teeSigner), "TEE signer should be registered");

        // Add same TEE signer again
        vm.expectEmit(true, false, false, true);
        emit ContractSignatureSigners.ContractSignatureSignerAdded(teeSigner);

        vm.prank(owner);
        signersContract.addContractSignatureSigner(teeSigner);

        assertTrue(signersContract.isContractSignatureSigner(teeSigner), "TEE signer should still be registered");
    }

    function test_addContractSignatureSigner_multipleSigners() public {
        // Add multiple TEE signers
        vm.startPrank(owner);
        signersContract.addContractSignatureSigner(teeSigner);
        signersContract.addContractSignatureSigner(teeSigner2);
        vm.stopPrank();

        assertTrue(signersContract.isContractSignatureSigner(teeSigner), "TEE signer 1 should be registered");
        assertTrue(signersContract.isContractSignatureSigner(teeSigner2), "TEE signer 2 should be registered");
    }

    // ============================================
    // 2. testRemoveContractSignatureSigner
    // ============================================
    function test_removeContractSignatureSigner_success() public {
        // Add TEE signer first
        vm.prank(owner);
        signersContract.addContractSignatureSigner(teeSigner);

        assertTrue(signersContract.isContractSignatureSigner(teeSigner), "TEE signer should be registered initially");

        // Remove TEE signer
        vm.expectEmit(true, false, false, true);
        emit ContractSignatureSigners.ContractSignatureSignerRemoved(teeSigner);

        vm.prank(owner);
        signersContract.removeContractSignatureSigner(teeSigner);

        assertFalse(
            signersContract.isContractSignatureSigner(teeSigner), "TEE signer should not be registered after removal"
        );
    }

    function test_removeContractSignatureSigner_isIdempotent() public {
        // Remove TEE signer that was never added
        vm.expectEmit(true, false, false, true);
        emit ContractSignatureSigners.ContractSignatureSignerRemoved(teeSigner);

        vm.prank(owner);
        signersContract.removeContractSignatureSigner(teeSigner);

        assertFalse(signersContract.isContractSignatureSigner(teeSigner), "TEE signer should remain unregistered");
    }

    function test_removeContractSignatureSigner_doesNotAffectOthers() public {
        // Add multiple TEE signers
        vm.startPrank(owner);
        signersContract.addContractSignatureSigner(teeSigner);
        signersContract.addContractSignatureSigner(teeSigner2);
        vm.stopPrank();

        // Remove one TEE signer
        vm.prank(owner);
        signersContract.removeContractSignatureSigner(teeSigner);

        assertFalse(signersContract.isContractSignatureSigner(teeSigner), "TEE signer 1 should be removed");
        assertTrue(signersContract.isContractSignatureSigner(teeSigner2), "TEE signer 2 should still be registered");
    }

    // ============================================
    // 3. testCannotAddZeroAddress
    // ============================================
    function test_addContractSignatureSigner_revertIfZeroAddress() public {
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        vm.prank(owner);
        signersContract.addContractSignatureSigner(address(0));
    }

    function test_isContractSignatureSigner_zeroAddressReturnsFalse() public view {
        assertFalse(signersContract.isContractSignatureSigner(address(0)), "Zero address should never be a TEE signer");
    }

    function test_removeContractSignatureSigner_revertIfZeroAddress() public {
        vm.expectRevert(AddressLib.InvalidAddress.selector);
        vm.prank(owner);
        signersContract.removeContractSignatureSigner(address(0));
    }

    // ============================================
    // 4. testOnlyOwnerCanAddContractSignatureSigner
    // ============================================
    function test_addContractSignatureSigner_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        vm.prank(unauthorized);
        signersContract.addContractSignatureSigner(teeSigner);
    }

    // ============================================
    // 5. testOnlyOwnerCanRemoveContractSignatureSigner
    // ============================================
    function test_removeContractSignatureSigner_revertIfNotOwner() public {
        // Add TEE signer as owner
        vm.prank(owner);
        signersContract.addContractSignatureSigner(teeSigner);

        // Try to remove as non-owner
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        vm.prank(unauthorized);
        signersContract.removeContractSignatureSigner(teeSigner);
    }

    // ============================================
    // 6. testStorageSlotIsCorrect
    // ============================================
    function test_storageSlotIsCorrect() public pure {
        // Dynamically calculate the expected storage slot using EIP-7201 formula
        bytes32 calculatedSlot = keccak256(
            abi.encode(uint256(keccak256(bytes("circle.gateway.ContractSignatureSigners"))) - 1)
        ) & ~bytes32(uint256(0xff));

        assertEq(
            ContractSignatureSignersStorage.SLOT, calculatedSlot, "Storage slot should match EIP-7201 calculated value"
        );
    }

    // ============================================
    // 7. testStorageIsolation
    // ============================================
    function test_storageIsolation() public {
        // This test verifies that ContractSignatureSigners storage is independent
        // We verify the storage namespace is unique by checking the slot value
        bytes32 contractSignatureSignersSlot = ContractSignatureSignersStorage.SLOT;

        // Verify it's a non-zero unique slot
        assertTrue(contractSignatureSignersSlot != bytes32(0), "Storage slot should be non-zero");

        // Add a TEE signer
        vm.prank(owner);
        signersContract.addContractSignatureSigner(teeSigner);

        // Verify it's registered
        assertTrue(signersContract.isContractSignatureSigner(teeSigner), "TEE signer should be registered");

        // Verify unrelated addresses are not affected
        assertFalse(signersContract.isContractSignatureSigner(teeSigner2), "Unrelated address should not be registered");
        assertFalse(signersContract.isContractSignatureSigner(owner), "Owner should not be registered as TEE signer");
        assertFalse(
            signersContract.isContractSignatureSigner(unauthorized),
            "Unauthorized should not be registered as TEE signer"
        );
    }
}
