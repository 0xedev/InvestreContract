# InvestreContract - Social Auto-Buy Protocol

**InvestreContract** is a smart contract system that enables automated token purchases triggered by social interactions on Farcaster, with intelligent routing across multiple Uniswap versions (V2, V3, V4).

## Overview

The protocol allows users to set up automated token purchases that are triggered by social interactions (likes, recasts) on Farcaster. Users pre-approve USDC spending, and authorized backends monitor social activity to execute purchases on their behalf, with purchased tokens held in the user's account within the contract.

### Key Features

- **Social-Triggered Auto-Buys**: Automatic token purchases triggered by Farcaster likes and recasts
- **Multi-Router Support**: Smart routing across Uniswap V4, V3, and V2 for optimal execution
- **Backend Authorization**: Authorized backends can execute trades on behalf of users
- **User-Controlled Limits**: Users set their own spending limits and social interaction amounts
- **Fee Structure**: 1% fee on all transactions goes to fee recipient
- **Earned Token Management**: Users can swap their earned tokens using smart routing

### Architecture

- **Option A Design**: Backends call functions on behalf of users (current implementation)
- **Smart Routing**: V4-first with V3/V2 fallback for optimal swap execution
- **User Funds**: USDC remains in user wallets, contract approved for spending
- **Earned Tokens**: Purchased tokens stored in contract, withdrawable by users

## Smart Contract

The main contract `AutoBuyContract` is built with:

- **Solidity 0.8.26**
- **OpenZeppelin** security standards
- **Uniswap V2/V3/V4** integration
- **ReentrancyGuard** protection
- **Foundry** testing framework

### Key Functions

- `executeFarcasterAutoBuy()` - Execute social-triggered purchases
- `smartAutoBuy()` - Intelligent multi-router token swapping
- `withdrawUserTokens()` - Withdraw earned tokens
- `setUserBuyLimitSelf()` - Set personal spending limits
- `setSocialAmounts()` - Configure like/recast amounts

## Development Setup

This project uses **Foundry** for development and testing.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Installation

```shell
git clone <repository-url>
cd extwall
forge install
```

### Build

```shell
forge build
```

### Test

Run all tests:

```shell
forge test
```

Run specific test suites:

```shell
# Integration tests
forge test --match-contract AutoBuyIntegration -vv

# Advanced functionality tests
forge test --match-contract AutoBuyAdvanced -vv

# Gas optimization tests
forge test --match-contract AutoBuyGas -vv
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

## Deployment

### Base Mainnet

For Base mainnet deployment, see [DEPLOY_BASE.md](./DEPLOY_BASE.md) for detailed instructions.

Quick deployment:

```shell
forge script script/DeployBase.s.sol:DeployBase --rpc-url base --broadcast --verify
```

### Local Testing

Start local node:

```shell
anvil
```

Deploy locally:

```shell
forge script script/Counter.s.sol:CounterScript --rpc-url http://localhost:8545 --private-key <anvil_private_key>
```

## Testing Strategy

The project includes comprehensive test suites:

- **Integration Tests** (`AutoBuyIntegration.t.sol`): Multi-user scenarios, social interactions, backend management
- **Advanced Tests** (`AutoBuyAdvanced.t.sol`): Smart routing, fallback logic, V4 swaps, fuzz testing
- **Gas Tests** (`AutoBuyGas.t.sol`): Gas optimization validation
- **Invariant Tests** (`AutoBuyInvariant.t.sol`): Property-based testing

### Test Coverage

- ✅ Social auto-buy execution
- ✅ Multi-router fallback logic
- ✅ User limit enforcement
- ✅ Backend authorization
- ✅ Fee collection
- ✅ Token withdrawal
- ✅ Emergency scenarios

## Documentation

- [Gas Optimization Suggestions](./GAS_OPTIMIZATION_SUGGESTIONS.md)
- [Base Deployment Guide](./DEPLOY_BASE.md)
- [Foundry Documentation](https://book.getfoundry.sh/)

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add comprehensive tests
4. Run `forge test` and `forge fmt`
5. Submit a pull request

## Support

For questions and support, please open an issue in the repository.
