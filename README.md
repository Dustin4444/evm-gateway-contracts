# Circle Gateway Contracts

These are the contracts that support the Circle Gateway product. See the contract docs or Circle's website for more information about the product and how to use it.

## Install dependencies

- Run `git submodule update --init --recursive` to update/download all libraries.
- Ensure Yarn is installed and then run `yarn install` to install additional JS dependencies.

## Install Foundry CLI

- Run `curl -L https://foundry.paradigm.xyz | bash`
- Follow the instructions of that command to source env file
- run `foundryup --install v1.0.0`

## Deployment

### How it works

The deployment steps are:

1. Deploy the `UpgradablePlaceholder` implementation
2. Deploy the actual implementation (e.g. `GatewayMinter`, `GatewayWallet`)
3. Deploy the ERC1967Proxy and setup the proxy:
   1. Deploy the ERC1967 Proxy, set the implementation to `UpgradablePlaceholder` and initialize the owner to Create2Factory address.
   2. In the same transcation, upgrade the implementation to actual implementation and initialize the implementation properly.

The reason of setting owner of `UpgradablePlaceholder` to Create2Factory address is that since the owner is part of the address computation, we want to use Create2Factory to avoid managing an extra EOA key.

Since the owner of `UpgradablePlaceholder` is Create2Factory and only the owner can perform `upgradeToAndCall`, we decided to use `Create2Factory.deployAndMultiCall` to upgrade to actual implementation in the proxy deployment call.

**Note**: The deployment scripts always deploy the latest compiled version of the contracts. Make sure to compile your contracts with `yarn artifacts` before deployment to ensure you're deploying the most up-to-date implementation.

### Prerequisites

Before deploying the contracts, ensure you have:

1. Create a `.env` file from `.env.example` and set up environment variables in `.env` file.

2. Run `source .env` to load the environment variables in your shell.

3. Verified you have sufficient funds in the deployer account for the target network

### Deploying Contracts

#### Step 1: Start a local blockchain

_Only needed for local deployment_

Start a local RPC node at http://127.0.0.1:8485 by running `anvil`.

#### Step 2: Deploy Create2Factory Contract

_Only needed for local deployment_

##### Local Deployment

Run the following command to deploy a test instance of the Create2Factory contract:

```bash
forge create Create2Factory -r http://127.0.0.1:8545 --broadcast --private-key $DEPLOYER_PRIVATE_KEY --constructor-args $DEPLOYER_ADDRESS
```

- `DEPLOYER_PRIVATE_KEY`: Any key from anvil pre-funded addresses.
- `DEPLOYER_ADDRESS`: This address should match the $DEPLOYER_ADDRESS in `.env`

Add the deployed Create2Factory contract address to your `.env` file under the variable `LOCAL_CREATE2_FACTORY_ADDRESS`.

##### Local deployment

Follow the instructions in evm-cctp-contracts-private README to deploy Create2Factory. Update `LOCAL_DEPLOYER_ADDRESS` and `LOCAL_CREATE2_FACTORY_ADDRESS` in `.env`.

#### Step3: Generate Deployment Transactions for `GatewayWallet` and `GatewayMinter`.

Run the following command to generate deployment transactions for `GatewayWallet` and `GatewayMinter`:

```bash
ENV=$ENV forge script script/001_DeployGatewayWallet.sol --rpc-url $RPC_URL -vvvv --slow --force
ENV=$ENV forge script script/002_DeployGatewayMinter.sol --rpc-url $RPC_URL -vvvv --slow --force
```

- `ENV`: Use `LOCAL` for local deployment. Or choose from `TESTNET_STAGING`, `TESTNET_PROD`, and `MAINNET_PROD`.
- `RPC_URL`: The rpc url for the targeted blockchain. use `http://127.0.0.1:8485` for local deployment.

The generated transaction data will be available in the `broadcast/` directory and can be used for signing.

### Deployed contract validation

Fill in the `Deployed Contract Validation` section in `.env` and run:

```bash
forge script script/003_DeployedContractValidation.s.sol --rpc-url $RPC_URL -vvvv --slow --force
```

This command validates deployed contract bytecode matches expected bytecode and contract state matches expected values.

## Upgrading Contracts

### Upgrading GatewayWallet

To upgrade an existing deployed GatewayWallet to the latest implementation:

1. Add the proxy address of the deployed GatewayWallet to your `.env` file as `GATEWAYMINTER_WALLET_ADDRESS`
2. Compile the contracts using `yarn artifacts`
3. Run the upgrade script:

```bash
# Generate upgrade transaction (dry run)
ENV=$ENV forge script script/004_UpgradeGatewayWallet.sol:UpgradeGatewayWallet --rpc-url $RPC_URL -vvvv --slow --force

# Execute upgrade (broadcast mode)
ENV=$ENV forge script script/004_UpgradeGatewayWallet.sol:UpgradeGatewayWallet --rpc-url $RPC_URL -vvvv --slow --force --broadcast
```

- `ENV`: Use `LOCAL` for local deployment. Or choose from `TESTNET_STAGING`, `TESTNET_PROD`, and `MAINNET_PROD`.
- `RPC_URL`: The rpc url for the targeted blockchain.
- `GATEWAYMINTER_WALLET_ADDRESS`: Must be set in your environment to the proxy address you want to upgrade.
- `GATEWAYWALLET_OWNER_ADDRESS`: Must be set to the current owner of the GatewayWallet proxy (required for the upgrade call).

The script will:
- Deploy a new GatewayWallet implementation using CREATE2 with the deployer address (same salt, different address due to updated bytecode)
- Call `upgradeTo` on the proxy using the owner address to point to the new implementation
- Output the new implementation address for verification

The generated transaction data will be available in the `broadcast/` directory and can be used for signing.

**Note**: The script requires two different signers:
- The **deployer** (from environment config) deploys the new implementation contract via CREATE2
- The **owner** (from `GATEWAYWALLET_OWNER_ADDRESS`) executes the upgrade on the proxy

### How to Update Deployment Scripts

#### Update Compiled Contract Artifacts

Run the following command to generate new artifacts for deployment:

```bash
yarn artifacts
```

#### Find New Salts

Find salts that creates gas-efficient proxy addresses via:

```bash
cast create2 --starts-with $ADDRESS_PREFIX --deployer $DEPLOYER> --init-code-hash $INIT_CODE_HASH
```

- `ADDRESS_PREFIX` is the prefix of the address we want to find. Usually set to `00000000` for a gas-efficient address.
- `DEPLOYER` is the address of Create2Factory.
- `INIT_CODE_HASH` is keccak256 hash of initcode + abi-encoded constuctor argument.

We have chosen the following prefixes for our top-level contracts:

| Environment | Network Type | Wallet Prefix | Minter Prefix | Notes |
|:------------------------:|:------------------------:|:------------------------:|:------------------------:|:------------------------:|
| Production | Mainnet | 0x7777777 | 0x2222222 |  |
| Production | Testnet | 0x0077777 | 0x0022222 | Add zero byte to mainnet addresses |
| Staging | Testnet | 0x5577777 | 0x5522222 | 5 = "S" for Staging |

To find and verify salts for the Wallet and Minter contracts, correctly set the `ENV` and `RPC_URL` environment variables (and possibly `LOCAL_CREATE2_FACTORY_ADDRESS` depending on your environment). Use any values for all of the other variables, as they do not matter here.

Simulate the deployments by running the below commands and note down the values initCodeHash from the logs of each command
1. `ENV=$ENV forge script script/001_DeployGatewayWallet.sol --rpc-url $RPC_URL -vv`
2. `ENV=$ENV forge script script/002_DeployGatewayMinter.sol --rpc-url $RPC_URL -vv`

Then, run the following command:

```shell
# Use the same value specified in the 000_Constants.sol or `LOCAL_CREATE2_FACTORY_ADDRESS` (depending on your environment)  
export SALT_MINE_CREATE2_FACTORY_ADDRESS=

# Use values of previous step's logs
export WALLET_PROXY_INIT_CODE_HASH=
export MINTER_PROXY_INIT_CODE_HASH=

# Make sure ENV has been set before calling this command (see .env file)
yarn mine-salts
```

Update the salts in `000_Constants.sol` and re-simulate the deployments to verify that the proxy addresses have been updated to the expected prefixes.

## Test

### Unit Tests and Fork Tests (Foundry)

To run tests using Foundry, run `yarn test`. This will run all tests using the default Anvil localnet.

To run tests against each supported network (by forking from each network's RPC endpoint), run `yarn test:all`. If failures related to remote state from an old block are encountered, either point to archive nodes or run `./scripts/update_block_numbers.sh` to pin the latest block for each network and try again.

To run tests and output a gas report for the top-level contracts, run `yarn test:gas`.

### Mock FiatToken port

To simplify local development and testing we have a local port of the FiatToken contracts from the https://github.com/circlefin/stablecoin-evm repo. The port is based on commit [0642db6](https://github.com/circlefin/stablecoin-evm/commit/0642db65d656a51d4df21b8d03dd38124ad0e7b3). When there are essential changes to the FiatToken contracts (e.g., new version release), we'll need to:

1. Go through the diff between the above commit and the latest version, applying the latest changes into `test/mock_fiattoken`
2. Update dependency imports and relative imports
3. Bump solidity version and fix resulting compiler errors
4. Update `test/util/DeployMockFiatToken.sol` if necessary

### Linting and Formatting

Run `yarn lint` to lint all `.sol` files in the `src` and `test` directories, and `yarn lint:fix` to automatically fix any fixable linting errors.

Run `yarn format` to check the formatting of all `.sol` files in the `src` and `test` directories, and `yarn format:fix` to automatically format them.

### Coverage

Run `yarn coverage` to generate a coverage report for the tests. This depends on the `lcov` and `genhtml` commands, which may be installed on macOS with `brew install lcov`. The coverage report will be generated in the `coverage` directory.

## Development

### Contract Sizes

To check the bytecode size of all top-level contracts against the EIP-170 contract size limit, run `yarn sizes`.

### Important Considerations: Memory Initialization with TypedMemView

This project relies heavily on the `TypedMemView` library (`lib/memview-sol/`) for efficient memory manipulation.

**Warning:** As documented in the [TypedMemView](https://github.com/summa-tx/memview-sol/tree/main) library itself, it utilizes unallocated memory operations and **does not guarantee cleanup of unallocated memory regions** after its internal functions execute.

**Implication:** This means that memory subsequently allocated by contracts in _this_ project (e.g., declaring new `memory` variables like arrays or structs after `TypedMemView` operations have occurred within the same transaction execution path) **might not be zero-initialized**. It could contain residual data from previous operations.

**Required Precaution:** Developers working on this codebase **must not** assume that newly allocated memory variables or structures are automatically zero-initialized. If the logic relies on a memory variable starting at zero (or `false`, `address(0)`, etc.), it **must** be explicitly initialized after allocation.

## Continuous Integration using Github Actions

We use Github actions to run the linter and all the tests. The workflow configuration can be found in [.github/workflows/pipeline.yml](.github/workflows/pipeline.yml). While not a complete replacement, all CI steps may be run locally with `yarn ci`.

## Manual Triggering of the Olympix CI Workflow

You can manually trigger the Olympix.ai Code Scanning workflow using the `workflow_dispatch` feature of GitHub Actions.

1. Click on the `Actions` tab.
2. In the left sidebar, select `Olympix Scan`.
3. Select the branch & click on the `Run workflow` button.
