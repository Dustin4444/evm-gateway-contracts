# Changelog

A summary of notable changes and updates for each Circle Gateway Contracts release and contract upgrade.

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
