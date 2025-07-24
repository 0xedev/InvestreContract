# Base Mainnet Deployment Guide

## Prerequisites

1. **Base ETH**: You need ETH on Base for gas fees

   - Bridge ETH to Base: https://bridge.base.org
   - Or get Base ETH from exchanges like Coinbase

2. **Basescan API Key**: For contract verification

   - Get at: https://basescan.org/apis

3. **Deployer Wallet**: Private key with sufficient ETH balance

## Deployment Steps

### 1. Environment Setup

Copy the Base environment template:

```bash
cp .env.base .env
```

Edit `.env` with your actual values:

```bash
NETWORK=base
RPC_URL=https://mainnet.base.org
CHAIN_ID=8453
ETHERSCAN_API_KEY=your_actual_basescan_api_key
PRIVATE_KEY=your_actual_private_key
```

### 2. Deploy Contract

Deploy the AutoBuyContract to Base mainnet:

```bash
forge script script/DeployBase.s.sol:DeployBase --rpc-url base --broadcast --verify
```

Or with manual verification:

```bash
# Deploy without verification
forge script script/DeployBase.s.sol:DeployBase --rpc-url base --broadcast

# Verify separately (replace CONTRACT_ADDRESS)
forge verify-contract CONTRACT_ADDRESS src/AllUniswap.sol:AutoBuyContract \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address)" \
  0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD \
  0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967 \
  0x000000000022D473030F116dDEE9F6B43aC78BA3 \
  0x2626664c2603336E57B271c5C0b26F421741e481 \
  0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24 \
  0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) \
  --chain base
```

### 3. Post-Deployment Configuration

After successful deployment:

1. **Set up additional backends** (if needed):

```bash
cast send CONTRACT_ADDRESS "authorizeBackend(address)" BACKEND_WALLET_ADDRESS --rpc-url base --private-key $PRIVATE_KEY
```

2. **Set fee recipient** (if different from deployer):

```bash
cast send CONTRACT_ADDRESS "setFeeRecipient(address)" FEE_RECIPIENT_ADDRESS --rpc-url base --private-key $PRIVATE_KEY
```

3. **Transfer ownership** (if needed):

```bash
cast send CONTRACT_ADDRESS "transferOwnership(address)" NEW_OWNER_ADDRESS --rpc-url base --private-key $PRIVATE_KEY
```

## Contract Addresses Used

The deployment script uses these official Uniswap addresses on Base:

- **Universal Router**: `0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD`
- **Pool Manager (V4)**: `0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967`
- **Permit2**: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
- **V3 SwapRouter**: `0x2626664c2603336E57B271c5C0b26F421741e481`
- **V2 Router**: `0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24`
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

## Testing Deployment

Test basic functionality after deployment:

```bash
# Check if contract is deployed
cast code CONTRACT_ADDRESS --rpc-url base

# Check owner
cast call CONTRACT_ADDRESS "owner()" --rpc-url base

# Check USDC address
cast call CONTRACT_ADDRESS "USDC()" --rpc-url base

# Check fee recipient
cast call CONTRACT_ADDRESS "feeRecipient()" --rpc-url base
```

## Security Notes

1. **Private Key**: Never commit your private key to version control
2. **Ownership**: Consider using a multisig for production deployments
3. **Backend Authorization**: Only authorize trusted backend wallets
4. **Testing**: Test thoroughly on Base Sepolia testnet first

## Troubleshooting

### Common Issues:

1. **Insufficient funds**: Make sure deployer has enough Base ETH
2. **Verification failed**: Ensure constructor args match exactly
3. **RPC issues**: Try different Base RPC endpoints if needed

### Alternative RPC URLs:

- `https://base.publicnode.com`
- `https://base.meowrpc.com`
- Alchemy/Infura Base endpoints

## Gas Estimates

Typical deployment costs on Base:

- Contract deployment: ~0.001-0.003 ETH
- Backend authorization: ~0.0001 ETH per backend
- User transactions: ~0.0001-0.0005 ETH per swap

Base has very low gas fees compared to Ethereum mainnet!
