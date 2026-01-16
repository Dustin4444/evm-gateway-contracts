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

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {GatewayCommon} from "src/GatewayCommon.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {BurnIntentLib} from "src/lib/BurnIntentLib.sol";
import {BurnIntent, BurnIntentSet} from "src/lib/BurnIntents.sol";
import {TransferSpec, TRANSFER_SPEC_VERSION} from "src/lib/TransferSpec.sol";
import {TransferSpecLib} from "src/lib/TransferSpecLib.sol";
import {TransferSpecHashes} from "src/modules/common/TransferSpecHashes.sol";
import {Burns} from "src/modules/wallet/Burns.sol";
import {Delegation} from "src/modules/wallet/Delegation.sol";
import {MasterMinter} from "test/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenV2_2} from "test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";
import {SignatureTestUtils} from "test/util/SignatureTestUtils.sol";

// solhint-disable max-states-count
contract GatewayWalletBurnsTest is SignatureTestUtils, DeployUtils {
    using MessageHashUtils for bytes32;

    uint32 private domain;
    address private owner = makeAddr("owner");
    address private feeRecipient = makeAddr("feeRecipient");
    uint256 private depositorKey;
    address private depositor;
    uint256 private depositor2Key;
    address private depositor2;
    uint256 private underFundedDepositorKey;
    address private underFundedDepositor;
    uint256 private delegateKey;
    address private delegate;
    address private recipient = makeAddr("recipient");
    address private otherToken = makeAddr("otherToken");
    address private destinationContract = makeAddr("destinationContract");
    address private destinationToken = makeAddr("destinationToken");
    address private burnSigner;
    uint256 private burnSignerKey;
    uint256 private defaultMaxBlockHeightOffset = 100;
    uint256 private defaultMaxFee = 10 ** 6;
    uint256 private depositorInitialBalance = 5 * 1000 * 10 ** 6;
    uint256 private depositor2InitialBalance = 3 * 1000 * 10 ** 6;
    bytes internal constant HOOK_DATA = "Test hook data";

    struct ExpectedBurnEventParams {
        address token;
        address depositor;
        bytes32 transferSpecHash;
        uint32 destinationDomain;
        bytes32 recipient;
        address authorizer;
        uint256 value;
        uint256 fee;
        uint256 fromAvailable;
        uint256 fromWithdrawing;
    }

    struct ExpectedBalances {
        uint256 depositorExternalUsdc;
        uint256 depositorAvailable;
        uint256 depositorWithdrawing;
        uint256 feeRecipientExternalUsdc;
        uint256 walletExternalUsdc;
        uint256 usdcTotalSupply;
    }

    FiatTokenV2_2 private usdc;

    BurnIntent private baseIntent;

    GatewayWallet private wallet;

    function setUp() public {
        domain = ForkTestUtils.forkVars().domain;
        usdc = FiatTokenV2_2(ForkTestUtils.forkVars().usdc);
        wallet = deployWalletOnly(owner, domain);

        (depositor, depositorKey) = makeAddrAndKey("depositor");
        (depositor2, depositor2Key) = makeAddrAndKey("depositor2");
        (underFundedDepositor, underFundedDepositorKey) = makeAddrAndKey("underFundedDepositor");
        (delegate, delegateKey) = makeAddrAndKey("delegate");
        (burnSigner, burnSignerKey) = makeAddrAndKey("burnSigner");

        vm.startPrank(owner);
        {
            wallet.addSupportedToken(address(usdc));
            wallet.addSupportedToken(otherToken);
            wallet.updateDenylister(owner);
            wallet.addBurnSigner(burnSigner);
            wallet.updateFeeRecipient(feeRecipient);
        }
        vm.stopPrank();

        // Setup wallet as USDC burner
        address masterMinterAddr = usdc.masterMinter();
        if (masterMinterAddr.code.length > 0) {
            MasterMinter masterMinter = MasterMinter(masterMinterAddr);
            address masterMinterOwner = masterMinter.owner();
            vm.startPrank(masterMinterOwner);
            masterMinter.configureController(masterMinterOwner, address(wallet));
            masterMinter.configureMinter(0); // zero allowance, burn only
            vm.stopPrank();
        } else {
            // On testnet MasterMinter can be an EOA
            vm.startPrank(masterMinterAddr);
            usdc.configureMinter(address(wallet), 0); // zero allowance, burn only
            vm.stopPrank();
        }

        // Setup initial depositor balance
        deal(address(usdc), depositor, depositorInitialBalance, true);
        vm.startPrank(depositor);
        {
            usdc.approve(address(wallet), type(uint256).max);
            wallet.deposit(address(usdc), depositorInitialBalance);
        }
        vm.stopPrank();

        baseIntent = BurnIntent({
            maxBlockHeight: block.number + defaultMaxBlockHeightOffset,
            maxFee: defaultMaxFee,
            spec: TransferSpec({
                version: TRANSFER_SPEC_VERSION,
                sourceDomain: domain,
                destinationDomain: domain + 1, // A different destination domain
                sourceContract: AddressLib._addressToBytes32(address(wallet)),
                destinationContract: AddressLib._addressToBytes32(destinationContract),
                sourceToken: AddressLib._addressToBytes32(address(usdc)),
                destinationToken: AddressLib._addressToBytes32(destinationToken),
                sourceDepositor: AddressLib._addressToBytes32(depositor),
                destinationRecipient: AddressLib._addressToBytes32(recipient),
                sourceSigner: AddressLib._addressToBytes32(depositor),
                destinationCaller: bytes32(0),
                value: depositorInitialBalance / 2,
                salt: keccak256("salt"),
                hookData: HOOK_DATA
            })
        });
    }

    function _emptyArgs()
        internal
        pure
        returns (bytes[] memory intents, bytes[] memory signatures, uint256[][] memory fees)
    {
        intents = new bytes[](0);
        signatures = new bytes[](0);
        fees = new uint256[][](0);
    }

    function _randomArgs()
        internal
        pure
        returns (bytes[] memory intents, bytes[] memory signatures, uint256[][] memory fees)
    {
        intents = new bytes[](3);
        intents[0] = hex"abcdef";
        intents[1] = hex"123456";
        intents[2] = hex"987654";
        signatures = new bytes[](3);
        signatures[0] = hex"aaaaaa";
        signatures[1] = hex"bbbbbb";
        signatures[2] = hex"cccccc";
        fees = new uint256[][](3);
        fees[0] = new uint256[](2);
        fees[0][0] = 1;
        fees[0][1] = 2;
        fees[1] = new uint256[](1);
        fees[1][0] = 3;
        fees[2] = new uint256[](1);
        fees[2][0] = 4;
    }

    function _callGatewayBurnSignedBy(
        bytes[] memory intents,
        bytes[] memory signatures,
        uint256[][] memory fees,
        uint256 signerKey
    ) internal {
        bytes memory burnerSignature = _signBurnIntents(intents, signatures, fees, signerKey);

        // Call gatewayBurn with the arguments and signature
        wallet.gatewayBurn(abi.encode(intents, signatures, fees), burnerSignature);
    }

    function _signIntentOrIntentSet(bytes memory intentOrIntentSet, uint256 signerKey)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            wallet.domainSeparator(), BurnIntentLib.getTypedDataHash(intentOrIntentSet)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _expectBurnEvent(ExpectedBurnEventParams memory params) internal {
        vm.expectEmit(true, true, true, true);
        emit Burns.GatewayBurned(
            params.token,
            params.depositor,
            params.transferSpecHash,
            params.destinationDomain,
            params.recipient,
            params.authorizer,
            params.value,
            params.fee,
            params.fromAvailable,
            params.fromWithdrawing
        );
    }

    // ===== Entry Checks / Modifier Tests =====

    function test_gatewayBurn_revertIfPaused() public {
        vm.startPrank(owner);
        wallet.pause();
        vm.stopPrank();

        (bytes[] memory intents, bytes[] memory signatures, uint256[][] memory fees) = _emptyArgs();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        wallet.gatewayBurn(abi.encode(intents, signatures, fees), new bytes(0));
    }

    // ===== BurnSigner Signature Tests =====

    function test_gatewayBurn_randomArgs_wrongSigner() public {
        (bytes[] memory intents, bytes[] memory signatures, uint256[][] memory fees) = _randomArgs();
        (, uint256 wrongSignerKey) = makeAddrAndKey("wrongSigner");
        vm.expectRevert(Burns.InvalidBurnSigner.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, wrongSignerKey);
    }

    function test_gatewayBurn_randomArgs_wrongSignatureLength() public {
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 2));
        wallet.gatewayBurn(new bytes(0), hex"aaaa");
    }

    // ===== Intent Structural Validation Tests =====

    function test_gatewayBurn_revertIfNoIntents() public {
        (bytes[] memory intents, bytes[] memory signatures, uint256[][] memory fees) = _emptyArgs();
        vm.expectRevert(Burns.MustHaveAtLeastOneBurnIntent.selector);
        wallet.gatewayBurn(
            abi.encode(intents, signatures, fees), _signBurnIntents(intents, signatures, fees, burnSignerKey)
        );
    }

    function test_gatewayBurn_revertIfIntentSetIsEmpty() public {
        BurnIntentSet memory intentSet = BurnIntentSet({intents: new BurnIntent[](0)});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = new bytes(0);
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](0);
        vm.expectRevert(Burns.MustHaveAtLeastOneBurnIntent.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfFeesLengthMismatch() public {
        BurnIntent[] memory unencodedIndents = new BurnIntent[](1);
        unencodedIndents[0] = baseIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIndents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = new bytes(0);
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](0); // empty, but should have length 1 to match intents and signatures
        vm.expectRevert(Burns.MismatchedBurn.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfInputLengthsMismatched() public {
        bytes[] memory intents = new bytes[](2);
        bytes[] memory signatures = new bytes[](1);
        uint256[][] memory fees = new uint256[][](2);
        bytes memory burnerSignature = _signBurnIntents(intents, signatures, fees, burnSignerKey);

        vm.expectRevert(Burns.MismatchedBurn.selector);
        wallet.gatewayBurn(abi.encode(intents, signatures, fees), burnerSignature);
    }

    // ===== Intent Content Validation Tests =====

    function test_gatewayBurn_revertIfZeroValueIntent() public {
        baseIntent.spec.value = 0;
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(baseIntent);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, depositorKey);
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(Burns.IntentValueMustBePositiveAtIndex.selector, 0));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfZeroValueIntentSet() public {
        BurnIntent memory zeroValueIntent = baseIntent;
        zeroValueIntent.spec.value = 0;

        BurnIntent[] memory unencodedIndents = new BurnIntent[](2);
        unencodedIndents[0] = baseIntent;
        unencodedIndents[1] = zeroValueIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIndents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        // Prepare arguments for gatewayBurn
        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Burns.IntentValueMustBePositiveAtIndex.selector, 1));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfExpiredIntent() public {
        // Set maxBlockHeight to a past block
        baseIntent.maxBlockHeight = block.number - 1;
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(baseIntent);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);

        vm.expectRevert(
            abi.encodeWithSelector(Burns.IntentExpiredAtIndex.selector, 0, baseIntent.maxBlockHeight, block.number)
        );
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfExpiredIntentSet() public {
        BurnIntent memory expiredIntent = baseIntent;
        expiredIntent.maxBlockHeight = block.number - 1;

        BurnIntent[] memory unencodedIndents = new BurnIntent[](2);
        unencodedIndents[0] = baseIntent;
        unencodedIndents[1] = expiredIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIndents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(
            abi.encodeWithSelector(Burns.IntentExpiredAtIndex.selector, 1, expiredIntent.maxBlockHeight, block.number)
        );
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfFeeTooHighIntent() public {
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(baseIntent);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        uint256 highFee = baseIntent.maxFee + 1;
        fees[0][0] = highFee;

        vm.expectRevert(abi.encodeWithSelector(Burns.BurnFeeTooHighAtIndex.selector, 0, baseIntent.maxFee, highFee));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfFeeTooHighIntentSet() public {
        BurnIntent memory highFeeIntent = baseIntent;

        BurnIntent[] memory unencodedIndents = new BurnIntent[](2);
        unencodedIndents[0] = baseIntent;
        unencodedIndents[1] = highFeeIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIndents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);
        fees[0][0] = highFeeIntent.maxFee;
        uint256 highFee = highFeeIntent.maxFee + 1;
        fees[0][1] = highFee;

        vm.expectRevert(abi.encodeWithSelector(Burns.BurnFeeTooHighAtIndex.selector, 1, highFeeIntent.maxFee, highFee));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfInvalidSourceContractIntent() public {
        BurnIntent memory invalidSourceContractIntent = baseIntent;
        address invalidSourceContract = makeAddr("invalidSourceContract");
        invalidSourceContractIntent.spec.sourceContract = AddressLib._addressToBytes32(invalidSourceContract);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(invalidSourceContractIntent);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Burns.InvalidIntentSourceContractAtIndex.selector, 0, invalidSourceContract, address(wallet)
            )
        );
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfInvalidSourceContractIntentSet() public {
        BurnIntent memory invalidSourceContractIntent = baseIntent;
        address invalidSourceContract = makeAddr("invalidSourceContract");
        invalidSourceContractIntent.spec.sourceContract = AddressLib._addressToBytes32(invalidSourceContract);

        BurnIntent[] memory unencodedIntents = new BurnIntent[](2);
        unencodedIntents[0] = baseIntent;
        unencodedIntents[1] = invalidSourceContractIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIntents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(
            abi.encodeWithSelector(
                Burns.InvalidIntentSourceContractAtIndex.selector, 1, invalidSourceContract, address(wallet)
            )
        );
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfUnsupportedTokenIntent() public {
        address unsupportedToken = makeAddr("unsupportedToken");
        baseIntent.spec.sourceToken = AddressLib._addressToBytes32(unsupportedToken);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(baseIntent);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(Burns.UnsupportedTokenAtIndex.selector, 0, unsupportedToken));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfUnsupportedTokenIntentSet() public {
        BurnIntent memory unsupportedTokenIntent = baseIntent;
        address unsupportedToken = makeAddr("unsupportedToken");
        unsupportedTokenIntent.spec.sourceToken = AddressLib._addressToBytes32(unsupportedToken);

        BurnIntent[] memory unencodedIntents = new BurnIntent[](2);
        unencodedIntents[0] = baseIntent;
        unencodedIntents[1] = unsupportedTokenIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIntents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Burns.UnsupportedTokenAtIndex.selector, 1, unsupportedToken));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfWasNeverAuthorizedForBalanceIntent() public {
        BurnIntent memory neverAuthorizedIntent = baseIntent;
        (address neverAuthorizedSigner, uint256 neverAuthorizedSignerKey) = makeAddrAndKey("neverAuthorizedSigner");
        neverAuthorizedIntent.spec.sourceSigner = AddressLib._addressToBytes32(neverAuthorizedSigner);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(neverAuthorizedIntent);
        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;

        // Sign with a wrong key
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, neverAuthorizedSignerKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);

        vm.expectRevert(Delegation.NotAuthorized.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfWasNeverAuthorizedForBalanceIntentSet() public {
        BurnIntent[] memory unencodedIntents = new BurnIntent[](2);
        (address neverAuthorizedSigner, uint256 neverAuthorizedSignerKey) = makeAddrAndKey("neverAuthorizedSigner");
        unencodedIntents[0] = baseIntent;
        unencodedIntents[0].spec.sourceSigner = AddressLib._addressToBytes32(neverAuthorizedSigner);
        unencodedIntents[1] = baseIntent;
        unencodedIntents[1].spec.sourceSigner = AddressLib._addressToBytes32(neverAuthorizedSigner);
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIntents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, neverAuthorizedSignerKey);

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(Delegation.NotAuthorized.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfInvalidSourceSignerIntent() public {
        BurnIntent memory mismatchedSignerIntent = baseIntent;
        address anotherAddress = makeAddr("anotherAddress");
        mismatchedSignerIntent.spec.sourceSigner = AddressLib._addressToBytes32(anotherAddress);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(mismatchedSignerIntent);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntent, depositorKey); // Signed by depositor but sourceSigner is anotherAddress

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);

        vm.expectRevert(
            abi.encodeWithSelector(Burns.InvalidIntentSourceSignerAtIndex.selector, 0, anotherAddress, depositor)
        );
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfInvalidSourceSignerIntentSet() public {
        BurnIntent memory intent1 = baseIntent;
        BurnIntent memory intent2MismatchedSigner = baseIntent;
        address anotherAddress = makeAddr("anotherAddress");
        intent2MismatchedSigner.spec.sourceSigner = AddressLib._addressToBytes32(anotherAddress);

        BurnIntent[] memory unencodedIntents = new BurnIntent[](2);
        unencodedIntents[0] = intent1;
        unencodedIntents[1] = intent2MismatchedSigner;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIntents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey); // Signed by depositor

        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(
            abi.encodeWithSelector(Burns.InvalidIntentSourceSignerAtIndex.selector, 1, anotherAddress, depositor)
        );
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    // ===== Burn Failure Scenarios =====

    function test_gatewayBurn_revertIfReplayed() public {
        BurnIntent memory intent = baseIntent;

        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);
        bytes memory signature = _signIntentOrIntentSet(encodedIntent, depositorKey);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = 0;

        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);

        // Replay the same intent
        bytes32 specHash = keccak256(TransferSpecLib.encodeTransferSpec(intent.spec));
        vm.expectRevert(abi.encodeWithSelector(TransferSpecHashes.TransferSpecHashUsed.selector, specHash));
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_revertIfNotAllSameToken() external {
        address notUsdc = makeAddr("notUsdc");
        vm.startPrank(owner);
        wallet.addSupportedToken(notUsdc);
        vm.stopPrank();

        BurnIntent memory nonUsdcIntent = baseIntent;
        nonUsdcIntent.spec.sourceToken = AddressLib._addressToBytes32(notUsdc);

        BurnIntent[] memory unencodedIntents = new BurnIntent[](2);
        unencodedIntents[0] = baseIntent;
        unencodedIntents[1] = nonUsdcIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIntents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);

        vm.expectRevert(Burns.NotAllSameToken.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_singleIntent_revertIfOtherSourceDomain() public {
        BurnIntent memory otherDomainIntent = baseIntent;
        otherDomainIntent.spec.sourceDomain = domain + 1; // A different domain

        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(otherDomainIntent);
        bytes memory signature = _signIntentOrIntentSet(encodedIntent, depositorKey);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = baseIntent.maxFee;

        vm.expectRevert(Burns.NoRelevantBurnIntents.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    function test_gatewayBurn_singleIntentSet_revertIfOtherSourceDomain() public {
        BurnIntent memory otherDomainIntent = baseIntent;
        otherDomainIntent.spec.sourceDomain = domain + 1; // A different domain

        BurnIntent[] memory unencodedIntents = new BurnIntent[](2);
        unencodedIntents[0] = otherDomainIntent;
        unencodedIntents[1] = otherDomainIntent;
        BurnIntentSet memory intentSet = BurnIntentSet({intents: unencodedIntents});
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(intentSet);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntentSet;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signIntentOrIntentSet(encodedIntentSet, depositorKey);
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](2);
        fees[0][0] = baseIntent.maxFee;
        fees[0][1] = baseIntent.maxFee;

        vm.expectRevert(Burns.NoRelevantBurnIntents.selector);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);
    }

    // ===== Insufficient Balance Tests =====

    struct IntentSetInsufficientBalanceTestData {
        uint256 initialDeposit;
        uint256 depositorKey;
        address depositorAddr;
        uint256 fee1;
        uint256 fee2;
        uint256 value1;
        uint256 value2;
        BurnIntent intent1;
        BurnIntent intent2;
        BurnIntent[] intentsForSet;
        BurnIntentSet intentSet;
        bytes encodedIntentSet;
        bytes signature;
        bytes[] intents;
        bytes[] signatures;
        uint256[][] fees;
        uint256 initialTotalSupply;
        uint256 initialWalletBalance;
        uint256 initialFeeRecipientBalance;
        ExpectedBalances initialBalances;
        ExpectedBalances finalBalances;
        ExpectedBurnEventParams eventParams1;
        uint256 insufficientEventValueNeeded;
        uint256 insufficientEventBalanceAvailable;
        uint256 insufficientEventWithdrawingAvailable;
        ExpectedBurnEventParams eventParams2;
    }

    function test_gatewayBurn_singleIntent_insufficientBalanceForBurnValue() public {
        // Setup the under funded depositor
        deal(address(usdc), underFundedDepositor, depositorInitialBalance, true); // Fund externally with initial $5000
        vm.startPrank(underFundedDepositor);
        usdc.approve(address(wallet), type(uint256).max);
        wallet.deposit(address(usdc), depositorInitialBalance / 4); // Deposit $1250 (1/4 of initial)
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.value = 2500 * 10 ** 6; // $2500
        intent.spec.sourceDepositor = AddressLib._addressToBytes32(underFundedDepositor);
        intent.spec.sourceSigner = AddressLib._addressToBytes32(underFundedDepositor);
        uint256 fee = defaultMaxFee / 2; // $0.50

        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);
        bytes memory signature = _signIntentOrIntentSet(encodedIntent, underFundedDepositorKey);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = fee;

        // Assert initial state
        uint256 initialTotalSupply = usdc.totalSupply();
        ExpectedBalances memory initialExpectedBalances = ExpectedBalances({
            depositorExternalUsdc: depositorInitialBalance * 3 / 4, // $3750 external
            depositorAvailable: depositorInitialBalance / 4, // $1250 available
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance + depositorInitialBalance / 4, // $5000 (original depositor) + $1250 (underFundedDepositor) = $6250 total in wallet
            usdcTotalSupply: initialTotalSupply
        });
        _assertBalances("Initial State", underFundedDepositor, feeRecipient, initialExpectedBalances);

        vm.expectEmit(true, true, true, true);
        emit GatewayCommon.InsufficientBalance(
            address(usdc),
            underFundedDepositor,
            intent.spec.value + fee, // Total needed: $2500 + $0.50 = $2500.50
            depositorInitialBalance / 4, // Balance available: $1250
            0 // Withdrawing available: $0
        );

        ExpectedBurnEventParams memory expectedParams;
        expectedParams.token = address(usdc);
        expectedParams.depositor = underFundedDepositor;
        expectedParams.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(intent.spec));
        expectedParams.destinationDomain = intent.spec.destinationDomain;
        expectedParams.recipient = intent.spec.destinationRecipient;
        expectedParams.authorizer = underFundedDepositor;
        expectedParams.value = depositorInitialBalance / 4; // fromAvailable - fee
        expectedParams.fee = 0; // Actual fee charged: $0 (waived)
        expectedParams.fromAvailable = depositorInitialBalance / 4; // Actual amount deducted from available: $1250
        expectedParams.fromWithdrawing = 0;
        _expectBurnEvent(expectedParams);

        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);

        // Assert final state
        ExpectedBalances memory finalExpectedBalances = ExpectedBalances({
            depositorExternalUsdc: depositorInitialBalance * 3 / 4, // $3750
            depositorAvailable: 0, // Available becomes $0
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0, // Fee recipient gets $0
            walletExternalUsdc: depositorInitialBalance, // Wallet balance: $6250 - $1250 = $5000
            usdcTotalSupply: initialTotalSupply - depositorInitialBalance / 4 // Total supply reduced by $1250
        });
        _assertBalances("Final State", underFundedDepositor, feeRecipient, finalExpectedBalances);
    }

    /// Tests gatewayBurn with an intent set containing two intents for the same depositor.
    /// The first intent succeeds, but depletes the balance such that the second intent
    /// triggers the InsufficientBalance event and results in a partial burn value and zero fee.
    function test_gatewayBurn_singleIntentSet_secondIntentHasInsufficientBalanceForBurnValue() public {
        IntentSetInsufficientBalanceTestData memory testData;

        (testData.depositorAddr, testData.depositorKey) = makeAddrAndKey("partiallyFundedDepositor");
        testData.initialDeposit = 1000 * 10 ** 6; // $1000.00
        testData.value1 = 600 * 10 ** 6; // $600.00
        testData.fee1 = defaultMaxFee / 5; // $0.20
        testData.value2 = 500 * 10 ** 6; // $500.00 (Needs $500.10 total)
        testData.fee2 = defaultMaxFee / 10; // $0.10

        // Setup the depositor's balance
        deal(address(usdc), testData.depositorAddr, testData.initialDeposit, true);
        vm.startPrank(testData.depositorAddr);
        usdc.approve(address(wallet), type(uint256).max);
        wallet.deposit(address(usdc), testData.initialDeposit);
        vm.stopPrank();

        // Intent 1 (should succeed)
        testData.intent1 = baseIntent;
        testData.intent1.spec.sourceDepositor = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent1.spec.sourceSigner = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent1.spec.value = testData.value1;
        testData.intent1.maxFee = defaultMaxFee;

        // Intent 2 (should have insufficient funds after Intent 1)
        testData.intent2 = baseIntent;
        testData.intent2.spec.sourceDepositor = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent2.spec.sourceSigner = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent2.spec.value = testData.value2;
        testData.intent2.maxFee = defaultMaxFee;

        testData.intentsForSet = new BurnIntent[](2);
        testData.intentsForSet[0] = testData.intent1;
        testData.intentsForSet[1] = testData.intent2;
        testData.intentSet = BurnIntentSet({intents: testData.intentsForSet});
        testData.encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(testData.intentSet);

        testData.signature = _signIntentOrIntentSet(testData.encodedIntentSet, testData.depositorKey);

        testData.intents = new bytes[](1);
        testData.intents[0] = testData.encodedIntentSet;
        testData.signatures = new bytes[](1);
        testData.signatures[0] = testData.signature;
        testData.fees = new uint256[][](1);
        testData.fees[0] = new uint256[](2);
        testData.fees[0][0] = testData.fee1;
        testData.fees[0][1] = testData.fee2;

        testData.initialTotalSupply = usdc.totalSupply();
        testData.initialWalletBalance = usdc.balanceOf(address(wallet));
        testData.initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);

        uint256 balanceAfterIntent1 = testData.initialDeposit - (testData.value1 + testData.fee1); // $1000 - ($600 + $0.20) = $399.80
        uint256 neededForIntent2 = testData.value2 + testData.fee2; // $500 + $0.10 = $500.10
        uint256 deductedForIntent2 = balanceAfterIntent1; // $399.80 (since $399.80 < $500.10)
        uint256 actualFeeIntent2 = 0; // Since deductedForIntent2 ($399.80) <= value2 ($500)
        uint256 actualValueBurnedIntent2 = deductedForIntent2 - actualFeeIntent2; // $399.80 - $0 = $399.80

        // Initial Balances
        testData.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0, // Depositor transferred all funds in
            depositorAvailable: testData.initialDeposit,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: testData.initialFeeRecipientBalance, // May have balance from other tests
            walletExternalUsdc: testData.initialWalletBalance, // Wallet holds initial depositor + this new one
            usdcTotalSupply: testData.initialTotalSupply
        });

        // Final Balances
        uint256 finalTotalValueBurned = testData.value1 + actualValueBurnedIntent2; // $600 + $399.80 = $999.80
        uint256 finalTotalFeeCharged = testData.fee1 + actualFeeIntent2; // $0.20 + $0 = $0.20
        uint256 finalTotalDeducted = (testData.value1 + testData.fee1) + deductedForIntent2; // $600.20 + $399.80 = $1000.00

        testData.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0, // Fully depleted
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: testData.initialFeeRecipientBalance + finalTotalFeeCharged, // Initial + $0.20
            walletExternalUsdc: testData.initialWalletBalance - finalTotalDeducted, // Initial wallet bal - $1000
            usdcTotalSupply: testData.initialTotalSupply - finalTotalValueBurned // Initial supply - $999.80
        });

        // Event 1 (Intent 1)
        testData.eventParams1 = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: testData.depositorAddr,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(testData.intent1.spec)),
            destinationDomain: testData.intent1.spec.destinationDomain,
            recipient: testData.intent1.spec.destinationRecipient,
            authorizer: testData.depositorAddr,
            value: testData.value1, // fromAvailable - fee
            fee: testData.fee1,
            fromAvailable: testData.value1 + testData.fee1,
            fromWithdrawing: 0
        });

        // Insufficient Balance Event (Intent 2)
        testData.insufficientEventValueNeeded = neededForIntent2; // $500.10
        testData.insufficientEventBalanceAvailable = balanceAfterIntent1; // $399.80
        testData.insufficientEventWithdrawingAvailable = 0;

        // Event 2 (Intent 2)
        testData.eventParams2 = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: testData.depositorAddr,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(testData.intent2.spec)),
            destinationDomain: testData.intent2.spec.destinationDomain,
            recipient: testData.intent2.spec.destinationRecipient,
            authorizer: testData.depositorAddr,
            value: deductedForIntent2 - actualFeeIntent2, // fromAvailable - fee
            fee: actualFeeIntent2, // Actual fee $0
            fromAvailable: deductedForIntent2, // Amount actually deducted $399.80
            fromWithdrawing: 0
        });

        // Assert initial state
        _assertBalances(
            "Initial State (IntentSet Insufficient)", testData.depositorAddr, feeRecipient, testData.initialBalances
        );

        _expectBurnEvent(testData.eventParams1); // Event for successful intent1
        vm.expectEmit(true, true, true, true);
        emit GatewayCommon.InsufficientBalance(
            address(usdc),
            testData.depositorAddr,
            testData.insufficientEventValueNeeded,
            testData.insufficientEventBalanceAvailable,
            testData.insufficientEventWithdrawingAvailable
        );
        _expectBurnEvent(testData.eventParams2); // Event for partially successful intent2

        _callGatewayBurnSignedBy(testData.intents, testData.signatures, testData.fees, burnSignerKey);

        // Assert final state
        _assertBalances(
            "Final State (IntentSet Insufficient)", testData.depositorAddr, feeRecipient, testData.finalBalances
        );
    }

    function test_gatewayBurn_singleIntent_insufficientBalanceForBurnFee() public {
        uint256 fee = defaultMaxFee / 2; // $0.50

        // Setup the under funded depositor
        deal(address(usdc), underFundedDepositor, depositorInitialBalance, true); // Fund externally with initial $5000
        vm.startPrank(underFundedDepositor);
        usdc.approve(address(wallet), type(uint256).max);
        wallet.deposit(address(usdc), depositorInitialBalance / 4 + fee / 2); // Deposit $1250 (1/4 of initial) + $0.25 (half of fee)
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.value = depositorInitialBalance / 4; // $1250
        intent.spec.sourceDepositor = AddressLib._addressToBytes32(underFundedDepositor);
        intent.spec.sourceSigner = AddressLib._addressToBytes32(underFundedDepositor);
        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(intent);
        bytes memory signature = _signIntentOrIntentSet(encodedIntent, underFundedDepositorKey);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = fee;

        // Assert initial state
        uint256 initialTotalSupply = usdc.totalSupply();
        ExpectedBalances memory initialExpectedBalances = ExpectedBalances({
            depositorExternalUsdc: depositorInitialBalance * 3 / 4 - fee / 2, // $3750 external - $0.25 (half of fee)
            depositorAvailable: depositorInitialBalance / 4 + fee / 2, // $1250 available + $0.25 (half of fee)
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance + depositorInitialBalance / 4 + fee / 2, // $5000 (original depositor) + $1250 (underFundedDepositor) + $0.25 (half of fee) = $6250.25 total in wallet
            usdcTotalSupply: initialTotalSupply
        });
        _assertBalances("Initial State", underFundedDepositor, feeRecipient, initialExpectedBalances);

        vm.expectEmit(true, true, true, true);
        emit GatewayCommon.InsufficientBalance(
            address(usdc),
            underFundedDepositor,
            intent.spec.value + fee, // Total needed: $1250 + $0.50 = $1250.50
            depositorInitialBalance / 4 + fee / 2, // Available available: $1250 + $0.25 (half of fee)
            0 // Withdrawing available: $0
        );

        ExpectedBurnEventParams memory expectedParams;
        expectedParams.token = address(usdc);
        expectedParams.depositor = underFundedDepositor;
        expectedParams.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(intent.spec));
        expectedParams.destinationDomain = intent.spec.destinationDomain;
        expectedParams.recipient = intent.spec.destinationRecipient;
        expectedParams.authorizer = underFundedDepositor;
        expectedParams.fee = fee / 2; // Actual fee charged: $0.25 (half of fee)
        expectedParams.fromAvailable = depositorInitialBalance / 4 + fee / 2; // Actual amount deducted from available: $1250.25
        expectedParams.value = expectedParams.fromAvailable - expectedParams.fee;
        expectedParams.fromWithdrawing = 0;
        _expectBurnEvent(expectedParams);

        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);

        // Assert final state
        ExpectedBalances memory finalExpectedBalances = ExpectedBalances({
            depositorExternalUsdc: depositorInitialBalance * 3 / 4 - fee / 2, // $3750 external - $0.25 (half of fee)
            depositorAvailable: 0, // Available becomes $0
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: fee / 2, // Fee recipient gets $0.25 (half of fee)
            walletExternalUsdc: depositorInitialBalance, // Wallet balance: $6250 - $1250 = $5000
            usdcTotalSupply: initialTotalSupply - depositorInitialBalance / 4 // Total supply reduced by $1250
        });
        _assertBalances("Final State", underFundedDepositor, feeRecipient, finalExpectedBalances);
    }

    /// Tests gatewayBurn with an intent set containing two intents for the same depositor.
    /// The first intent succeeds, but depletes the balance such that the second intent
    /// can cover its value but only a portion of its fee.
    function test_gatewayBurn_singleIntentSet_secondIntentPartialFee() public {
        IntentSetInsufficientBalanceTestData memory testData;

        (testData.depositorAddr, testData.depositorKey) = makeAddrAndKey("partialFeeDepositor");
        testData.initialDeposit = 1000 * 10 ** 6; // $1000.00
        testData.value1 = 800 * 10 ** 6; // $800.00
        testData.fee1 = defaultMaxFee / 10; // $0.10
        testData.value2 = 1995 * 10 ** 5; // $199.50
        testData.fee2 = defaultMaxFee / 2; // $0.50 (Needs $199.50 + $0.50 = $200.00 total)

        // Setup the depositor's balance
        deal(address(usdc), testData.depositorAddr, testData.initialDeposit, true);
        vm.startPrank(testData.depositorAddr);
        usdc.approve(address(wallet), type(uint256).max);
        wallet.deposit(address(usdc), testData.initialDeposit);
        vm.stopPrank();

        // Intent 1 (designed to succeed)
        testData.intent1 = baseIntent;
        testData.intent1.spec.sourceDepositor = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent1.spec.sourceSigner = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent1.spec.value = testData.value1;
        testData.intent1.maxFee = defaultMaxFee;

        // Intent 2 (designed to have insufficient funds for full fee after Intent 1)
        testData.intent2 = baseIntent;
        testData.intent2.spec.sourceDepositor = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent2.spec.sourceSigner = AddressLib._addressToBytes32(testData.depositorAddr);
        testData.intent2.spec.value = testData.value2;
        testData.intent2.maxFee = defaultMaxFee;

        testData.intentsForSet = new BurnIntent[](2);
        testData.intentsForSet[0] = testData.intent1;
        testData.intentsForSet[1] = testData.intent2;
        testData.intentSet = BurnIntentSet({intents: testData.intentsForSet});
        testData.encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(testData.intentSet);

        testData.signature = _signIntentOrIntentSet(testData.encodedIntentSet, testData.depositorKey);

        testData.intents = new bytes[](1);
        testData.intents[0] = testData.encodedIntentSet;
        testData.signatures = new bytes[](1);
        testData.signatures[0] = testData.signature;
        testData.fees = new uint256[][](1);
        testData.fees[0] = new uint256[](2);
        testData.fees[0][0] = testData.fee1;
        testData.fees[0][1] = testData.fee2;

        testData.initialTotalSupply = usdc.totalSupply();
        testData.initialWalletBalance = usdc.balanceOf(address(wallet));
        testData.initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);

        uint256 balanceAfterIntent1 = testData.initialDeposit - (testData.value1 + testData.fee1); // $1000 - ($800 + $0.10) = $199.90
        uint256 neededForIntent2 = testData.value2 + testData.fee2; // $199.50 + $0.50 = $200.00
        uint256 deductedForIntent2 = balanceAfterIntent1; // $199.90 (since $199.90 < $200.00)
        // Since deductedAmount ($199.90) > value2 ($199.50), potential fee is deductedAmount - value2
        uint256 potentialFeeIntent2 = deductedForIntent2 - testData.value2; // $199.90 - $199.50 = $0.40
        uint256 actualFeeIntent2 = potentialFeeIntent2 < testData.fee2 ? potentialFeeIntent2 : testData.fee2; // min($0.40, $0.50) = $0.40
        uint256 actualValueBurnedIntent2 = deductedForIntent2 - actualFeeIntent2; // $199.90 - $0.40 = $199.50

        // Initial Balances
        testData.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: testData.initialDeposit,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: testData.initialFeeRecipientBalance,
            walletExternalUsdc: testData.initialWalletBalance,
            usdcTotalSupply: testData.initialTotalSupply
        });

        // Final Balances
        uint256 finalTotalValueBurned = testData.value1 + actualValueBurnedIntent2; // $800 + $199.50 = $999.50
        uint256 finalTotalFeeCharged = testData.fee1 + actualFeeIntent2; // $0.10 + $0.40 = $0.50
        uint256 finalTotalDeducted = (testData.value1 + testData.fee1) + deductedForIntent2; // $800.10 + $199.90 = $1000.00

        testData.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0, // Fully depleted
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: testData.initialFeeRecipientBalance + finalTotalFeeCharged, // Initial + $0.50
            walletExternalUsdc: testData.initialWalletBalance - finalTotalDeducted, // Initial wallet bal - $1000
            usdcTotalSupply: testData.initialTotalSupply - finalTotalValueBurned // Initial supply - $999.50
        });

        // Event 1 (Intent 1)
        testData.eventParams1 = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: testData.depositorAddr,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(testData.intent1.spec)),
            destinationDomain: testData.intent1.spec.destinationDomain,
            recipient: testData.intent1.spec.destinationRecipient,
            authorizer: testData.depositorAddr,
            value: testData.value1,
            fee: testData.fee1,
            fromAvailable: testData.value1 + testData.fee1,
            fromWithdrawing: 0
        });

        // Insufficient Balance Event (Intent 2)
        testData.insufficientEventValueNeeded = neededForIntent2; // $200.00
        testData.insufficientEventBalanceAvailable = balanceAfterIntent1; // $199.90
        testData.insufficientEventWithdrawingAvailable = 0;

        // Event 2 (Intent 2)
        testData.eventParams2 = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: testData.depositorAddr,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(testData.intent2.spec)),
            destinationDomain: testData.intent2.spec.destinationDomain,
            recipient: testData.intent2.spec.destinationRecipient,
            authorizer: testData.depositorAddr,
            value: deductedForIntent2 - actualFeeIntent2, // Requested value $199.50
            fee: actualFeeIntent2, // Actual fee $0.40
            fromAvailable: deductedForIntent2, // Amount actually deducted $199.90
            fromWithdrawing: 0
        });

        // Assert initial state
        _assertBalances(
            "Initial State (IntentSet Partial Fee)", testData.depositorAddr, feeRecipient, testData.initialBalances
        );

        _expectBurnEvent(testData.eventParams1); // Event for successful intent1
        vm.expectEmit(true, true, true, true);
        emit GatewayCommon.InsufficientBalance(
            address(usdc),
            testData.depositorAddr,
            testData.insufficientEventValueNeeded,
            testData.insufficientEventBalanceAvailable,
            testData.insufficientEventWithdrawingAvailable
        );
        _expectBurnEvent(testData.eventParams2); // Event for successful value burn, partial fee

        _callGatewayBurnSignedBy(testData.intents, testData.signatures, testData.fees, burnSignerKey);

        // Assert final state
        _assertBalances(
            "Final State (IntentSet Partial Fee)", testData.depositorAddr, feeRecipient, testData.finalBalances
        );
    }

    // ===== Burn Success Scenarios - Single Intent, Single Intent Set =====
    //
    // Test Matrix for Successful Burns:
    //
    // This section tests successful `gatewayBurn` calls by varying several parameters:
    // 1. Input Structure: How intents are grouped (single vs. multiple sets, single vs. multiple intents per set).
    // 2. Domain Relevance: Whether intents are for the current domain (processed) or another (skipped).
    // 3. Balance Source: Where funds are drawn from (available only, withdrawing only, or both).
    // 4. Intent Signer: Who signed the intent (the depositor, an authorized delegate, or a now revoked delegate).

    struct SingleBurnTestConfig {
        string contextSuffix; // Short description (e.g., "(Available, Depositor)")
        BurnIntent intent; // The specific intent to test
        uint256 fee; // The fee for this specific burn
        uint256 signerKey; // Private key of the authorizer (depositor or delegate)
        ExpectedBalances initialBalances; // Expected state before the burn
        ExpectedBalances finalBalances; // Expected state after the burn
        ExpectedBurnEventParams eventParams; // Expected event details
    }

    function _assertBalances(
        string memory context, // e.g., "Initial State", "After Burn"
        address depositorAddr,
        address feeRecipientAddr,
        ExpectedBalances memory expected
    ) internal view {
        // Fetch actual balances
        uint256 actualDepositorExternalUsdc = usdc.balanceOf(depositorAddr);
        uint256 actualDepositorAvailable = wallet.availableBalance(address(usdc), depositorAddr);
        uint256 actualDepositorWithdrawing = wallet.withdrawingBalance(address(usdc), depositorAddr);
        uint256 actualFeeRecipientExternalUsdc = usdc.balanceOf(feeRecipientAddr);
        uint256 actualWalletExternalUsdc = usdc.balanceOf(address(wallet));
        uint256 actualUsdcTotalSupply = usdc.totalSupply();

        assertEq(
            actualDepositorExternalUsdc,
            expected.depositorExternalUsdc,
            string.concat(context, ": Depositor External USDC mismatch")
        );
        assertEq(
            actualDepositorAvailable,
            expected.depositorAvailable,
            string.concat(context, ": Depositor Available mismatch")
        );
        assertEq(
            actualDepositorWithdrawing,
            expected.depositorWithdrawing,
            string.concat(context, ": Depositor Withdrawing mismatch")
        );
        assertEq(
            actualFeeRecipientExternalUsdc,
            expected.feeRecipientExternalUsdc,
            string.concat(context, ": Fee Recipient External USDC mismatch")
        );
        assertEq(
            actualWalletExternalUsdc,
            expected.walletExternalUsdc,
            string.concat(context, ": Wallet External USDC mismatch")
        );
        assertEq(
            actualUsdcTotalSupply, expected.usdcTotalSupply, string.concat(context, ": USDC Total Supply mismatch")
        );
    }

    function _executeAndAssertSingleBurn(SingleBurnTestConfig memory config) internal {
        // Assert initial state
        _assertBalances(
            string.concat("Initial State ", config.contextSuffix),
            config.eventParams.depositor, // Get depositor from event params
            feeRecipient, // Global fee recipient
            config.initialBalances
        );

        bytes memory encodedIntent = BurnIntentLib.encodeBurnIntent(config.intent);
        bytes memory signature = _signIntentOrIntentSet(encodedIntent, config.signerKey);

        bytes[] memory intents = new bytes[](1);
        intents[0] = encodedIntent;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        uint256[][] memory fees = new uint256[][](1);
        fees[0] = new uint256[](1);
        fees[0][0] = config.fee;

        _expectBurnEvent(config.eventParams);
        _callGatewayBurnSignedBy(intents, signatures, fees, burnSignerKey);

        // Assert final state
        _assertBalances(
            string.concat("Final State ", config.contextSuffix),
            config.eventParams.depositor,
            feeRecipient,
            config.finalBalances
        );
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromAvailableBalance_depositorSigner() public {
        BurnIntent memory intent = baseIntent;
        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = depositorKey;
        address expectedAuthorizer = depositor;
        string memory contextSuffix = "(Available, Depositor)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance - expectedTotalDeducted,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: expectedTotalDeducted,
            fromWithdrawing: 0
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromAvailableBalance_delegateSigner() public {
        // Setup delegate
        vm.startPrank(depositor);
        wallet.addDelegate(address(usdc), delegate);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.sourceSigner = AddressLib._addressToBytes32(delegate);

        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = delegateKey; // Signed by delegate
        address expectedAuthorizer = delegate; // Authorizer is delegate
        string memory contextSuffix = "(Available, Delegate)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance - expectedTotalDeducted,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: expectedTotalDeducted,
            fromWithdrawing: 0
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromAvailableBalance_revokedDelegateSigner() public {
        // Setup and revoke delegate
        vm.startPrank(depositor);
        wallet.addDelegate(address(usdc), delegate);
        wallet.removeDelegate(address(usdc), delegate);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.sourceSigner = AddressLib._addressToBytes32(delegate);

        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = delegateKey; // Signed by delegate (before revocation)
        address expectedAuthorizer = delegate; // Authorizer is revoked delegate
        string memory contextSuffix = "(Available, Revoked Delegate)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance - expectedTotalDeducted,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: expectedTotalDeducted,
            fromWithdrawing: 0
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromWithdrawingBalance_depositorSigner() public {
        vm.startPrank(depositor);
        wallet.initiateWithdrawal(address(usdc), depositorInitialBalance);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = depositorKey;
        address expectedAuthorizer = depositor;
        string memory contextSuffix = "(Withdrawing, Depositor)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: depositorInitialBalance,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: depositorInitialBalance - expectedTotalDeducted,
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: 0,
            fromWithdrawing: expectedTotalDeducted
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromWithdrawingBalance_delegateSigner() public {
        // Move all depositor funds to withdrawing balance
        vm.startPrank(depositor);
        wallet.initiateWithdrawal(address(usdc), depositorInitialBalance);

        // Setup delegate
        wallet.addDelegate(address(usdc), delegate);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.sourceSigner = AddressLib._addressToBytes32(delegate);

        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = delegateKey; // Signed by delegate
        address expectedAuthorizer = delegate;
        string memory contextSuffix = "(Withdrawing, Delegate)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: depositorInitialBalance,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: depositorInitialBalance - expectedTotalDeducted,
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: 0,
            fromWithdrawing: expectedTotalDeducted
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromWithdrawingBalance_revokedDelegateSigner() public {
        vm.startPrank(depositor);
        wallet.initiateWithdrawal(address(usdc), depositorInitialBalance);
        wallet.addDelegate(address(usdc), delegate);
        wallet.removeDelegate(address(usdc), delegate);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.sourceSigner = AddressLib._addressToBytes32(delegate);

        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = delegateKey; // Signed by delegate
        address expectedAuthorizer = delegate;
        string memory contextSuffix = "(Withdrawing, Revoked Delegate)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: depositorInitialBalance,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: depositorInitialBalance - expectedTotalDeducted,
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: 0,
            fromWithdrawing: expectedTotalDeducted
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromBothBalances_depositorSigner() public {
        // Move some funds to withdrawing balance
        uint256 withdrawAmount = depositorInitialBalance * 3 / 4;
        uint256 remainingAvailable = depositorInitialBalance / 4;

        vm.startPrank(depositor);
        wallet.initiateWithdrawal(address(usdc), withdrawAmount);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = depositorKey;
        address expectedAuthorizer = depositor;
        string memory contextSuffix = "(Both, Depositor)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: remainingAvailable,
            depositorWithdrawing: withdrawAmount,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: withdrawAmount - (expectedTotalDeducted - remainingAvailable),
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: remainingAvailable,
            fromWithdrawing: expectedTotalDeducted - remainingAvailable
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromBothBalances_delegateSigner() public {
        // Move some funds to withdrawing balance
        uint256 withdrawAmount = depositorInitialBalance * 3 / 4;
        uint256 remainingAvailable = depositorInitialBalance - withdrawAmount;

        // Setup delegate
        vm.startPrank(depositor);
        wallet.initiateWithdrawal(address(usdc), withdrawAmount);
        wallet.addDelegate(address(usdc), delegate);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.sourceSigner = AddressLib._addressToBytes32(delegate);

        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = delegateKey; // Signed by delegate
        address expectedAuthorizer = delegate;
        string memory contextSuffix = "(Both, Delegate)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: remainingAvailable,
            depositorWithdrawing: withdrawAmount,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0, // Available used up
            depositorWithdrawing: withdrawAmount - (expectedTotalDeducted - remainingAvailable),
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: remainingAvailable,
            fromWithdrawing: expectedTotalDeducted - remainingAvailable
        });

        _executeAndAssertSingleBurn(config);
    }

    function test_gatewayBurn_singleIntent_currentDomain_fromBothBalances_revokedDelegateSigner() public {
        // Move some funds to withdrawing balance
        uint256 withdrawAmount = depositorInitialBalance * 3 / 4;
        uint256 remainingAvailable = depositorInitialBalance - withdrawAmount;

        // Setup and revoke delegate
        vm.startPrank(depositor);
        wallet.initiateWithdrawal(address(usdc), withdrawAmount);
        wallet.addDelegate(address(usdc), delegate);
        wallet.removeDelegate(address(usdc), delegate);
        vm.stopPrank();

        BurnIntent memory intent = baseIntent;
        intent.spec.sourceSigner = AddressLib._addressToBytes32(delegate);

        uint256 burnValue = depositorInitialBalance / 2;
        uint256 fee = defaultMaxFee / 2;
        uint256 signerKey = delegateKey; // Signed by delegate
        address expectedAuthorizer = delegate;
        string memory contextSuffix = "(Both, Revoked Delegate)";
        uint256 expectedTotalDeducted = burnValue + fee;

        SingleBurnTestConfig memory config;
        config.contextSuffix = contextSuffix;
        config.intent = intent;
        config.fee = fee;
        config.signerKey = signerKey;

        uint256 initialTotalSupply = usdc.totalSupply();
        config.initialBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: remainingAvailable,
            depositorWithdrawing: withdrawAmount,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: initialTotalSupply
        });

        config.finalBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: 0,
            depositorWithdrawing: withdrawAmount - (expectedTotalDeducted - remainingAvailable),
            feeRecipientExternalUsdc: fee,
            walletExternalUsdc: depositorInitialBalance - expectedTotalDeducted,
            usdcTotalSupply: initialTotalSupply - burnValue
        });

        config.eventParams = ExpectedBurnEventParams({
            token: address(usdc),
            depositor: depositor,
            transferSpecHash: keccak256(TransferSpecLib.encodeTransferSpec(intent.spec)),
            destinationDomain: intent.spec.destinationDomain,
            recipient: intent.spec.destinationRecipient,
            authorizer: expectedAuthorizer,
            value: burnValue,
            fee: fee,
            fromAvailable: remainingAvailable,
            fromWithdrawing: expectedTotalDeducted - remainingAvailable
        });

        _executeAndAssertSingleBurn(config);
    }

    // Struct to hold test data for the multi-set mixed domain test to avoid stack too deep errors
    struct MultiSetMixedDomainTestData {
        uint256 fee1;
        uint256 fee2;
        uint256 fee3Irrelevant;
        uint256 fee4;
        uint256 value1;
        uint256 value2;
        uint256 value3Irrelevant;
        uint256 value4;
        BurnIntent intent1;
        BurnIntent intent2;
        BurnIntent intent3Irrelevant;
        BurnIntent intent4;
        BurnIntent[] intentsForSet;
        BurnIntentSet intentSet;
        bytes encodedIntent1;
        bytes encodedIntentSet;
        bytes sig1;
        bytes sigSet;
        bytes[] intents;
        bytes[] signatures;
        uint256[][] fees;
        uint256 initialTotalSupply;
        uint256 expectedTotalValueBurned;
        uint256 expectedTotalFeeCharged;
        uint256 expectedTotalDeducted;
        ExpectedBalances initialExpectedBalances;
        ExpectedBalances finalExpectedBalances;
        ExpectedBurnEventParams eventParams1;
        ExpectedBurnEventParams eventParams2;
        ExpectedBurnEventParams eventParams4;
    }

    /// Tests gatewayBurn with multiple independent intent inputs, including a set with mixed domain relevance.
    /// - intents[0]: Single intent, current domain.
    /// - intents[1]: Set of 3 intents (current, other, current).
    /// Expects burns for the 3 current-domain intents to succeed and the other-domain intent to be skipped.
    function test_gatewayBurn_multipleSets_mixedDomains_fromAvailable_depositorSigner() public {
        MultiSetMixedDomainTestData memory testData;

        testData.fee1 = defaultMaxFee / 10;
        testData.fee2 = defaultMaxFee / 20;
        testData.fee3Irrelevant = defaultMaxFee / 30; // Fee for the irrelevant intent (won't be charged)
        testData.fee4 = defaultMaxFee / 40;

        testData.value1 = depositorInitialBalance / 10;
        testData.value2 = depositorInitialBalance / 20;
        testData.value3Irrelevant = depositorInitialBalance / 30; // Value for irrelevant intent
        testData.value4 = depositorInitialBalance / 40;

        // Intent 1: Single, current domain
        testData.intent1 = baseIntent;
        testData.intent1.spec.value = testData.value1;
        testData.intent1.maxFee = testData.fee1 * 2; // Ensure fee is allowed

        // Intent 2: Part of set, current domain
        testData.intent2 = baseIntent;
        testData.intent2.spec.value = testData.value2;
        testData.intent2.maxFee = testData.fee2 * 2;

        // Intent 3: Part of set, a different domain (should be skipped)
        testData.intent3Irrelevant = baseIntent;
        testData.intent3Irrelevant.spec.value = testData.value3Irrelevant;
        testData.intent3Irrelevant.spec.sourceDomain = domain + 1; // Different domain
        testData.intent3Irrelevant.maxFee = testData.fee3Irrelevant * 2;

        // Intent 4: Part of set, current domain
        testData.intent4 = baseIntent;
        testData.intent4.spec.value = testData.value4;
        testData.intent4.maxFee = testData.fee4 * 2;

        // Create intent set (containing intents 2, 3, 4)
        testData.intentsForSet = new BurnIntent[](3);
        testData.intentsForSet[0] = testData.intent2;
        testData.intentsForSet[1] = testData.intent3Irrelevant; // The irrelevant one
        testData.intentsForSet[2] = testData.intent4;
        testData.intentSet = BurnIntentSet({intents: testData.intentsForSet});

        // Encode intents
        testData.encodedIntent1 = BurnIntentLib.encodeBurnIntent(testData.intent1);
        testData.encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(testData.intentSet);

        // Sign intents
        testData.sig1 = _signIntentOrIntentSet(testData.encodedIntent1, depositorKey);
        testData.sigSet = _signIntentOrIntentSet(testData.encodedIntentSet, depositorKey);

        testData.intents = new bytes[](2);
        testData.intents[0] = testData.encodedIntent1;
        testData.intents[1] = testData.encodedIntentSet;

        testData.signatures = new bytes[](2);
        testData.signatures[0] = testData.sig1;
        testData.signatures[1] = testData.sigSet;

        testData.fees = new uint256[][](2);
        testData.fees[0] = new uint256[](1); // Fees for intents[0] (intent1)
        testData.fees[0][0] = testData.fee1;
        testData.fees[1] = new uint256[](3); // Fees for intents[1] (intentSet: intent2, intent3, intent4)
        testData.fees[1][0] = testData.fee2;
        testData.fees[1][1] = testData.fee3Irrelevant; // Provide fee, though it shouldn't be used
        testData.fees[1][2] = testData.fee4;

        // Expected initial state
        testData.initialTotalSupply = usdc.totalSupply();
        testData.expectedTotalValueBurned = testData.value1 + testData.value2 + testData.value4; // value3 is skipped
        testData.expectedTotalFeeCharged = testData.fee1 + testData.fee2 + testData.fee4; // fee3 is skipped
        testData.expectedTotalDeducted = testData.expectedTotalValueBurned + testData.expectedTotalFeeCharged;
        testData.initialExpectedBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: 0,
            walletExternalUsdc: depositorInitialBalance,
            usdcTotalSupply: testData.initialTotalSupply
        });
        _assertBalances("Initial State (MultiSet Mixed)", depositor, feeRecipient, testData.initialExpectedBalances);

        // Event for intent1
        testData.eventParams1.token = address(usdc);
        testData.eventParams1.depositor = depositor;
        testData.eventParams1.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(testData.intent1.spec));
        testData.eventParams1.destinationDomain = testData.intent1.spec.destinationDomain;
        testData.eventParams1.recipient = testData.intent1.spec.destinationRecipient;
        testData.eventParams1.authorizer = depositor;
        testData.eventParams1.value = testData.value1;
        testData.eventParams1.fee = testData.fee1;
        testData.eventParams1.fromAvailable = testData.value1 + testData.fee1; // Assuming drawn from available first
        testData.eventParams1.fromWithdrawing = 0;
        _expectBurnEvent(testData.eventParams1);

        // Event for intent2
        testData.eventParams2.token = address(usdc);
        testData.eventParams2.depositor = depositor;
        testData.eventParams2.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(testData.intent2.spec));
        testData.eventParams2.destinationDomain = testData.intent2.spec.destinationDomain;
        testData.eventParams2.recipient = testData.intent2.spec.destinationRecipient;
        testData.eventParams2.authorizer = depositor;
        testData.eventParams2.value = testData.value2;
        testData.eventParams2.fee = testData.fee2;
        testData.eventParams2.fromAvailable = testData.value2 + testData.fee2;
        testData.eventParams2.fromWithdrawing = 0;
        _expectBurnEvent(testData.eventParams2);

        // Event for intent4 (intent3 is skipped)
        testData.eventParams4.token = address(usdc);
        testData.eventParams4.depositor = depositor;
        testData.eventParams4.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(testData.intent4.spec));
        testData.eventParams4.destinationDomain = testData.intent4.spec.destinationDomain;
        testData.eventParams4.recipient = testData.intent4.spec.destinationRecipient;
        testData.eventParams4.authorizer = depositor;
        testData.eventParams4.value = testData.value4;
        testData.eventParams4.fee = testData.fee4;
        testData.eventParams4.fromAvailable = testData.value4 + testData.fee4;
        testData.eventParams4.fromWithdrawing = 0;
        _expectBurnEvent(testData.eventParams4);

        _callGatewayBurnSignedBy(testData.intents, testData.signatures, testData.fees, burnSignerKey);

        testData.finalExpectedBalances = ExpectedBalances({
            depositorExternalUsdc: 0,
            depositorAvailable: depositorInitialBalance - testData.expectedTotalDeducted,
            depositorWithdrawing: 0,
            feeRecipientExternalUsdc: testData.expectedTotalFeeCharged,
            walletExternalUsdc: depositorInitialBalance - testData.expectedTotalDeducted,
            usdcTotalSupply: testData.initialTotalSupply - testData.expectedTotalValueBurned
        });
        _assertBalances("Final State (MultiSet Mixed)", depositor, feeRecipient, testData.finalExpectedBalances);
    }

    struct MultiDepositorTestData {
        uint256 burnValue1;
        uint256 fee1;
        uint256 burnValue2;
        uint256 fee2;
        BurnIntent intent1;
        BurnIntent intent2;
        bytes encodedIntent1;
        bytes encodedIntent2;
        bytes sig1;
        bytes sig2;
        bytes[] intents;
        bytes[] signatures;
        uint256[][] fees;
        uint256 initialTotalSupply;
        uint256 initialFeeRecipientBalance;
        uint256 initialWalletBalance;
        uint256 expectedTotalFee;
        uint256 expectedTotalValueBurned;
        uint256 expectedTotalDeducted;
        ExpectedBurnEventParams eventParams1;
        ExpectedBurnEventParams eventParams2;
    }

    function test_gatewayBurn_multipleDepositors_currentDomain_fromAvailable_depositorSigners() public {
        // Setup second depositor balance
        deal(address(usdc), depositor2, depositor2InitialBalance, true);
        vm.startPrank(depositor2);
        {
            usdc.approve(address(wallet), type(uint256).max);
            wallet.deposit(address(usdc), depositor2InitialBalance);
        }
        vm.stopPrank();

        MultiDepositorTestData memory testData;

        testData.burnValue1 = depositorInitialBalance / 5; // $1000 from depositor1
        testData.fee1 = defaultMaxFee / 10; // $0.10 fee for depositor1
        testData.burnValue2 = depositor2InitialBalance / 3; // $1000 from depositor2
        testData.fee2 = defaultMaxFee / 20; // $0.05 fee for depositor2

        // Intent for depositor 1
        testData.intent1 = baseIntent;
        testData.intent1.spec.sourceDepositor = AddressLib._addressToBytes32(depositor);
        testData.intent1.spec.value = testData.burnValue1;
        testData.intent1.maxFee = defaultMaxFee; // Ensure provided fee1 is allowed

        // Intent for depositor 2
        testData.intent2 = baseIntent;
        testData.intent2.spec.sourceDepositor = AddressLib._addressToBytes32(depositor2);
        testData.intent2.spec.sourceSigner = AddressLib._addressToBytes32(depositor2);
        testData.intent2.spec.value = testData.burnValue2;
        testData.intent2.maxFee = defaultMaxFee;

        testData.encodedIntent1 = BurnIntentLib.encodeBurnIntent(testData.intent1);
        testData.sig1 = _signIntentOrIntentSet(testData.encodedIntent1, depositorKey);

        testData.encodedIntent2 = BurnIntentLib.encodeBurnIntent(testData.intent2);
        testData.sig2 = _signIntentOrIntentSet(testData.encodedIntent2, depositor2Key);

        testData.intents = new bytes[](2);
        testData.intents[0] = testData.encodedIntent1;
        testData.intents[1] = testData.encodedIntent2;

        testData.signatures = new bytes[](2);
        testData.signatures[0] = testData.sig1;
        testData.signatures[1] = testData.sig2;

        testData.fees = new uint256[][](2);
        testData.fees[0] = new uint256[](1);
        testData.fees[0][0] = testData.fee1;
        testData.fees[1] = new uint256[](1);
        testData.fees[1][0] = testData.fee2;

        testData.initialTotalSupply = usdc.totalSupply();
        testData.initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        testData.initialWalletBalance = usdc.balanceOf(address(wallet));

        // Depositor 1 Initial State
        assertEq(wallet.availableBalance(address(usdc), depositor), depositorInitialBalance, "Initial D1 Available");
        assertEq(wallet.withdrawingBalance(address(usdc), depositor), 0, "Initial D1 Withdrawing");

        // Depositor 2 Initial State
        assertEq(wallet.availableBalance(address(usdc), depositor2), depositor2InitialBalance, "Initial D2 Available");
        assertEq(wallet.withdrawingBalance(address(usdc), depositor2), 0, "Initial D2 Withdrawing");

        // Event for Depositor 1's burn
        testData.eventParams1.token = address(usdc);
        testData.eventParams1.depositor = depositor;
        testData.eventParams1.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(testData.intent1.spec));
        testData.eventParams1.destinationDomain = testData.intent1.spec.destinationDomain;
        testData.eventParams1.recipient = testData.intent1.spec.destinationRecipient;
        testData.eventParams1.authorizer = depositor;
        testData.eventParams1.value = testData.burnValue1;
        testData.eventParams1.fee = testData.fee1;
        testData.eventParams1.fromAvailable = testData.burnValue1 + testData.fee1;
        testData.eventParams1.fromWithdrawing = 0;
        _expectBurnEvent(testData.eventParams1);

        // Event for Depositor 2's burn
        testData.eventParams2.token = address(usdc);
        testData.eventParams2.depositor = depositor2;
        testData.eventParams2.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(testData.intent2.spec));
        testData.eventParams2.destinationDomain = testData.intent2.spec.destinationDomain;
        testData.eventParams2.recipient = testData.intent2.spec.destinationRecipient;
        testData.eventParams2.authorizer = depositor2;
        testData.eventParams2.value = testData.burnValue2;
        testData.eventParams2.fee = testData.fee2;
        testData.eventParams2.fromAvailable = testData.burnValue2 + testData.fee2;
        testData.eventParams2.fromWithdrawing = 0;
        _expectBurnEvent(testData.eventParams2);

        _callGatewayBurnSignedBy(testData.intents, testData.signatures, testData.fees, burnSignerKey);

        testData.expectedTotalFee = testData.fee1 + testData.fee2;
        testData.expectedTotalValueBurned = testData.burnValue1 + testData.burnValue2;
        testData.expectedTotalDeducted = (testData.burnValue1 + testData.fee1) + (testData.burnValue2 + testData.fee2);

        // Check Depositor 1 Final State
        assertEq(
            wallet.availableBalance(address(usdc), depositor),
            depositorInitialBalance - (testData.burnValue1 + testData.fee1),
            "Final D1 Available"
        );
        assertEq(wallet.withdrawingBalance(address(usdc), depositor), 0, "Final D1 Withdrawing");
        assertEq(usdc.balanceOf(depositor), 0, "Final D1 External");

        // Check Depositor 2 Final State
        assertEq(
            wallet.availableBalance(address(usdc), depositor2),
            depositor2InitialBalance - (testData.burnValue2 + testData.fee2),
            "Final D2 Available"
        );
        assertEq(wallet.withdrawingBalance(address(usdc), depositor2), 0, "Final D2 Withdrawing");
        assertEq(usdc.balanceOf(depositor2), 0, "Final D2 External");

        assertEq(
            usdc.balanceOf(feeRecipient),
            testData.initialFeeRecipientBalance + testData.expectedTotalFee,
            "Final Fee Recipient Balance"
        );
        assertEq(
            usdc.balanceOf(address(wallet)),
            testData.initialWalletBalance - testData.expectedTotalDeducted,
            "Final Wallet Balance"
        );
        assertEq(
            usdc.totalSupply(), testData.initialTotalSupply - testData.expectedTotalValueBurned, "Final Total Supply"
        );
    }

    function test_getTypedDataHash_returnsExpectedBurnIntentHash() public view {
        BurnIntent memory intent = BurnIntent({
            maxBlockHeight: 1,
            maxFee: defaultMaxFee,
            spec: TransferSpec({
                version: TRANSFER_SPEC_VERSION,
                sourceDomain: 0,
                destinationDomain: 1, // A different destination domain
                sourceContract: AddressLib._addressToBytes32(address(0x1)),
                destinationContract: AddressLib._addressToBytes32(address(0x2)),
                sourceToken: AddressLib._addressToBytes32(address(0x3)),
                destinationToken: AddressLib._addressToBytes32(address(0x4)),
                sourceDepositor: AddressLib._addressToBytes32(address(0x5)),
                destinationRecipient: AddressLib._addressToBytes32(address(0x6)),
                sourceSigner: AddressLib._addressToBytes32(address(0x7)),
                destinationCaller: bytes32(0),
                value: 100,
                salt: keccak256("salt"),
                hookData: HOOK_DATA
            })
        });

        bytes memory walletEncoded = BurnIntentLib.encodeBurnIntent(intent);
        bytes32 expectedHash = 0x52528dacb2770069666b863a3c27ae73d54cf8c96b25dde5da5480a82b504b71;

        bytes32 walletEIP712Hash = wallet.getTypedDataHash(walletEncoded);

        assertEq(walletEIP712Hash, expectedHash);
    }

    function test_getTypedDataHash_returnsExpectedBurnIntentSetHash() public view {
        BurnIntent memory intent = BurnIntent({
            maxBlockHeight: 1,
            maxFee: defaultMaxFee,
            spec: TransferSpec({
                version: TRANSFER_SPEC_VERSION,
                sourceDomain: 0,
                destinationDomain: 1, // A different destination domain
                sourceContract: AddressLib._addressToBytes32(address(0x1)),
                destinationContract: AddressLib._addressToBytes32(address(0x2)),
                sourceToken: AddressLib._addressToBytes32(address(0x3)),
                destinationToken: AddressLib._addressToBytes32(address(0x4)),
                sourceDepositor: AddressLib._addressToBytes32(address(0x5)),
                destinationRecipient: AddressLib._addressToBytes32(address(0x6)),
                sourceSigner: AddressLib._addressToBytes32(address(0x7)),
                destinationCaller: bytes32(0),
                value: 100,
                salt: keccak256("salt"),
                hookData: HOOK_DATA
            })
        });

        BurnIntent[] memory intentArray = new BurnIntent[](1);
        intentArray[0] = intent;
        bytes memory encodedIntentSet = BurnIntentLib.encodeBurnIntentSet(BurnIntentSet({intents: intentArray}));
        bytes32 expectedHash = 0xe598e3111843912b9b25c9fd7976c93fbd3edfeaf186edaf4e205b0a92cea9a7;

        bytes32 walletEIP712Hash = wallet.getTypedDataHash(encodedIntentSet);

        assertEq(walletEIP712Hash, expectedHash);
    }
}
