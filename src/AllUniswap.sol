// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UniversalRouter } from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
// ADD ADDITIONAL IMPORTS FOR V2/V3:
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract AutoBuyContract is ReentrancyGuard {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
//BASE MAINNET
    UniversalRouter public immutable router; //0x6ff5693b99212da76ad316178a184ab56d299b43
    IPoolManager public immutable poolManager;//0x498581ff718922c3f8e6a244956af099b2652b2b
    IPermit2 public immutable permit2;//0x000000000022D473030F116dDEE9F6B43aC78BA3
    ISwapRouter public immutable v3Router;
    IUniswapV2Router02 public immutable v2Router;//0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24
  
    // Track earned tokens per user (from auto-buys)
    mapping(address => mapping(address => uint256)) public userTokenBalances; // user => token => balance
    mapping(address => bool) public authorizedBackends; // Backend wallets that can trigger buys
    mapping(address => uint256) public userBuyLimits; // Max USDC per single buy per user
    
    // Social interaction buy amounts
    mapping(address => uint256) public userLikeAmounts; // USDC amount per like
    mapping(address => uint256) public userRecastAmounts; // USDC amount per recast
    
    address public owner;
    address public feeRecipient;
    address public immutable USDC; // Main token for purchases
    uint256 public constant FEE_BASIS_POINTS = 100; // 1% fee
    uint256 public constant BASIS_POINTS = 10000;

    event AutoBuyExecuted(address indexed user, address indexed tokenOut, uint256 usdcAmount, uint256 tokenAmount, uint256 fee);
    event FeeCollected(address indexed token, uint256 amount);
    event UserLimitSet(address indexed user, uint256 newLimit);
    event UserSocialAmountsSet(address indexed user, uint256 likeAmount, uint256 recastAmount);

    constructor(
        address _router, 
        address _poolManager, 
        address _permit2,
        address _v3Router,
        address _v2Router,
        address _usdc
    ) {
        router = UniversalRouter(payable(_router));
        poolManager = IPoolManager(_poolManager);
        permit2 = IPermit2(_permit2);
        v3Router = ISwapRouter(_v3Router);
        v2Router = IUniswapV2Router02(_v2Router);
        USDC = _usdc;
        owner = msg.sender;
        feeRecipient = msg.sender;
        
        // Automatically authorize deployer as backend wallet
        authorizedBackends[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedBackends[msg.sender], "Not authorized backend");
        _;
    }

    function authorizeBackend(address backend) external onlyOwner {
        authorizedBackends[backend] = true;
    }

    function deauthorizeBackend(address backend) external onlyOwner {
        authorizedBackends[backend] = false;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }

    function setUserBuyLimit(address user, uint256 limitUSDC) external onlyOwner {
        userBuyLimits[user] = limitUSDC;
        emit UserLimitSet(user, limitUSDC);
    }

    function setUserBuyLimitSelf(uint256 limitUSDC) external {
        userBuyLimits[msg.sender] = limitUSDC;
        emit UserLimitSet(msg.sender, limitUSDC);
    }

    // User sets their social interaction amounts
    function setSocialAmounts(uint256 likeAmount, uint256 recastAmount) external {
        require(likeAmount <= userBuyLimits[msg.sender], "Like amount exceeds buy limit");
        require(recastAmount <= userBuyLimits[msg.sender], "Recast amount exceeds buy limit");
        
        userLikeAmounts[msg.sender] = likeAmount;
        userRecastAmounts[msg.sender] = recastAmount;
        emit UserSocialAmountsSet(msg.sender, likeAmount, recastAmount);
    }

    // Update just like amount
    function updateLikeAmount(uint256 newLikeAmount) external {
        require(newLikeAmount <= userBuyLimits[msg.sender], "Like amount exceeds buy limit");
        
        userLikeAmounts[msg.sender] = newLikeAmount;
        emit UserSocialAmountsSet(msg.sender, newLikeAmount, userRecastAmounts[msg.sender]);
    }

    // Update just recast amount  
    function updateRecastAmount(uint256 newRecastAmount) external {
        require(newRecastAmount <= userBuyLimits[msg.sender], "Recast amount exceeds buy limit");
        
        userRecastAmounts[msg.sender] = newRecastAmount;
        emit UserSocialAmountsSet(msg.sender, userLikeAmounts[msg.sender], newRecastAmount);
    }

    // Disable social auto-buying (set both amounts to 0)
    function disableSocialAutoBuying() external {
        userLikeAmounts[msg.sender] = 0;
        userRecastAmounts[msg.sender] = 0;
        emit UserSocialAmountsSet(msg.sender, 0, 0);
    }

    // Enable social auto-buying with specific amounts
    function enableSocialAutoBuying(uint256 likeAmount, uint256 recastAmount) external {
        require(likeAmount <= userBuyLimits[msg.sender], "Like amount exceeds buy limit");
        require(recastAmount <= userBuyLimits[msg.sender], "Recast amount exceeds buy limit");
        
        userLikeAmounts[msg.sender] = likeAmount;
        userRecastAmounts[msg.sender] = recastAmount;
        emit UserSocialAmountsSet(msg.sender, likeAmount, recastAmount);
    }

    // Convenience function to set everything at once
    function setUserPreferences(
        uint256 buyLimit,
        uint256 likeAmount, 
        uint256 recastAmount
    ) external {
        require(likeAmount <= buyLimit, "Like amount exceeds buy limit");
        require(recastAmount <= buyLimit, "Recast amount exceeds buy limit");
        
        userBuyLimits[msg.sender] = buyLimit;
        userLikeAmounts[msg.sender] = likeAmount;
        userRecastAmounts[msg.sender] = recastAmount;
        
        emit UserLimitSet(msg.sender, buyLimit);
        emit UserSocialAmountsSet(msg.sender, likeAmount, recastAmount);
    }

    function calculateFee(uint256 amount) public pure returns (uint256) {
        return (amount * FEE_BASIS_POINTS) / BASIS_POINTS;
    }

    // Main function for Farcaster-triggered auto-buys
    function executeFarcasterAutoBuy(
        address user,
        address tokenOut,
        uint256 usdcAmount,
        uint256 minAmountOut
    ) public onlyAuthorized nonReentrant returns (uint256 amountOut) {
        // Check user has set a buy limit and this buy doesn't exceed it
        require(userBuyLimits[user] > 0, "User has not set buy limit");
        require(usdcAmount <= userBuyLimits[user], "Buy amount exceeds user limit");
        
        // Check allowance before proceeding
        uint256 allowance = IERC20(USDC).allowance(user, address(this));
        require(allowance >= usdcAmount, "Insufficient USDC allowance");
        
        // Calculate fee
        uint256 fee = calculateFee(usdcAmount);
        uint256 swapAmount = usdcAmount - fee;
        
        // Transfer USDC from user to contract at execution time
        IERC20(USDC).transferFrom(user, address(this), usdcAmount);

        // Transfer fee to recipient
        IERC20(USDC).transfer(feeRecipient, fee);
        emit FeeCollected(USDC, fee);

        // Get balance before swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // Smart routing: try V4 -> V3 -> V2
        bool success = false;
        
        if (tryV4Route(USDC, tokenOut)) {
            success = executeV4Swap(USDC, tokenOut, uint128(swapAmount), uint128(minAmountOut));
        }
        
        if (!success && tryV3Route(USDC, tokenOut)) {
            success = executeV3Swap(USDC, tokenOut, uint128(swapAmount), uint128(minAmountOut));
        }
        
        if (!success) {
            success = executeV2Swap(USDC, tokenOut, uint128(swapAmount), uint128(minAmountOut));
        }
        
        require(success, "All swap attempts failed");

        // Calculate actual output
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= minAmountOut, "Insufficient output");
        
        // Add output tokens to user's earned balance
        userTokenBalances[user][tokenOut] += amountOut;
        emit AutoBuyExecuted(user, tokenOut, usdcAmount, amountOut, fee);
        
        return amountOut;
    }

    // Specialized function for social interactions - backend reads user's preferences
    function executeSocialAutoBuy(
        address user,
        address tokenOut,
        string calldata interactionType, // "like" or "recast"
        uint256 minAmountOut
    ) external onlyAuthorized returns (uint256 amountOut) {
        uint256 usdcAmount;
        
        // Get user's configured amount for this interaction type
        if (keccak256(abi.encodePacked(interactionType)) == keccak256(abi.encodePacked("like"))) {
            usdcAmount = userLikeAmounts[user];
            require(usdcAmount > 0, "User has not set like amount");
        } else if (keccak256(abi.encodePacked(interactionType)) == keccak256(abi.encodePacked("recast"))) {
            usdcAmount = userRecastAmounts[user];
            require(usdcAmount > 0, "User has not set recast amount");
        } else {
            revert("Invalid interaction type");
        }
        
        // Execute the auto-buy with user's configured amount
        return executeFarcasterAutoBuy(user, tokenOut, usdcAmount, minAmountOut);
    }

    // Alternative: Backend-controlled amounts (for advanced users who opt-in)
    function executeSocialAutoBuyWithAmount(
        address user,
        address tokenOut,
        uint256 usdcAmount,
        uint256 minAmountOut
    ) external onlyAuthorized returns (uint256 amountOut) {
        // Must be within user's buy limit
        require(usdcAmount <= userBuyLimits[user], "Amount exceeds user limit");
        
        // Execute the auto-buy with backend-specified amount
        return executeFarcasterAutoBuy(user, tokenOut, usdcAmount, minAmountOut);
    }

    // V4 Swap Function for users to manually swap their earned tokens
    function swapExactInputSingleV4(
        PoolKey calldata key,
        uint128 amountIn,
        uint128 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        // Determine input and output tokens based on the pool key
        address inputToken;
        address outputToken;
        
        // For this function, we need to determine which currency is the input
        // Check user's balance for both currencies to determine input token
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        
        if (userTokenBalances[msg.sender][currency0] >= amountIn) {
            inputToken = currency0;
            outputToken = currency1;
        } else if (userTokenBalances[msg.sender][currency1] >= amountIn) {
            inputToken = currency1;
            outputToken = currency0;
        } else {
            revert("Insufficient balance");
        }
        
        // Calculate fee
        uint256 fee = calculateFee(amountIn);
        uint256 swapAmount = amountIn - fee;
        
        userTokenBalances[msg.sender][inputToken] -= amountIn;

        // Transfer fee to recipient
        IERC20(inputToken).transfer(feeRecipient, fee);
        emit FeeCollected(inputToken, fee);

        // Get balance before swap
        uint256 balanceBefore = IERC20(outputToken).balanceOf(address(this));

        // Execute the actual swap
        bool success = executeV4Swap(inputToken, outputToken, uint128(swapAmount), minAmountOut);
        require(success, "V4 swap failed");

        // Calculate actual output
        uint256 balanceAfter = IERC20(outputToken).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= minAmountOut, "Insufficient output amount");
        
        // Add output tokens to user's balance
        userTokenBalances[msg.sender][outputToken] += amountOut;
        
        emit AutoBuyExecuted(msg.sender, outputToken, amountIn, amountOut, fee);
        return amountOut;
    }

    // Smart routing function - tries V4 first, falls back to V3/V2
    function smartAutoBuy(
        address user,
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) external onlyAuthorized nonReentrant returns (uint256 amountOut) {
        require(userTokenBalances[user][tokenIn] >= amountIn, "Insufficient balance");
        
        // Calculate fee
        uint256 fee = calculateFee(amountIn);
        uint256 swapAmount = amountIn - fee;
        
        userTokenBalances[user][tokenIn] -= amountIn;

        // Transfer fee to recipient
        IERC20(tokenIn).transfer(feeRecipient, fee);
        emit FeeCollected(tokenIn, fee);

        // Get balance before swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // Smart routing: try V4 -> V3 -> V2
        bool success = false;
        
        if (tryV4Route(tokenIn, tokenOut)) {
            success = executeV4Swap(tokenIn, tokenOut, uint128(swapAmount), minAmountOut);
        }
        
        if (!success && tryV3Route(tokenIn, tokenOut)) {
            success = executeV3Swap(tokenIn, tokenOut, uint128(swapAmount), minAmountOut);
        }
        
        if (!success) {
            success = executeV2Swap(tokenIn, tokenOut, uint128(swapAmount), minAmountOut);
        }
        
        require(success, "All swap attempts failed");

        // Calculate actual output
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= minAmountOut, "Insufficient output");
        
        // Add output tokens to user's balance
        userTokenBalances[user][tokenOut] += amountOut;
        emit AutoBuyExecuted(user, tokenOut, amountIn, amountOut, fee);
        
        return amountOut;
    }

    function tryV4Route(address tokenIn, address tokenOut) internal view returns (bool) {
        // Ensure proper token ordering
        (Currency currency0, Currency currency1) = tokenIn < tokenOut 
            ? (Currency.wrap(tokenIn), Currency.wrap(tokenOut))
            : (Currency.wrap(tokenOut), Currency.wrap(tokenIn));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        return sqrtPriceX96 != 0;
    }

    function tryV3Route(address tokenIn, address tokenOut) internal pure returns (bool) {
        // In production, you would query V3 factory for pool existence
        // For now, we assume most major tokens have V3 pools
        return tokenIn != address(0) && tokenOut != address(0);
    }

    // Individual swap execution functions
    function executeV4Swap(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal returns (bool) {
        try this.internalV4Swap(tokenIn, tokenOut, amountIn, minAmountOut) {
            return true;
        } catch {
            return false;
        }
    }

    function internalV4Swap(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) external {
        require(msg.sender == address(this), "Internal only");
        
        // Approve Universal Router
        IERC20(tokenIn).approve(address(router), amountIn);
        
        // Build and execute V4 swap
        (bytes memory commands, bytes[] memory inputs) = buildV4Route(tokenIn, tokenOut, amountIn, minAmountOut);
        router.execute(commands, inputs, block.timestamp + 300);
    }

    function executeV3Swap(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal returns (bool) {
        try this.internalV3Swap(tokenIn, tokenOut, amountIn, minAmountOut) {
            return true;
        } catch {
            return false;
        }
    }

    function internalV3Swap(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) external {
        require(msg.sender == address(this), "Internal only");
        
        // Approve V3 router
        IERC20(tokenIn).approve(address(v3Router), amountIn);
        
        // Execute V3 swap directly
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000, // 0.3%
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        
        v3Router.exactInputSingle(params);
    }

    function executeV2Swap(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal returns (bool) {
        try this.internalV2Swap(tokenIn, tokenOut, amountIn, minAmountOut) {
            return true;
        } catch {
            return false;
        }
    }

    function internalV2Swap(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) external {
        require(msg.sender == address(this), "Internal only");
        
        // Approve V2 router
        IERC20(tokenIn).approve(address(v2Router), amountIn);
        
        // Build path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        // Execute V2 swap
        v2Router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        );
    }

    function buildV4Route(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal pure returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(0x10)); // V4_SWAP command
        inputs = new bytes[](1);
        
        // Ensure proper token ordering
        (Currency currency0, Currency currency1) = tokenIn < tokenOut 
            ? (Currency.wrap(tokenIn), Currency.wrap(tokenOut))
            : (Currency.wrap(tokenOut), Currency.wrap(tokenIn));
        
        bool zeroForOne = tokenIn < tokenOut;
        
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, minAmountOut);

        inputs[0] = abi.encode(actions, params);
    }

    function buildV3Route(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs = new bytes[](1);
        
        // Build V3 path: tokenIn -> fee -> tokenOut
        bytes memory path = abi.encodePacked(tokenIn, uint24(3000), tokenOut);
        
        inputs[0] = abi.encode(
            address(this), // recipient
            amountIn,
            minAmountOut,
            path,
            false // payerIsUser
        );
    }

    function buildV2Route(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(Commands.V2_SWAP_EXACT_IN));
        inputs = new bytes[](1);
        
        // Build V2 path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        inputs[0] = abi.encode(
            address(this), // recipient
            amountIn,
            minAmountOut,
            path,
            false // payerIsUser
        );
    }

    // Emergency functions
    function withdrawUserBalance(address token, uint256 amount) external nonReentrant {
        require(userTokenBalances[msg.sender][token] >= amount, "Insufficient balance");
        userTokenBalances[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
    }

    function withdrawFees(address token) external onlyOwner nonReentrant {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No fees to withdraw");
        IERC20(token).transfer(feeRecipient, balance);
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner nonReentrant {
        IERC20(token).transfer(owner, amount);
    }

    // View functions
    function getUserTokenBalance(address user, address token) external view returns (uint256) {
        return userTokenBalances[user][token];
    }

    function getUserUSDCAllowance(address user) external view returns (uint256) {
        return IERC20(USDC).allowance(user, address(this));
    }

    function getUserBuyLimit(address user) external view returns (uint256) {
        return userBuyLimits[user];
    }

    function getUserLikeAmount(address user) external view returns (uint256) {
        return userLikeAmounts[user];
    }

    function getUserRecastAmount(address user) external view returns (uint256) {
        return userRecastAmounts[user];
    }

    function getUserSocialAmounts(address user) external view returns (uint256 likeAmount, uint256 recastAmount) {
        return (userLikeAmounts[user], userRecastAmounts[user]);
    }

    function isAuthorizedBackend(address backend) external view returns (bool) {
        return authorizedBackends[backend];
    }

    // Check if user is ready for auto-buys
    function isUserReadyForAutoBuys(address user) external view returns (bool) {
        return userBuyLimits[user] > 0 && 
               IERC20(USDC).allowance(user, address(this)) > 0 &&
               (userLikeAmounts[user] > 0 || userRecastAmounts[user] > 0);
    }
}
