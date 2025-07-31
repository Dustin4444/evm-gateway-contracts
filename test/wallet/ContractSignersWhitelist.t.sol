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
import {ContractSignersWhitelist} from "src/modules/wallet/ContractSignersWhitelist.sol";

contract ContractSignersWhitelistHarness is ContractSignersWhitelist {
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
    }

    // Test function to expose the onlyWhitelistedContractSigner modifier
    function checkOnlyWhitelistedContractSignerModifier(address contractAddr)
        public
        onlyWhitelistedContractSigner(contractAddr)
    {}

    // Test function to expose the onlyContractSignersWhitelister modifier
    function checkOnlyContractSignersWhitelisterModifier() public onlyContractSignersWhitelister {}
}

contract ContractSignersWhitelistTest is Test {
    address private owner = makeAddr("owner");
    address private whitelister = makeAddr("whitelister");
    address private contractSigner = makeAddr("contractSigner");
    address private otherContract = makeAddr("otherContract");

    ContractSignersWhitelistHarness private whitelistContract;

    function setUp() public {
        whitelistContract = new ContractSignersWhitelistHarness();
        whitelistContract.initialize(owner);
    }

    function test_initialState() public {
        // Verify no whitelister is set initially
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersWhitelist.UnauthorizedContractSignersWhitelister.selector, whitelister
            )
        );
        vm.prank(whitelister);
        whitelistContract.checkOnlyContractSignersWhitelisterModifier();

        // Verify random contract is not whitelisted initially
        assertFalse(
            whitelistContract.isWhitelistedContractSigner(contractSigner),
            "Contract should not be whitelisted by default"
        );

        // Verify owner is correctly set
        assertEq(whitelistContract.owner(), owner, "Owner should be set correctly");

        // Verify whitelister is not set initially
        assertEq(
            whitelistContract.contractSignersWhitelister(), address(0), "Whitelister should be zero address initially"
        );
    }

    function test_updateContractSignersWhitelister_basicSuccess() public {
        vm.expectEmit(true, true, false, true);
        emit ContractSignersWhitelist.ContractSignersWhitelisterChanged(address(0), whitelister);

        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        // Verify whitelister is set correctly
        assertEq(whitelistContract.contractSignersWhitelister(), whitelister, "Whitelister should be set correctly");

        // Verify whitelister can whitelist contracts
        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(
            whitelistContract.isWhitelistedContractSigner(contractSigner),
            "Contract should be whitelisted by whitelister"
        );
    }

    function test_updateContractSignersWhitelister_changeWhitelister() public {
        // Set initial whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        address newWhitelister = makeAddr("newWhitelister");
        vm.expectEmit(true, true, false, true);
        emit ContractSignersWhitelist.ContractSignersWhitelisterChanged(whitelister, newWhitelister);

        // Update to new whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(newWhitelister);

        // Verify new whitelister can whitelist contracts
        vm.prank(newWhitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(
            whitelistContract.isWhitelistedContractSigner(contractSigner),
            "Contract should be whitelisted by new whitelister"
        );

        // Verify old whitelister cannot whitelist contracts
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersWhitelist.UnauthorizedContractSignersWhitelister.selector, whitelister
            )
        );
        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(otherContract);
    }

    function test_updateContractSignersWhitelister_isIdempotent() public {
        // Set initial whitelister
        vm.expectEmit(true, true, false, true);
        emit ContractSignersWhitelist.ContractSignersWhitelisterChanged(address(0), whitelister);

        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        // Set same whitelister again
        vm.expectEmit(true, true, false, true);
        emit ContractSignersWhitelist.ContractSignersWhitelisterChanged(whitelister, whitelister);

        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        // Verify whitelister still has permissions
        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(
            whitelistContract.isWhitelistedContractSigner(contractSigner),
            "Contract should be whitelisted after idempotent whitelister update"
        );
    }

    function test_updateContractSignersWhitelister_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, whitelister));
        vm.prank(whitelister);
        whitelistContract.updateContractSignersWhitelister(whitelister);
    }

    function test_whitelistContractSigner_success() public {
        // Set whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        vm.expectEmit(true, false, false, true);
        emit ContractSignersWhitelist.ContractSignerWhitelisted(contractSigner);

        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(whitelistContract.isWhitelistedContractSigner(contractSigner), "Contract should be whitelisted");
    }

    function test_whitelistContractSigner_revertIfNotWhitelister() public {
        // Set whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersWhitelist.UnauthorizedContractSignersWhitelister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        whitelistContract.whitelistContractSigner(contractSigner);
    }

    function test_whitelistContractSigner_isIdempotent() public {
        // Set whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        // Whitelist contract first time
        vm.expectEmit(true, false, false, true);
        emit ContractSignersWhitelist.ContractSignerWhitelisted(contractSigner);

        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(whitelistContract.isWhitelistedContractSigner(contractSigner), "Contract should be whitelisted");

        // Whitelist same contract again
        vm.expectEmit(true, false, false, true);
        emit ContractSignersWhitelist.ContractSignerWhitelisted(contractSigner);

        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(
            whitelistContract.isWhitelistedContractSigner(contractSigner), "Contract should still be whitelisted"
        );
    }

    function test_unwhitelistContractSigner_success() public {
        // Set whitelister and whitelist contract
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        assertTrue(
            whitelistContract.isWhitelistedContractSigner(contractSigner), "Contract should be whitelisted initially"
        );

        // Unwhitelist contract
        vm.expectEmit(true, false, false, true);
        emit ContractSignersWhitelist.ContractSignerUnwhitelisted(contractSigner);

        vm.prank(whitelister);
        whitelistContract.unwhitelistContractSigner(contractSigner);

        assertFalse(whitelistContract.isWhitelistedContractSigner(contractSigner), "Contract should be unwhitelisted");
    }

    function test_unwhitelistContractSigner_revertIfNotWhitelister() public {
        // Set whitelister and whitelist contract
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersWhitelist.UnauthorizedContractSignersWhitelister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        whitelistContract.unwhitelistContractSigner(contractSigner);
    }

    function test_unwhitelistContractSigner_isIdempotent() public {
        // Set whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        // Unwhitelist contract that was never whitelisted
        vm.expectEmit(true, false, false, true);
        emit ContractSignersWhitelist.ContractSignerUnwhitelisted(contractSigner);

        vm.prank(whitelister);
        whitelistContract.unwhitelistContractSigner(contractSigner);

        assertFalse(
            whitelistContract.isWhitelistedContractSigner(contractSigner), "Contract should remain unwhitelisted"
        );
    }

    function test_onlyWhitelistedContractSignerModifier_success() public {
        // Set whitelister and whitelist contract
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        vm.prank(whitelister);
        whitelistContract.whitelistContractSigner(contractSigner);

        // Should not revert for whitelisted contract
        whitelistContract.checkOnlyWhitelistedContractSignerModifier(contractSigner);
    }

    function test_onlyWhitelistedContractSignerModifier_revertIfNotWhitelisted() public {
        vm.expectRevert(
            abi.encodeWithSelector(ContractSignersWhitelist.ContractSignerNotWhitelisted.selector, contractSigner)
        );
        whitelistContract.checkOnlyWhitelistedContractSignerModifier(contractSigner);
    }

    function test_onlyContractSignersWhitelisterModifier_success() public {
        // Set whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        vm.prank(whitelister);
        whitelistContract.checkOnlyContractSignersWhitelisterModifier();
    }

    function test_onlyContractSignersWhitelisterModifier_revertIfNotWhitelister() public {
        address unauthorized = makeAddr("unauthorized");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContractSignersWhitelist.UnauthorizedContractSignersWhitelister.selector, unauthorized
            )
        );
        vm.prank(unauthorized);
        whitelistContract.checkOnlyContractSignersWhitelisterModifier();
    }

    function test_multipleContractsWhitelisting() public {
        // Set whitelister
        vm.prank(owner);
        whitelistContract.updateContractSignersWhitelister(whitelister);

        address contract1 = makeAddr("contract1");
        address contract2 = makeAddr("contract2");
        address contract3 = makeAddr("contract3");

        // Whitelist multiple contracts
        vm.startPrank(whitelister);
        whitelistContract.whitelistContractSigner(contract1);
        whitelistContract.whitelistContractSigner(contract2);
        whitelistContract.whitelistContractSigner(contract3);
        vm.stopPrank();

        // Verify all are whitelisted
        assertTrue(whitelistContract.isWhitelistedContractSigner(contract1), "Contract1 should be whitelisted");
        assertTrue(whitelistContract.isWhitelistedContractSigner(contract2), "Contract2 should be whitelisted");
        assertTrue(whitelistContract.isWhitelistedContractSigner(contract3), "Contract3 should be whitelisted");

        // Unwhitelist one
        vm.prank(whitelister);
        whitelistContract.unwhitelistContractSigner(contract2);

        // Verify states
        assertTrue(whitelistContract.isWhitelistedContractSigner(contract1), "Contract1 should still be whitelisted");
        assertFalse(whitelistContract.isWhitelistedContractSigner(contract2), "Contract2 should be unwhitelisted");
        assertTrue(whitelistContract.isWhitelistedContractSigner(contract3), "Contract3 should still be whitelisted");
    }
}
