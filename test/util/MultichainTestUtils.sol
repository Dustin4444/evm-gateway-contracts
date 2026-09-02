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

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {GatewayMinter} from "src/GatewayMinter.sol";
import {GatewayWallet} from "src/GatewayWallet.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {BurnIntentLib} from "src/lib/BurnIntentLib.sol";
import {TransferSpec} from "src/lib/TransferSpec.sol";
import {MasterMinter} from "test/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenV2_2} from "test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployUtils} from "test/util/DeployUtils.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";
import {SignatureTestUtils} from "test/util/SignatureTestUtils.sol";

contract MultichainTestUtils is DeployUtils, SignatureTestUtils {
    using MessageHashUtils for bytes32;

    // Based on Ethereum, assuming 12 seconds per block, 21,600 blocks in 3 days.
    uint256 public constant WITHDRAW_DELAY = (3 * 24 * 60 * 60) / 12;
    uint256 public constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDC
    uint256 public constant MINT_AMOUNT = 100e6; // 100 USDC
    uint256 public constant FEE_AMOUNT = 10000; // 0.01 USDC
    bytes public constant HOOK_DATA = "Test hook data";

    uint256 public depositorPrivateKey = 0xdc47ad9d59d92b5f9b7f2400a82623f0c45917250135166b5037bd860ea6090c;
    address public depositor = vm.addr(depositorPrivateKey);

    uint256 public delegatePrivateKey = 0xf0ef684ba0cb4d94fd0a47b889f8fcae344a804955618434e960a38505180d3a;
    address public delegate = vm.addr(delegatePrivateKey);

    address public recipient = vm.addr(0xb0950200e150e70cb83af4a6c04668c71a9bf162798f7bf4c9300d4acde150ff);
    address public destinationCaller = vm.addr(0x503810cb8d7135c8775a09e90aef7f12682ab3702d2542e2b9f9c3c8123a5463);

    struct ChainSetup {
        uint256 forkId;
        uint32 domain;
        uint256 walletBurnSignerKey;
        uint256 minterAttestationSignerKey;
        GatewayWallet wallet;
        GatewayMinter minter;
        FiatTokenV2_2 usdc;
    }

    /// @dev Helper for setting up multi-chain test environments with GatewayWallet and GatewayMinter contracts
    /// @param chainName The name of the chain to fork, must match an RPC endpoint name in foundry.toml (e.g. "ethereum", "arbitrum")
    /// @return ChainSetup Struct containing all relevant contract instances and addresses
    function _initializeGatewayContracts(string memory chainName) internal returns (ChainSetup memory) {
        // Create and select fork for specified chain
        uint256 forkId = vm.createFork(vm.rpcUrl(chainName));
        vm.selectFork(forkId);

        FiatTokenV2_2 usdc = FiatTokenV2_2(ForkTestUtils.forkVars().usdc);
        uint32 domain = ForkTestUtils.forkVars().domain;

        // Generate role addresses based on chain ID
        uint256 chainId = block.chainid;
        address owner = vm.addr(chainId + 1);
        address walletFeeRecipient = vm.addr(chainId + 2);
        (address walletBurnSigner, uint256 walletBurnSignerKey) = makeAddrAndKey(vm.toString(chainId + 3));
        (address minterAttestationSigner, uint256 minterAttestationSignerKey) = makeAddrAndKey(vm.toString(chainId + 4));

        // Deploy core contracts
        (GatewayWallet wallet, GatewayMinter minter) = deploy(owner, domain);
        vm.makePersistent(address(wallet));
        vm.makePersistent(address(minter));

        vm.startPrank(owner);
        {
            // Configure minter settings
            minter.addSupportedToken(address(usdc));
            minter.addAttestationSigner(minterAttestationSigner);
            minter.updateMintAuthority(address(usdc), address(usdc));

            // Configure wallet settings
            wallet.addSupportedToken(address(usdc));
            wallet.addBurnSigner(walletBurnSigner);
            wallet.updateFeeRecipient(walletFeeRecipient);
            wallet.updateWithdrawalDelay(WITHDRAW_DELAY);
        }
        vm.stopPrank();

        // Setup wallet and minter as USDC minter / burner
        MasterMinter masterMinter = MasterMinter(usdc.masterMinter());
        address masterMinterOwner = masterMinter.owner();

        vm.startPrank(masterMinterOwner);
        {
            // Configure minter with maximum allowance
            masterMinter.configureController(masterMinterOwner, address(minter));
            masterMinter.configureMinter(type(uint256).max);

            // Configure wallet with zero allowance (burn only)
            masterMinter.configureController(masterMinterOwner, address(wallet));
            masterMinter.configureMinter(0);
        }
        vm.stopPrank();

        return ChainSetup({
            forkId: forkId,
            domain: domain,
            walletBurnSignerKey: walletBurnSignerKey,
            minterAttestationSignerKey: minterAttestationSignerKey,
            wallet: wallet,
            minter: minter,
            usdc: usdc
        });
    }

    function _createFees(bytes[] memory encodedBurnAuths, uint256 feeAmount)
        internal
        pure
        returns (uint256[][] memory fees)
    {
        uint256 n = encodedBurnAuths.length;

        fees = new uint256[][](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 m = BurnIntentLib.cursor(encodedBurnAuths[i]).numElements;
            fees[i] = new uint256[](m);
            for (uint256 j = 0; j < m; j++) {
                fees[i][j] = feeAmount;
            }
        }
    }

    function _createTransferSpec(
        ChainSetup memory sourceChain,
        ChainSetup memory destChain,
        uint256 amount,
        address depositor_,
        address recipient_,
        address sourceSigner_,
        address destinationCaller_
    ) internal returns (TransferSpec memory) {
        return TransferSpec({
            version: 1,
            sourceDomain: sourceChain.domain,
            destinationDomain: destChain.domain,
            sourceContract: AddressLib._addressToBytes32(address(sourceChain.wallet)),
            destinationContract: AddressLib._addressToBytes32(address(destChain.minter)),
            sourceToken: AddressLib._addressToBytes32(address(sourceChain.usdc)),
            destinationToken: AddressLib._addressToBytes32(address(destChain.usdc)),
            sourceDepositor: AddressLib._addressToBytes32(depositor_),
            destinationRecipient: AddressLib._addressToBytes32(recipient_),
            sourceSigner: AddressLib._addressToBytes32(sourceSigner_),
            destinationCaller: AddressLib._addressToBytes32(destinationCaller_),
            value: amount,
            salt: keccak256(abi.encode(vm.randomUint())),
            hookData: HOOK_DATA
        });
    }

    function _depositToChain(ChainSetup memory chain, address depositor_, uint256 amount_) internal {
        vm.selectFork(chain.forkId);
        vm.startPrank(depositor_);
        {
            deal(address(chain.usdc), depositor_, amount_);
            chain.usdc.approve(address(chain.wallet), amount_);
            chain.wallet.deposit(address(chain.usdc), amount_);
        }
        vm.stopPrank();
        assertEq(chain.usdc.balanceOf(address(chain.wallet)), amount_);
        assertEq(chain.wallet.availableBalance(address(chain.usdc), depositor_), amount_);
    }

    function _burnFromChain(
        ChainSetup memory chain,
        bytes memory encodedBurnAuth,
        bytes memory burnSignature,
        uint256 expectedTotalBurntAmount,
        uint256 expectedTotalFeeAmount
    ) internal {
        _burnFromChain(
            chain, encodedBurnAuth, burnSignature, depositor, expectedTotalBurntAmount, expectedTotalFeeAmount
        );
    }

    function _burnFromChain(
        ChainSetup memory chain,
        bytes memory encodedBurnAuth,
        bytes memory burnSignature,
        address depositor_,
        uint256 expectedTotalBurntAmount,
        uint256 expectedTotalFeeAmount
    ) internal {
        bytes[] memory allBurnAuths = new bytes[](1);
        allBurnAuths[0] = encodedBurnAuth;
        bytes[] memory allSignatures = new bytes[](1);
        allSignatures[0] = burnSignature;
        _burnFromChainMulti(
            chain, allBurnAuths, allSignatures, depositor_, expectedTotalBurntAmount, expectedTotalFeeAmount
        );
    }

    function _burnFromChainMulti(
        ChainSetup memory chain,
        bytes[] memory encodedBurnAuths,
        bytes[] memory burnSignatures,
        uint256 expectedTotalBurntAmount,
        uint256 expectedTotalFeeAmount
    ) internal {
        _burnFromChainMulti(
            chain, encodedBurnAuths, burnSignatures, depositor, expectedTotalBurntAmount, expectedTotalFeeAmount
        );
    }

    function _burnFromChainMulti(
        ChainSetup memory chain,
        bytes[] memory encodedBurnAuths,
        bytes[] memory burnSignatures,
        address depositor_,
        uint256 expectedTotalBurntAmount,
        uint256 expectedTotalFeeAmount
    ) internal {
        vm.selectFork(chain.forkId);

        // Record state before burn
        uint256 totalSupplyBefore = chain.usdc.totalSupply();
        uint256 depositorTotalBalanceBefore = chain.wallet.totalBalance(address(chain.usdc), depositor_);
        uint256 feeRecipientBalanceBefore = chain.usdc.balanceOf(chain.wallet.feeRecipient());

        // Prepare burn intent parameters
        uint256[][] memory fees = _createFees(encodedBurnAuths, FEE_AMOUNT);

        // Get burn signer signature and execute burn
        bytes memory burnSignerSignature =
            _signBurnIntents(encodedBurnAuths, burnSignatures, fees, chain.walletBurnSignerKey);
        chain.wallet.gatewayBurn(abi.encode(encodedBurnAuths, burnSignatures, fees), burnSignerSignature);

        // Verify state after burn
        assertEq(
            chain.usdc.totalSupply(),
            totalSupplyBefore - expectedTotalBurntAmount,
            "Total supply should decrease by expected amount"
        );
        assertEq(
            chain.wallet.totalBalance(address(chain.usdc), depositor_),
            depositorTotalBalanceBefore - expectedTotalBurntAmount - expectedTotalFeeAmount,
            "Depositor balance should decrease by expected burnt amount plus fees"
        );
        assertEq(
            chain.usdc.balanceOf(chain.wallet.feeRecipient()),
            feeRecipientBalanceBefore + expectedTotalFeeAmount,
            "Fee recipient should receive expected fee amount"
        );
    }

    function _mintFromChain(
        ChainSetup memory chain,
        bytes memory encodedAttestation,
        bytes memory attestationSignature,
        uint256 expectedTotalMinted
    ) internal {
        _mintFromChain(chain, encodedAttestation, attestationSignature, recipient, expectedTotalMinted);
    }

    function _mintFromChain(
        ChainSetup memory chain,
        bytes memory encodedAttestation,
        bytes memory attestationSignature,
        address recipient_,
        uint256 expectedTotalMinted
    ) internal {
        vm.selectFork(chain.forkId);

        // Record state before mint
        uint256 totalSupplyBefore = chain.usdc.totalSupply();
        uint256 recipientBalanceBefore = chain.usdc.balanceOf(recipient_);

        // Execute mint operation
        vm.prank(destinationCaller);
        chain.minter.gatewayMint(encodedAttestation, attestationSignature);

        // Verify state after mint
        assertEq(
            chain.usdc.totalSupply(),
            totalSupplyBefore + expectedTotalMinted,
            "Total supply should increase by expected amount"
        );
        assertEq(
            chain.usdc.balanceOf(recipient_),
            recipientBalanceBefore + expectedTotalMinted,
            "Recipient balance should increase by total minted amount"
        );
    }
}
