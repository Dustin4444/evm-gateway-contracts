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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Test} from "forge-std/Test.sol";
import {GatewayCommon} from "src/GatewayCommon.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {BatchedDelta} from "src/lib/BatchedDelta.sol";
import {TokenSupport} from "src/modules/common/TokenSupport.sol";
import {Batches} from "src/modules/wallet/Batches.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";

contract GatewayWalletBatchesTest is Test, DeployUtils {
    using MessageHashUtils for bytes32;

    address private owner = makeAddr("owner");
    address private usdc;
    uint32 private domain;

    // We'll use these as our testing addresses; they're initialized below
    address[] private addresses;
    uint256 private addressCount = 5;
    uint256 private initialAddressBalance = 1000 * 10 ** 6;

    // Batch signers for testing
    address private batchSigner1;
    address private batchSigner2;
    uint256 private batchSigner1PrivateKey;
    uint256 private batchSigner2PrivateKey;

    GatewayWallet private wallet;

    function setUp() public {
        domain = ForkTestUtils.forkVars().domain;
        wallet = deployWalletOnly(owner, domain);

        // Set up USDC
        usdc = ForkTestUtils.forkVars().usdc;
        vm.startPrank(owner);
        wallet.addSupportedToken(usdc);
        vm.stopPrank();

        // Set up batch signers
        batchSigner1PrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        batchSigner2PrivateKey = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        batchSigner1 = vm.addr(batchSigner1PrivateKey);
        batchSigner2 = vm.addr(batchSigner2PrivateKey);

        // Register batch signers
        vm.startPrank(owner);
        wallet.addBatchSigner(batchSigner1);
        wallet.addBatchSigner(batchSigner2);
        vm.stopPrank();

        // Set up some addresses to test with.
        for (uint256 i = 0; i < addressCount; i++) {
            // Make and save the address.  The abi.encode() is probably not producing a concatenated
            // string that actually looks like "address1", but we don't really care as long as it's
            // unique for each i.
            address addr = makeAddr(string.concat("address", string(abi.encode(i))));
            addresses.push(addr);

            // Give it some USDC
            deal(usdc, addr, initialAddressBalance);

            // Deposit that into Gateway
            vm.startPrank(addr);
            IERC20(usdc).approve(address(wallet), initialAddressBalance);
            wallet.deposit(usdc, initialAddressBalance);
            vm.stopPrank();

            // Make sure that the available balance is set as expected, and withdrawing balance
            // is 0.
            assertEq(initialAddressBalance, wallet.availableBalance(usdc, addr));
            assertEq(0, wallet.withdrawingBalance(usdc, addr));
        }
    }

    /// Utility function to sign batch data with a batch signer
    ///
    /// @param deltas               The batch deltas to sign
    /// @param batchId              The batch ID
    /// @param domainToSign         The domain
    /// @param tokenAddress         The token address
    /// @param gatewayWalletAddress The gateway wallet address
    /// @param signerPrivateKey     The private key of the signer
    /// @return calldataBytes       The ABI-encoded calldata
    /// @return signature           The signature of the calldata
    function signBatchData(
        BatchedDelta[] memory deltas,
        bytes32 batchId,
        uint32 domainToSign,
        address tokenAddress,
        address gatewayWalletAddress,
        uint256 signerPrivateKey
    ) internal pure returns (bytes memory calldataBytes, bytes memory signature) {
        // ABI encode the batch data
        calldataBytes = abi.encode(deltas, batchId, domainToSign, tokenAddress, gatewayWalletAddress);

        // Create the message hash using the same logic as _verifyBatchSignerSignature
        bytes32 messageHash = keccak256(calldataBytes).toEthSignedMessageHash();

        // Sign the message hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        signature = abi.encodePacked(r, s, v);
    }

    /// Helper functions to create BatchedDelta array with 1 delta.  Solidity doesn't have variadic
    /// functions so this is the best we can do.
    function _toDelta(address depositor1, int256 value1) internal pure returns (BatchedDelta[] memory deltas) {
        deltas = new BatchedDelta[](1);
        deltas[0] = BatchedDelta({depositor: depositor1, value: value1});
    }

    function _toDelta(address depositor1, int256 value1, address depositor2, int256 value2)
        internal
        pure
        returns (BatchedDelta[] memory deltas)
    {
        deltas = new BatchedDelta[](2);
        deltas[0] = BatchedDelta({depositor: depositor1, value: value1});
        deltas[1] = BatchedDelta({depositor: depositor2, value: value2});
    }

    function _toDelta(
        address depositor1,
        int256 value1,
        address depositor2,
        int256 value2,
        address depositor3,
        int256 value3
    ) internal pure returns (BatchedDelta[] memory deltas) {
        deltas = new BatchedDelta[](3);
        deltas[0] = BatchedDelta({depositor: depositor1, value: value1});
        deltas[1] = BatchedDelta({depositor: depositor2, value: value2});
        deltas[2] = BatchedDelta({depositor: depositor3, value: value3});
    }

    function _toDelta(
        address depositor1,
        int256 value1,
        address depositor2,
        int256 value2,
        address depositor3,
        int256 value3,
        address depositor4,
        int256 value4
    ) internal pure returns (BatchedDelta[] memory deltas) {
        deltas = new BatchedDelta[](4);
        deltas[0] = BatchedDelta({depositor: depositor1, value: value1});
        deltas[1] = BatchedDelta({depositor: depositor2, value: value2});
        deltas[2] = BatchedDelta({depositor: depositor3, value: value3});
        deltas[3] = BatchedDelta({depositor: depositor4, value: value4});
    }

    function _toDelta(
        address depositor1,
        int256 value1,
        address depositor2,
        int256 value2,
        address depositor3,
        int256 value3,
        address depositor4,
        int256 value4,
        address depositor5,
        int256 value5,
        address depositor6,
        int256 value6
    ) internal pure returns (BatchedDelta[] memory deltas) {
        deltas = new BatchedDelta[](6);
        deltas[0] = BatchedDelta({depositor: depositor1, value: value1});
        deltas[1] = BatchedDelta({depositor: depositor2, value: value2});
        deltas[2] = BatchedDelta({depositor: depositor3, value: value3});
        deltas[3] = BatchedDelta({depositor: depositor4, value: value4});
        deltas[4] = BatchedDelta({depositor: depositor5, value: value5});
        deltas[5] = BatchedDelta({depositor: depositor6, value: value6});
    }

    /// Test that an unregistered signer throws InvalidBatchSigner()
    function testSubmitBatchInvalidSigner() public {
        // Create a new signer that's not registered
        uint256 unregisteredSignerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
        vm.addr(unregisteredSignerPrivateKey);

        // Build batch call data with the unregistered signer
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], -100),
            keccak256("test-batch-invalid-signer"),
            domain,
            usdc,
            address(wallet),
            unregisteredSignerPrivateKey
        );

        // Call submitBatch and expect InvalidBatchSigner() error
        vm.expectRevert(abi.encodeWithSelector(Batches.InvalidBatchSigner.selector));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that a removed signer throws InvalidBatchSigner()
    function testSubmitBatchRemovedSigner() public {
        // Remove batchSigner1
        vm.startPrank(owner);
        wallet.removeBatchSigner(batchSigner1);
        vm.stopPrank();

        // Build batch call data with the removed signer
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], -100),
            keccak256("test-batch-removed-signer"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Call submitBatch and expect InvalidBatchSigner() error
        vm.expectRevert(abi.encodeWithSelector(Batches.InvalidBatchSigner.selector));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that malformed signatures revert
    function testSubmitBatchMalformedSignature() public {
        // Build valid batch call data and signature
        (bytes memory calldataBytes, bytes memory validSignature) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], -100),
            keccak256("test-batch-malformed-sig"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Make sure that the calldataBytes and validSignature pass so that the rest of the test is valid.
        wallet.submitBatch(calldataBytes, validSignature);

        // Test with signature that's too short (remove last byte)
        bytes memory shortSignature = new bytes(validSignature.length - 1);
        for (uint256 i = 0; i < shortSignature.length; i++) {
            shortSignature[i] = validSignature[i];
        }
        vm.expectRevert();
        wallet.submitBatch(calldataBytes, shortSignature);

        // Test with signature that's too long (add extra byte)
        bytes memory longSignature = new bytes(validSignature.length + 1);
        for (uint256 i = 0; i < validSignature.length; i++) {
            longSignature[i] = validSignature[i];
        }
        longSignature[validSignature.length] = 0x42;
        vm.expectRevert();
        wallet.submitBatch(calldataBytes, longSignature);

        // Test with signature that has one byte modified
        bytes memory modifiedSignature = new bytes(validSignature.length);
        for (uint256 i = 0; i < validSignature.length; i++) {
            modifiedSignature[i] = validSignature[i];
        }
        modifiedSignature[validSignature.length - 1] =
            bytes1(uint8(modifiedSignature[validSignature.length - 1]) ^ 0x01);
        vm.expectRevert();
        wallet.submitBatch(calldataBytes, modifiedSignature);

        // Test with calldata that has one byte modified
        bytes memory modifiedCalldata = new bytes(calldataBytes.length);
        for (uint256 i = 0; i < calldataBytes.length; i++) {
            modifiedCalldata[i] = calldataBytes[i];
        }
        modifiedCalldata[calldataBytes.length - 1] = bytes1(uint8(modifiedCalldata[calldataBytes.length - 1]) ^ 0x01);
        vm.expectRevert();
        wallet.submitBatch(modifiedCalldata, validSignature);

        // Test with empty calldataBytes
        bytes memory emptyCalldata = new bytes(0);
        vm.expectRevert();
        wallet.submitBatch(emptyCalldata, validSignature);

        // Test with empty signature
        bytes memory emptySignature = new bytes(0);
        vm.expectRevert();
        wallet.submitBatch(calldataBytes, emptySignature);
    }

    /// Test that wrong domain throws WrongDomain()
    function testSubmitBatchWrongDomain() public {
        // Build batch call data with wrong domain
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], -100),
            keccak256("test-batch-wrong-domain"),
            999999, // Wrong domain
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Call submitBatch and expect WrongDomain() error
        vm.expectRevert(abi.encodeWithSelector(Batches.WrongDomain.selector));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that wrong gateway wallet address throws WrongGatewayContract()
    function testSubmitBatchWrongGatewayContract() public {
        // Build batch call data with wrong gateway wallet address
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], -100),
            keccak256("test-batch-wrong-gateway"),
            domain,
            usdc,
            makeAddr("wrong-gateway"), // Wrong gateway wallet address
            batchSigner1PrivateKey
        );

        // Call submitBatch and expect WrongGatewayContract() error
        vm.expectRevert(abi.encodeWithSelector(Batches.WrongGatewayContract.selector));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that reusing a batch ID throws BatchIdUsed() but different batch IDs work
    function testSubmitBatchReuseBatchId() public {
        bytes32 batchId1 = keccak256("test-batch-reuse-1");
        bytes32 batchId2 = keccak256("test-batch-reuse-2");

        // Submit first batch successfully
        (bytes memory calldataBytes1, bytes memory signature1) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], -100),
            batchId1,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );
        wallet.submitBatch(calldataBytes1, signature1);

        // Try to submit the same batch ID again - should fail
        vm.expectRevert(abi.encodeWithSelector(Batches.BatchIdUsed.selector, batchId1));
        wallet.submitBatch(calldataBytes1, signature1);

        // Submit a batch with a different batch ID - should succeed
        (bytes memory calldataBytes2, bytes memory signature2) = signBatchData(
            _toDelta(addresses[1], 50, addresses[2], -50),
            batchId2,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );
        wallet.submitBatch(calldataBytes2, signature2);
    }

    /// Test that an supported token throws UnsupportedToken.
    function testSubmitBatchUnsupportedToken() public {
        address token = makeAddr("unsupportedtoken");
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -100, addresses[1], 100),
            keccak256("test-batch-unsupported-token"),
            domain,
            token,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Call submitBatch and expect WrongGatewayContract() error
        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, token));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that empty deltas array throws MustHaveAtLeastOneDelta()
    function testSubmitBatchEmptyDeltas() public {
        // Create empty deltas array
        BatchedDelta[] memory emptyDeltas = new BatchedDelta[](0);

        // Build batch call data with empty deltas
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            emptyDeltas, keccak256("test-batch-empty-deltas"), domain, usdc, address(wallet), batchSigner1PrivateKey
        );

        // Call submitBatch and expect MustHaveAtLeastOneDelta() error
        vm.expectRevert(abi.encodeWithSelector(Batches.MustHaveAtLeastOneDelta.selector));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that deltas with value 0 throw DeltaMustBeNonZero()
    function testSubmitBatchZeroValueDelta() public {
        // Build batch call data with zero-value delta using _toDelta
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            // Second delta has value 0
            _toDelta(addresses[0], 100, addresses[1], 0),
            keccak256("test-batch-zero-delta"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Call submitBatch and expect DeltaMustBeNonZero() error
        vm.expectRevert(abi.encodeWithSelector(Batches.DeltaMustBeNonZero.selector, addresses[1]));
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that deltas that don't sum to zero throw MustNetToZero()
    function testSubmitBatchMustNetToZero() public {
        // Test 1: Single positive delta
        (bytes memory calldataBytes1, bytes memory signature1) = signBatchData(
            _toDelta(addresses[0], 100), // Only positive delta
            keccak256("test-batch-single-positive"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );
        vm.expectRevert(abi.encodeWithSelector(Batches.MustNetToZero.selector, 100));
        wallet.submitBatch(calldataBytes1, signature1);

        // Test 2: Single negative delta
        (bytes memory calldataBytes2, bytes memory signature2) = signBatchData(
            _toDelta(addresses[0], -100), // Only negative delta
            keccak256("test-batch-single-negative"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );
        vm.expectRevert(abi.encodeWithSelector(Batches.MustNetToZero.selector, -100));
        wallet.submitBatch(calldataBytes2, signature2);

        // Test 3: Multiple deltas that sum to positive
        (bytes memory calldataBytes3, bytes memory signature3) = signBatchData(
            _toDelta(addresses[0], 100, addresses[1], 50, addresses[2], -75), // Sums to +75
            keccak256("test-batch-sum-positive"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );
        vm.expectRevert(abi.encodeWithSelector(Batches.MustNetToZero.selector, 75));
        wallet.submitBatch(calldataBytes3, signature3);

        // Test 4: Multiple deltas that sum to negative
        (bytes memory calldataBytes4, bytes memory signature4) = signBatchData(
            _toDelta(addresses[0], 50, addresses[1], -100, addresses[2], -25), // Sums to -75
            keccak256("test-batch-sum-negative"),
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );
        vm.expectRevert(abi.encodeWithSelector(Batches.MustNetToZero.selector, -75));
        wallet.submitBatch(calldataBytes4, signature4);
    }

    /// Basic batch transfer
    function testSubmitBatchSuccess() public {
        bytes32 batchId = keccak256("test-batch-success");

        // Build batch call data for transfer from addresses[0] to addresses[1]
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -100, addresses[1], 100),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Check that balances were updated correctly
        assertEq(wallet.availableBalance(usdc, addresses[0]), 999_999_900);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 1_000_000_100);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
    }

    /// Test multiple senders to one receiver
    function testSubmitBatchMultipleSendersToOneReceiver() public {
        bytes32 batchId = keccak256("test-batch-multiple-senders");

        // Build batch call data: addresses[0] and addresses[1] send to addresses[2]
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -50, addresses[1], -60, addresses[2], 110),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Check that balances were updated correctly
        assertEq(wallet.availableBalance(usdc, addresses[0]), 999_999_950);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 999_999_940);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[2]), 1_000_000_110);
        assertEq(wallet.withdrawingBalance(usdc, addresses[2]), 0);
    }

    /// Test one sender to multiple receivers
    function testSubmitBatchOneSenderToMultipleReceivers() public {
        bytes32 batchId = keccak256("test-batch-one-sender-multiple-receivers");

        // Build batch call data: addresses[0] sends to addresses[1] and addresses[2]
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -110, addresses[1], 50, addresses[2], 60),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Check that balances were updated correctly
        assertEq(wallet.availableBalance(usdc, addresses[0]), 999_999_890);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 1_000_000_050);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[2]), 1_000_000_060);
        assertEq(wallet.withdrawingBalance(usdc, addresses[2]), 0);
    }

    /// Test multiple senders to multiple receivers
    function testSubmitBatchMultipleSendersToMultipleReceivers() public {
        bytes32 batchId = keccak256("test-batch-multiple-senders-multiple-receivers");

        // Build batch call data: addresses[0] and addresses[1] send to addresses[2] and addresses[3]
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -50, addresses[1], -60, addresses[2], 70, addresses[3], 40),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Check that balances were updated correctly
        assertEq(wallet.availableBalance(usdc, addresses[0]), 999_999_950);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 999_999_940);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[2]), 1_000_000_070);
        assertEq(wallet.withdrawingBalance(usdc, addresses[2]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[3]), 1_000_000_040);
        assertEq(wallet.withdrawingBalance(usdc, addresses[3]), 0);
    }

    /// Test multiple deltas for the same sender and receiver.  There's no reason this should happen, but test
    /// that it works as expected to avoid any nasty surprises.
    function testSubmitBatchMultipleDeltasSameAddresses() public {
        bytes32 batchId = keccak256("test-batch-multiple-deltas-same-addresses");

        // Build batch call data: addresses[0] sends to addresses[1] in two separate deltas
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -30, addresses[1], 20, addresses[0], -11, addresses[1], 21),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Check that balances were updated correctly
        assertEq(wallet.availableBalance(usdc, addresses[0]), 999_999_959);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 1_000_000_041);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
    }

    /// Test that extremely large positive deltas cause overflow.  These can probably be avoided by
    /// correct ordering of the deltas, but make sure it errors if there are problems.
    function testSubmitBatchOverflow() public {
        bytes32 batchId = keccak256("test-batch-overflow");

        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(
                addresses[0],
                type(int256).max,
                addresses[1],
                type(int256).max,
                addresses[2],
                type(int256).max,
                addresses[3],
                -type(int256).max,
                addresses[3],
                -type(int256).max,
                addresses[3],
                -type(int256).max
            ),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // This should revert due to overflow when summing the deltas
        vm.expectRevert();
        wallet.submitBatch(calldataBytes, signature);
    }

    /// Test that it's able to split across both balances: first available, then withdrawing
    function testSubmitBatchInsufficientAvailableUsesWithdrawing() public {
        bytes32 batchId = keccak256("test-batch-insufficient-available");

        // Request a withdrawal of 999_999_900, moving it into the withdrawing balance
        vm.startPrank(addresses[0]);
        wallet.initiateWithdrawal(usdc, 999_999_900);
        vm.stopPrank();
        assertEq(wallet.availableBalance(usdc, addresses[0]), 100);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 999_999_900);

        // Transferring 101 will use the remaining 100 in the available balance, and 1 from the withdrawing balance.
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -101, addresses[1], 101),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Make sure the balances are correct
        assertEq(wallet.availableBalance(usdc, addresses[0]), 0);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 999_999_899);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 1_000_000_101);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
    }

    /// Test that it's able to pull all from the withdrawing balance
    function testSubmitBatchNoAvailableUsesWithdrawing() public {
        bytes32 batchId = keccak256("test-batch-insufficient-available");

        // Move everything to the withdrawing balance
        vm.startPrank(addresses[0]);
        wallet.initiateWithdrawal(usdc, initialAddressBalance);
        vm.stopPrank();
        assertEq(wallet.availableBalance(usdc, addresses[0]), 0);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), initialAddressBalance);

        // Transferring 100 will all come from the withdrawing balance.
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -100, addresses[1], 100),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect BatchProcessed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Make sure the balances are correct
        assertEq(wallet.availableBalance(usdc, addresses[0]), 0);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 999_999_900);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 1_000_000_100);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
    }

    // Insufficient balance is still processed, but complains
    function testSubmitBatchInsufficientBalance() public {
        bytes32 batchId = keccak256("test-batch-insufficient");

        // Move some of the balance to the withdrawing balance to make sure the balances are emitted correctly
        vm.startPrank(addresses[0]);
        wallet.initiateWithdrawal(usdc, 50);
        vm.stopPrank();
        assertEq(wallet.availableBalance(usdc, addresses[0]), 999_999_950);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 50);

        // Build batch call data for transfer from addresses[0] to addresses[1]
        (bytes memory calldataBytes, bytes memory signature) = signBatchData(
            _toDelta(addresses[0], -1_000_000_001, addresses[1], 1_000_000_001),
            batchId,
            domain,
            usdc,
            address(wallet),
            batchSigner1PrivateKey
        );

        // Expect InsufficientBalance event to be emitted
        vm.expectEmit(true, true, false, true);
        emit GatewayCommon.InsufficientBalance(usdc, addresses[0], 1_000_000_001, 999_999_950, 50);

        // Expect BatchProcessed event to still be emitted
        vm.expectEmit(true, true, true, true);
        emit Batches.BatchProcessed(batchId, batchSigner1, usdc);

        // Submit the batch
        wallet.submitBatch(calldataBytes, signature);

        // Check that balances were updated correctly
        assertEq(wallet.availableBalance(usdc, addresses[0]), 0);
        assertEq(wallet.withdrawingBalance(usdc, addresses[0]), 0);
        assertEq(wallet.availableBalance(usdc, addresses[1]), 2_000_000_001);
        assertEq(wallet.withdrawingBalance(usdc, addresses[1]), 0);
    }
}
