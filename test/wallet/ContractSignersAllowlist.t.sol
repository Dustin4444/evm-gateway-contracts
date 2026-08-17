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
import {ContractSignersAllowlist} from "src/modules/wallet/ContractSignersAllowlist.sol";

contract ContractSignersAllowlistHarness is ContractSignersAllowlist {
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
    }

    // Test function to expose the onlyContractSignersAllowlister modifier
    function checkOnlyContractSignersAllowlisterModifier() public onlyContractSignersAllowlister {}

    // Test function to expose the onlyContractSignersDisallowlister modifier
    function checkOnlyContractSignersDisallowlisterModifier() public onlyContractSignersDisallowlister {}

    function wasEverAllowlistedContractSigner(address contractAddr) public view returns (bool) {
        return _wasEverAllowlistedContractSigner(contractAddr);
    }
}

contract ContractSignersAllowlistTest is Test {
    address private owner = makeAddr("owner");
    address private allowlister = makeAddr("allowlister");
    address private disallowlister = makeAddr("disallowlister");
    address private contractSigner = makeAddr("contractSigner");
    address private otherContract = makeAddr("otherContract");

    ContractSignersAllowlistHarness private allowlistContract;

    function setUp() public {
        allowlistContract = new ContractSignersAllowlistHarness();
        allowlistContract.initialize(owner);
    }

    function _setBothRoles() internal {
        vm.startPrank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);
        vm.stopPrank();
    }

    function test_wasEverAllowlistedContractSigner_returnsFalseIfZeroAddress() public view {
        // Verify zero address is not allowlisted
        assertFalse(allowlistContract.wasEverAllowlistedContractSigner(address(0)));
    }

    function test_wasEverAllowlistedContractSigner_returnsTrueIfAllowlisted(address contractAddr) public {
        vm.assume(contractAddr != address(0));

        // Set a non-zero allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Allowlist contract
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractAddr);

        // Verify contract is allowlisted
        assertTrue(allowlistContract.wasEverAllowlistedContractSigner(contractAddr));
    }

    function test_wasEverAllowlistedContractSigner_returnsTrueIfAllowlistedThenDisallowed(address contractAddr)
        public
    {
        vm.assume(contractAddr != address(0));

        _setBothRoles();

        // Allowlist then disallow contract
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractAddr);
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractAddr);

        // Verify contract is allowlisted (was ever)
        assertTrue(allowlistContract.wasEverAllowlistedContractSigner(contractAddr));
    }

    function test_initialState() public {
        // Verify no allowlister is set initially
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, allowlister)
        );
        vm.prank(allowlister);
        allowlistContract.checkOnlyContractSignersAllowlisterModifier();

        // Verify no disallowlister is set initially
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerDisallowlister.selector, disallowlister
            )
        );
        vm.prank(disallowlister);
        allowlistContract.checkOnlyContractSignersDisallowlisterModifier();

        // Verify random contract is not allowlisted initially
        assertFalse(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should not be allowlisted by default"
        );

        // Verify owner is correctly set
        assertEq(allowlistContract.owner(), owner, "Owner should be set correctly");

        // Verify allowlister is not set initially
        assertEq(
            allowlistContract.contractSignersAllowlister(), address(0), "Allowlister should be zero address initially"
        );

        // Verify disallowlister is not set initially
        assertEq(
            allowlistContract.contractSignersDisallowlister(),
            address(0),
            "Disallowlister should be zero address initially"
        );
    }

    function test_updateContractSignersAllowlister_basicSuccess() public {
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersAllowlisterChanged(address(0), allowlister);

        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Verify allowlister is set correctly
        assertEq(allowlistContract.contractSignersAllowlister(), allowlister, "Allowlister should be set correctly");

        // Verify allowlister can allowlist contracts
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should be allowlisted by allowlister"
        );
    }

    function test_updateContractSignersAllowlister_changeAllowlister() public {
        // Set initial allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        address newAllowlister = makeAddr("newAllowlister");
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersAllowlisterChanged(allowlister, newAllowlister);

        // Update to new allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(newAllowlister);

        // Verify new allowlister can allowlist contracts
        vm.prank(newAllowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should be allowlisted by new allowlister"
        );

        // Verify old allowlister cannot allowlist contracts
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, allowlister)
        );
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(otherContract);
    }

    function test_updateContractSignersAllowlister_isIdempotent() public {
        // Set initial allowlister
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersAllowlisterChanged(address(0), allowlister);

        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Set same allowlister again
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersAllowlisterChanged(allowlister, allowlister);

        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Verify allowlister still has permissions
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should be allowlisted after idempotent allowlister update"
        );
    }

    function test_updateContractSignersAllowlister_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, allowlister));
        vm.prank(allowlister);
        allowlistContract.updateContractSignersAllowlister(allowlister);
    }

    function test_updateContractSignersAllowlister_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressAllowlister.selector));
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(address(0));
    }

    function test_updateContractSignersDisallowlister_basicSuccess() public {
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersDisallowlisterChanged(address(0), disallowlister);

        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);

        // Verify disallowlister is set correctly
        assertEq(
            allowlistContract.contractSignersDisallowlister(), disallowlister, "Disallowlister should be set correctly"
        );

        // Allowlist a contract via allowlister so disallow has something to do
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        // Verify disallowlister can disallow contracts
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should be disallowed by disallowlister"
        );
    }

    function test_updateContractSignersDisallowlister_changeDisallowlister() public {
        _setBothRoles();

        address newDisallowlister = makeAddr("newDisallowlister");
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersDisallowlisterChanged(disallowlister, newDisallowlister);

        // Update to new disallowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(newDisallowlister);

        // Allowlist a contract first
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        // Verify new disallowlister can disallow contracts
        vm.prank(newDisallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should be disallowed by new disallowlister"
        );

        // Verify old disallowlister cannot disallow contracts
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(otherContract);
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerDisallowlister.selector, disallowlister
            )
        );
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(otherContract);
    }

    function test_updateContractSignersDisallowlister_isIdempotent() public {
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersDisallowlisterChanged(address(0), disallowlister);

        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);

        // Set same disallowlister again
        vm.expectEmit(true, true, false, true);
        emit ContractSignersAllowlist.ContractSignersDisallowlisterChanged(disallowlister, disallowlister);

        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);

        // Verify disallowlister still has permissions on an allowlisted contract
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(
            allowlistContract.isAllowlistedContractSigner(contractSigner),
            "Contract should be disallowed after idempotent disallowlister update"
        );
    }

    function test_updateContractSignersDisallowlister_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, disallowlister));
        vm.prank(disallowlister);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);
    }

    function test_updateContractSignersDisallowlister_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressDisallowlister.selector));
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(address(0));
    }

    function test_allowlistContractSigner_success() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerAllowlisted(contractSigner);

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be allowlisted");
        assertTrue(
            allowlistContract.wasEverAllowlistedContractSigner(contractSigner), "Contract should have been allowlisted"
        );
    }

    function test_allowlistContractSigner_revertIfNotAllowlister() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        allowlistContract.allowlistContractSigner(contractSigner);
    }

    function test_allowlistContractSigner_revertIfCalledByDisallowlister() public {
        // The disallowlister must not be able to call allowlistContractSigner — this is the whole point of the split
        _setBothRoles();

        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, disallowlister
            )
        );
        vm.prank(disallowlister);
        allowlistContract.allowlistContractSigner(contractSigner);
    }

    function test_allowlistContractSigner_revertIfZeroAddress() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressContractSigner.selector));
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(address(0));
    }

    function test_allowlistContractSigner_isIdempotent() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Allowlist contract first time
        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerAllowlisted(contractSigner);

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be allowlisted");

        // Allowlist same contract again
        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerAllowlisted(contractSigner);

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(
            allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should still be allowlisted"
        );
        assertTrue(
            allowlistContract.wasEverAllowlistedContractSigner(contractSigner), "Contract should have been allowlisted"
        );
    }

    function test_disallowContractSigner_success() public {
        _setBothRoles();

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(
            allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be allowlisted initially"
        );

        // Disallow contract
        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerDisallowed(contractSigner);

        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be disallowed");
        assertTrue(
            allowlistContract.wasEverAllowlistedContractSigner(contractSigner), "Contract should have been allowlisted"
        );
    }

    function test_disallowContractSigner_revertIfNotDisallowlister() public {
        _setBothRoles();

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerDisallowlister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        allowlistContract.disallowContractSigner(contractSigner);
    }

    function test_disallowContractSigner_revertIfCalledByAllowlister() public {
        // The allowlister must not be able to call disallowContractSigner — this is the whole point of the split
        _setBothRoles();

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerDisallowlister.selector, allowlister
            )
        );
        vm.prank(allowlister);
        allowlistContract.disallowContractSigner(contractSigner);
    }

    function test_disallowContractSigner_revertIfZeroAddress() public {
        // Set disallowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);

        // The zero address can never have been allowlisted, so disallowing it reverts as never-allowlisted
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersAllowlist.ContractSignerNeverAllowlisted.selector, address(0))
        );
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(address(0));
    }

    function test_disallowContractSigner_revertIfNeverAllowlisted() public {
        // Set disallowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);

        // Disallowing a contract that was never allowlisted is not allowed and must revert
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersAllowlist.ContractSignerNeverAllowlisted.selector, contractSigner)
        );
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(
            allowlistContract.wasEverAllowlistedContractSigner(contractSigner),
            "Contract should not be recorded as ever allowlisted"
        );
    }

    function test_disallowContractSigner_isIdempotentForRevokedContract() public {
        _setBothRoles();

        // Allowlist then disallow the contract
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        // Disallowing an already-revoked contract is allowed and re-emits the event
        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerDisallowed(contractSigner);

        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should remain disallowed");
        assertTrue(
            allowlistContract.wasEverAllowlistedContractSigner(contractSigner), "Contract should have been allowlisted"
        );
    }

    function test_onlyContractSignersAllowlisterModifier_success() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.prank(allowlister);
        allowlistContract.checkOnlyContractSignersAllowlisterModifier();
    }

    function test_onlyContractSignersAllowlisterModifier_revertIfNotAllowlister() public {
        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        allowlistContract.checkOnlyContractSignersAllowlisterModifier();
    }

    function test_onlyContractSignersDisallowlisterModifier_success() public {
        // Set disallowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(disallowlister);

        vm.prank(disallowlister);
        allowlistContract.checkOnlyContractSignersDisallowlisterModifier();
    }

    function test_onlyContractSignersDisallowlisterModifier_revertIfNotDisallowlister() public {
        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerDisallowlister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        allowlistContract.checkOnlyContractSignersDisallowlisterModifier();
    }

    function test_allowlisterAndDisallowlisterAreIndependent() public {
        // The two roles are independent — updating one does not affect the other
        _setBothRoles();

        assertEq(allowlistContract.contractSignersAllowlister(), allowlister);
        assertEq(allowlistContract.contractSignersDisallowlister(), disallowlister);

        // Rotate the allowlister
        address newAllowlister = makeAddr("newAllowlister");
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(newAllowlister);

        // Disallowlister should be unchanged
        assertEq(allowlistContract.contractSignersDisallowlister(), disallowlister);

        // Rotate the disallowlister
        address newDisallowlister = makeAddr("newDisallowlister");
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(newDisallowlister);

        // Allowlister should be unchanged
        assertEq(allowlistContract.contractSignersAllowlister(), newAllowlister);
    }

    function test_multipleContractsAllowlisting() public {
        _setBothRoles();

        address contract1 = makeAddr("contract1");
        address contract2 = makeAddr("contract2");
        address contract3 = makeAddr("contract3");

        // Allowlist multiple contracts
        vm.startPrank(allowlister);
        allowlistContract.allowlistContractSigner(contract1);
        allowlistContract.allowlistContractSigner(contract2);
        allowlistContract.allowlistContractSigner(contract3);
        vm.stopPrank();

        // Verify all are allowlisted
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract1), "Contract1 should be allowlisted");
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract2), "Contract2 should be allowlisted");
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract3), "Contract3 should be allowlisted");

        // Disallow one
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(contract2);

        // Verify states
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract1), "Contract1 should still be allowlisted");
        assertFalse(allowlistContract.isAllowlistedContractSigner(contract2), "Contract2 should be disallowed");
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract3), "Contract3 should still be allowlisted");
    }

    function test_isAllowlistedContractSigner_zeroAddressReturnsFalse() public view {
        assertFalse(allowlistContract.isAllowlistedContractSigner(address(0)), "Zero address should not be allowlisted");
    }

    function test_zeroAddressHandling_comprehensive() public {
        // Set valid allowlister and disallowlister
        _setBothRoles();

        // Verify zero address cannot be allowlisted
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressContractSigner.selector));
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(address(0));

        // Verify zero address cannot be disallowed (it can never have been allowlisted)
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersAllowlist.ContractSignerNeverAllowlisted.selector, address(0))
        );
        vm.prank(disallowlister);
        allowlistContract.disallowContractSigner(address(0));

        // Verify zero address cannot be set as allowlister
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressAllowlister.selector));
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(address(0));

        // Verify zero address cannot be set as disallowlister
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressDisallowlister.selector));
        vm.prank(owner);
        allowlistContract.updateContractSignersDisallowlister(address(0));

        // Verify zero address is not allowlisted by default
        assertFalse(
            allowlistContract.isAllowlistedContractSigner(address(0)), "Zero address should never be allowlisted"
        );
    }
}
