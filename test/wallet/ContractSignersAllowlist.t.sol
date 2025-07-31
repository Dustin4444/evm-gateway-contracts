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
}

contract ContractSignersAllowlistTest is Test {
    address private owner = makeAddr("owner");
    address private allowlister = makeAddr("allowlister");
    address private contractSigner = makeAddr("contractSigner");
    address private otherContract = makeAddr("otherContract");

    ContractSignersAllowlistHarness private allowlistContract;

    function setUp() public {
        allowlistContract = new ContractSignersAllowlistHarness();
        allowlistContract.initialize(owner);
    }

    function test_initialState() public {
        // Verify no allowlister is set initially
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, allowlister)
        );
        vm.prank(allowlister);
        allowlistContract.checkOnlyContractSignersAllowlisterModifier();

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

    function test_allowlistContractSigner_success() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerAllowlisted(contractSigner);

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be allowlisted");
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
    }

    function test_disallowContractSigner_success() public {
        // Set allowlister and allowlist contract
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        assertTrue(
            allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be allowlisted initially"
        );

        // Disallow contract
        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerDisallowed(contractSigner);

        vm.prank(allowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should be disallowed");
    }

    function test_disallowContractSigner_revertIfNotAllowlister() public {
        // Set allowlister and allowlist contract
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(contractSigner);

        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersAllowlist.UnauthorizedContractSignerAllowlister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        allowlistContract.disallowContractSigner(contractSigner);
    }

    function test_disallowContractSigner_revertIfZeroAddress() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressContractSigner.selector));
        vm.prank(allowlister);
        allowlistContract.disallowContractSigner(address(0));
    }

    function test_disallowContractSigner_isIdempotent() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Disallow contract that was never allowlisted
        vm.expectEmit(true, false, false, true);
        emit ContractSignersAllowlist.ContractSignerDisallowed(contractSigner);

        vm.prank(allowlister);
        allowlistContract.disallowContractSigner(contractSigner);

        assertFalse(allowlistContract.isAllowlistedContractSigner(contractSigner), "Contract should remain disallowed");
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

    function test_multipleContractsAllowlisting() public {
        // Set allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

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
        vm.prank(allowlister);
        allowlistContract.disallowContractSigner(contract2);

        // Verify states
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract1), "Contract1 should still be allowlisted");
        assertFalse(allowlistContract.isAllowlistedContractSigner(contract2), "Contract2 should be disallowed");
        assertTrue(allowlistContract.isAllowlistedContractSigner(contract3), "Contract3 should still be allowlisted");
    }

    function test_isAllowlistedContractSigner_zeroAddressReturnsFalse() public {
        assertFalse(allowlistContract.isAllowlistedContractSigner(address(0)), "Zero address should not be allowlisted");
    }

    function test_zeroAddressHandling_comprehensive() public {
        // Set valid allowlister
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(allowlister);

        // Verify zero address cannot be allowlisted
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressContractSigner.selector));
        vm.prank(allowlister);
        allowlistContract.allowlistContractSigner(address(0));

        // Verify zero address cannot be disallowed
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressContractSigner.selector));
        vm.prank(allowlister);
        allowlistContract.disallowContractSigner(address(0));

        // Verify zero address cannot be set as allowlister
        vm.expectRevert(abi.encodeWithSelector(ContractSignersAllowlist.ZeroAddressAllowlister.selector));
        vm.prank(owner);
        allowlistContract.updateContractSignersAllowlister(address(0));

        // Verify zero address is not allowlisted by default
        assertFalse(
            allowlistContract.isAllowlistedContractSigner(address(0)), "Zero address should never be allowlisted"
        );
    }
}
