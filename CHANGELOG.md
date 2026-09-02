# Changelog

A summary of notable changes and updates for each Circle Gateway Contracts release and contract upgrade.

## 1.3.0 (2026/06)

- Added TEE-based ERC-1271 signature verification to `GatewayWallet` via the new `ContractSignatureSigners` module. A new `contractSignatureSigner` role allows a TEE to vouch for contract signers by re-signing the burn intent using an ECDSA signature after verifying the ERC-1271 signature offchain
- Split the `contractSignersAllowlister` role in two. The existing allowlister role is authorized to call `allowlistContractSigner`, while a new `contractSignersDisallowlister` role is authorized to call `disallowContractSigner`.
- Added a `RenounceOwnershipDisabled` safeguards.

## 1.2.0 (2026/01)

- Added batching support to `GatewayWallet` via the new `Batches` module. A new `batchSigner` role signs batch calldata, and `submitBatch` applies a set of signed `BatchedDelta` balance changes for a single supported token in one transaction.

## 1.1.0 (2025/11)

- Added support for contract allowlisting in `GatewayWallet`. Contracts on the allowlist can now initiate burn intents using ERC1271 signatures.

## 1.0.0 (2025/07)

- Initial release of Gateway contracts
- Create `GatewayWallet` contract supporting deposits, burns, and withdrawals
- Create `GatewayMinter` contract for processing attestations and minting tokens
- Add delegation support for attestations and burn authorizations
- Add denylist, pausing, and token support modules
- Add withdrawal delay mechanism for security
- Add EIP-7597 and EIP-7598 interfaces for cross-chain token transfers
- Create deployment scripts using CREATE2 for deterministic addresses
- Create `UpgradeablePlaceholder` for upgradeable proxy pattern
