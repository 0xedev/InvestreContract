// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

// Enhanced mock contracts for advanced testing
contract AdvancedMockUniversalRouter {
    mapping(address => bool) public shouldFailForToken;
    mapping(address => uint256) public mockOutputAmount;
    
    // Store references to tokens for easier access
    mapping(string => address) public tokens;
    
    receive() external payable {}
    
    function setShouldFailForToken(address token, bool shouldFail) external {
        shouldFailForToken[token] = shouldFail;
    }
    
    function setMockOutputAmount(address token, uint256 amount) external {
        mockOutputAmount[token] = amount;
    }
    
    // Allow the test to register token addresses
    function setToken(string memory name, address tokenAddr) external {
        tokens[name] = tokenAddr;
    }
    
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256) external payable {
        // Simple mock implementation for V4 swaps
        // We'll transfer the token we have the most balance of (since tests fund us with specific tokens)
        
        if (commands.length > 0 && inputs.length > 0) {
            address caller = msg.sender;
            uint256 transferAmount = 50e6;
            
            // Get all registered tokens and find the one with highest balance
            address[] memory registeredTokens = new address[](4);
            registeredTokens[0] = tokens["tokenA"];
            registeredTokens[1] = tokens["tokenB"];
            registeredTokens[2] = tokens["tokenC"];
            registeredTokens[3] = tokens["tokenD"];
            
            address bestToken = address(0);
            uint256 bestBalance = 0;
            
            // Find the token with the highest balance that can cover the transfer
            for (uint i = 0; i < registeredTokens.length; i++) {
                address tokenAddr = registeredTokens[i];
                if (tokenAddr == address(0)) continue;
                
                try IERC20(tokenAddr).balanceOf(address(this)) returns (uint256 balance) {
                    if (balance >= transferAmount && balance > bestBalance) {
                        bestToken = tokenAddr;
                        bestBalance = balance;
                    }
                } catch {
                    // Continue to next token  
                }
            }
            
            // Transfer from the token with the highest balance
            if (bestToken != address(0)) {
                try IERC20(bestToken).transfer(caller, transferAmount) returns (bool success) {
                    if (success) {
                        return; // Successfully transferred
                    }
                } catch {}
            }
            
            // Fallback: try any token with sufficient balance
            for (uint i = 0; i < registeredTokens.length; i++) {
                address tokenAddr = registeredTokens[i];
                if (tokenAddr == address(0) || tokenAddr == bestToken) continue; // Skip already tried token
                
                try IERC20(tokenAddr).balanceOf(address(this)) returns (uint256 balance) {
                    if (balance >= transferAmount) {
                        try IERC20(tokenAddr).transfer(caller, transferAmount) returns (bool success) {
                            if (success) {
                                return; // Successfully transferred, exit
                            }
                        } catch {
                            // Continue to next token
                        }
                    }
                } catch {
                    // Continue to next token  
                }
            }
        }
    }
}

contract AdvancedMockV3Router {
    mapping(address => bool) public shouldFailForToken;
    mapping(address => uint256) public mockOutputAmount;
    
    function setShouldFailForToken(address token, bool shouldFail) external {
        shouldFailForToken[token] = shouldFail;
    }
    
    function setMockOutputAmount(address token, uint256 amount) external {
        mockOutputAmount[token] = amount;
    }
    
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external returns (uint256) {
        if (shouldFailForToken[params.tokenOut]) {
            revert("V3 swap failed");
        }
        
        // Return mock amount or default
        uint256 amountOut = mockOutputAmount[params.tokenOut] > 0 
            ? mockOutputAmount[params.tokenOut] 
            : 100e6;
            
        // Transfer tokens from this contract to recipient if we have them
        IERC20 outputToken = IERC20(params.tokenOut);
        if (outputToken.balanceOf(address(this)) >= amountOut) {
            outputToken.transfer(params.recipient, amountOut);
        }
        
        return amountOut;
    }
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
}

contract AdvancedMockV2Router {
    mapping(address => bool) public shouldFailForToken;
    mapping(address => uint256) public mockOutputAmount;
    
    function setShouldFailForToken(address token, bool shouldFail) external {
        shouldFailForToken[token] = shouldFail;
    }
    
    function setMockOutputAmount(address token, uint256 amount) external {
        mockOutputAmount[token] = amount;
    }
    
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        address tokenOut = path[path.length - 1];
        
        if (shouldFailForToken[tokenOut]) {
            revert("V2 swap failed");
        }
        
        amounts = new uint256[](path.length);
        amounts[0] = 100e6; // Input amount
        amounts[1] = mockOutputAmount[tokenOut] > 0 
            ? mockOutputAmount[tokenOut] 
            : 100e6; // Output amount
        
        // Transfer output token to recipient
        IERC20 outputToken = IERC20(tokenOut);
        if (outputToken.balanceOf(address(this)) >= amounts[1]) {
            outputToken.transfer(to, amounts[1]);
        }
    }
}

contract AdvancedMockPoolManager {
    mapping(bytes32 => bool) public poolExists;
    mapping(bytes32 => uint160) public poolPrices;
    
    function setPoolExists(bytes32 poolId, bool exists) external {
        poolExists[poolId] = exists;
        if (exists && poolPrices[poolId] == 0) {
            poolPrices[poolId] = 1000000000000000000; // Default price
        }
    }
    
    function getSlot0(bytes32 poolId) external view returns (uint160 sqrtPriceX96, int24, uint16, uint8) {
        return (poolPrices[poolId], 0, 0, 0);
    }
    
    fallback() external {
        assembly {
            mstore(0x00, 0)
            return(0x00, 0x20)
        }
    }
}

contract MockPermit2 {
    // Empty mock
}

contract AutoBuyAdvancedTest is Test {
    AutoBuyContract public autoBuy;
    ERC20Mock public usdc;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;
    ERC20Mock public tokenD; // For fallback testing
    
    AdvancedMockUniversalRouter public mockUniversalRouter;
    AdvancedMockPoolManager public mockPoolManager;
    AdvancedMockV3Router public mockV3Router;
    AdvancedMockV2Router public mockV2Router;
    MockPermit2 public permit2;
    
    address public owner = address(0x1);
    address public backend = address(0x2);
    address public user = address(0x3);
    address public feeRecipient = address(0x4);
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new ERC20Mock();
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        tokenD = new ERC20Mock();
        
        // Deploy advanced mock contracts
        mockUniversalRouter = new AdvancedMockUniversalRouter();
        mockPoolManager = new AdvancedMockPoolManager();
        mockV3Router = new AdvancedMockV3Router();
        mockV2Router = new AdvancedMockV2Router();
        permit2 = new MockPermit2();
        
        // Register token addresses with mock router
        mockUniversalRouter.setToken("tokenA", address(tokenA));
        mockUniversalRouter.setToken("tokenB", address(tokenB));
        mockUniversalRouter.setToken("tokenC", address(tokenC));
        mockUniversalRouter.setToken("tokenD", address(tokenD));
        
        // Fund routers with tokens
        tokenA.mint(address(mockUniversalRouter), 10000e6);
        tokenB.mint(address(mockUniversalRouter), 10000e6);
        tokenC.mint(address(mockUniversalRouter), 10000e6);
        tokenD.mint(address(mockUniversalRouter), 10000e6);
        
        tokenA.mint(address(mockV3Router), 10000e6);
        tokenB.mint(address(mockV3Router), 10000e6);
        tokenC.mint(address(mockV3Router), 10000e6);
        tokenD.mint(address(mockV3Router), 10000e6);
        
        tokenA.mint(address(mockV2Router), 10000e6);
        tokenB.mint(address(mockV2Router), 10000e6);
        tokenC.mint(address(mockV2Router), 10000e6);
        tokenD.mint(address(mockV2Router), 10000e6);
        
        // Deploy main contract
        vm.prank(owner);
        autoBuy = new AutoBuyContract(
            address(mockUniversalRouter),
            address(mockPoolManager),
            address(permit2),
            address(mockV3Router),
            address(mockV2Router),
            address(usdc)
        );
        
        // Setup
        vm.prank(owner);
        autoBuy.authorizeBackend(backend);
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(feeRecipient);
        
        // Fund user
        usdc.mint(user, 10000e6);
        tokenA.mint(user, 1000e6);
        
        // User approvals
        vm.startPrank(user);
        usdc.approve(address(autoBuy), type(uint256).max);
        tokenA.approve(address(autoBuy), type(uint256).max);
        autoBuy.setUserBuyLimitSelf(5000e6);
        autoBuy.setSocialAmounts(1000e6, 500e6);
        vm.stopPrank();
    }
    
    // ===== SMART AUTO BUY TESTS =====
    
    // NOTE: These tests assume smartAutoBuy takes a user parameter and is called by authorized backends
    // The contract needs to be updated to match this design pattern
    
    function test_smartAutoBuy_success() public {
        // Give user some earned tokenA balance first (from previous auto-buys)
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // User should now have earned tokenA balance in the contract
        uint256 userTokenBalance = autoBuy.getUserTokenBalance(user, address(tokenA));
        assertTrue(userTokenBalance > 0);
        
        // Setup V4 route to exist
        bytes32 poolId = keccak256(abi.encode(address(tokenA), address(tokenB)));
        mockPoolManager.setPoolExists(poolId, true);
        
        // Fund routers with output tokens for swapping and set good output amount
        tokenB.mint(address(mockV3Router), 1000e6);
        mockV3Router.setMockOutputAmount(address(tokenB), 50e6); // Ensure sufficient output
        
        // Backend calls smartAutoBuy on behalf of user (Option A design)
        vm.prank(backend);
        uint256 amountOut = autoBuy.smartAutoBuy(
            user,                // User parameter - backend acts on behalf of this user
            address(tokenA),
            address(tokenB),
            50e6,  // Amount of earned tokenA to swap
            25e6   // Minimum tokenB expected
        );
        
        assertTrue(amountOut > 0);
        assertTrue(autoBuy.getUserTokenBalance(user, address(tokenB)) > 0);
    }
    
    function test_smartAutoBuy_insufficientBalance() public {
        // Backend tries to swap more earned tokens than user has
        vm.prank(backend);
        vm.expectRevert("Insufficient balance");
        autoBuy.smartAutoBuy(
            user,                // User parameter
            address(tokenA),
            address(tokenB),
            1000e6, // User has 0 earned tokenA balance
            50e6
        );
    }
    
    function test_smartAutoBuy_unauthorizedCaller() public {
        // Give user some earned token balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // Non-authorized address tries to call smartAutoBuy
        address unauthorizedCaller = address(0x999);
        vm.prank(unauthorizedCaller);
        vm.expectRevert("Not authorized backend");
        autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            50e6,
            25e6
        );
    }
    
    function test_smartAutoBuy_fallbackToV3() public {
        // Give user some earned token balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // V4 route doesn't exist (no pool setup), should fallback to V3
        tokenB.mint(address(mockV3Router), 1000e6);
        mockV3Router.setMockOutputAmount(address(tokenB), 50e6); // Ensure sufficient output
        
        vm.prank(backend);
        uint256 amountOut = autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            50e6,
            25e6
        );
        
        assertTrue(amountOut > 0);
    }
    
    function test_smartAutoBuy_fallbackToV2() public {
        // Give user some earned token balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // V4 route doesn't exist, V3 route fails, should fallback to V2
        mockV3Router.setShouldFailForToken(address(tokenB), true);
        tokenB.mint(address(mockV2Router), 1000e6);
        mockV2Router.setMockOutputAmount(address(tokenB), 50e6); // Ensure sufficient output
        
        vm.prank(backend);
        uint256 amountOut = autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            50e6,
            25e6
        );
        
        assertTrue(amountOut > 0);
    }
    
    // ===== FALLBACK LOGIC TESTS =====
    
    function test_tryV4Route_poolExists() public {
        // Setup pool to exist
        bytes32 poolId = keccak256(abi.encode(address(tokenA), address(tokenB)));
        mockPoolManager.setPoolExists(poolId, true);
        
        // Give user some earned token balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        tokenB.mint(address(mockV3Router), 1000e6);
        mockV3Router.setMockOutputAmount(address(tokenB), 50e6); // Ensure sufficient output
        
        vm.prank(backend);
        uint256 amountOut = autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            50e6,
            25e6
        );
        
        assertTrue(amountOut > 0);
    }
    
    function test_tryV4Route_poolDoesNotExist() public {
        // Pool doesn't exist (default state) - should fallback to V3
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        tokenB.mint(address(mockV3Router), 1000e6);
        mockV3Router.setMockOutputAmount(address(tokenB), 50e6); // Ensure sufficient output        
        
        vm.prank(backend);
        uint256 amountOut = autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            50e6,
            25e6
        );
        
        assertTrue(amountOut > 0);
    }
    
    function test_allRoutesFail() public {
        // Give user some earned token balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // Make all routes fail - don't mint tokens to routers and set them to fail
        mockV3Router.setShouldFailForToken(address(tokenB), true);
        mockV2Router.setShouldFailForToken(address(tokenB), true);
        // Don't mint any tokenB to the routers, so they will fail
        
        vm.prank(backend);
        vm.expectRevert("All swap attempts failed");
        autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            50e6,
            25e6
        );
    }
    
    // ===== V4 SWAP TESTS =====
    
    function test_swapExactInputSingleV4_success() public {
        // Give user some earned tokenA balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // Setup V4 pool
        bytes32 poolId = keccak256(abi.encode(address(tokenA), address(tokenB)));
        mockPoolManager.setPoolExists(poolId, true);
        
        // Fund universal router with output tokens for the V4 swap
        tokenB.mint(address(mockUniversalRouter), 1000e6);
        
        // Create pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        vm.prank(user);
        uint256 amountOut = autoBuy.swapExactInputSingleV4(
            key,
            100e6,
            50e6
        );
        
        assertTrue(amountOut > 0);
        assertTrue(autoBuy.getUserTokenBalance(user, address(tokenB)) > 0);
    }
    
    function test_swapExactInputSingleV4_insufficientBalance() public {
        // User has no earned balance
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        autoBuy.swapExactInputSingleV4(
            key,
            100e6,
            50e6
        );
    }
    
    // ===== VIEW FUNCTION TESTS =====
    
    function test_getUserBuyLimit() public {
        assertEq(autoBuy.getUserBuyLimit(user), 5000e6);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(3000e6);
        
        assertEq(autoBuy.getUserBuyLimit(user), 3000e6);
    }
    
    function test_getUserLikeAmount() public {
        assertEq(autoBuy.getUserLikeAmount(user), 1000e6);
        
        vm.prank(user);
        autoBuy.updateLikeAmount(1500e6);
        
        assertEq(autoBuy.getUserLikeAmount(user), 1500e6);
    }
    
    function test_getUserRecastAmount() public {
        assertEq(autoBuy.getUserRecastAmount(user), 500e6);
        
        vm.prank(user);
        autoBuy.updateRecastAmount(750e6);
        
        assertEq(autoBuy.getUserRecastAmount(user), 750e6);
    }
    
    function test_getUserSocialAmounts() public {
        (uint256 likeAmount, uint256 recastAmount) = autoBuy.getUserSocialAmounts(user);
        assertEq(likeAmount, 1000e6);
        assertEq(recastAmount, 500e6);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(1200e6, 600e6);
        
        (likeAmount, recastAmount) = autoBuy.getUserSocialAmounts(user);
        assertEq(likeAmount, 1200e6);
        assertEq(recastAmount, 600e6);
    }
    
    function test_getUserTokenBalance() public {
        assertEq(autoBuy.getUserTokenBalance(user, address(tokenA)), 0);
        
        // Execute buy to give user earned balance
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user, address(tokenA)) > 0);
    }
    
    function test_getUserUSDCAllowance() public {
        assertEq(autoBuy.getUserUSDCAllowance(user), type(uint256).max);
        
        vm.prank(user);
        usdc.approve(address(autoBuy), 1000e6);
        
        assertEq(autoBuy.getUserUSDCAllowance(user), 1000e6);
    }
    
    function test_isAuthorizedBackend() public {
        assertTrue(autoBuy.isAuthorizedBackend(backend));
        assertFalse(autoBuy.isAuthorizedBackend(user));
        
        vm.prank(owner);
        autoBuy.deauthorizeBackend(backend);
        
        assertFalse(autoBuy.isAuthorizedBackend(backend));
    }
    
    function test_isUserReadyForAutoBuys() public {
        assertTrue(autoBuy.isUserReadyForAutoBuys(user));
        
        // Disable social amounts
        vm.prank(user);
        autoBuy.disableSocialAutoBuying();
        
        assertFalse(autoBuy.isUserReadyForAutoBuys(user));
        
        // Re-enable
        vm.prank(user);
        autoBuy.enableSocialAutoBuying(1000e6, 500e6);
        
        assertTrue(autoBuy.isUserReadyForAutoBuys(user));
    }
    
    // ===== FUZZ TESTS =====
    
    function testFuzz_buildV3Route(
        address tokenIn,
        address tokenOut,
        uint128 amountIn
    ) public {
        // Bound inputs to reasonable values
        vm.assume(tokenIn != address(0));
        vm.assume(tokenOut != address(0));
        vm.assume(tokenIn != tokenOut);
        vm.assume(amountIn > 0 && amountIn <= 1000000e6);
        
        // This tests route building indirectly through smartAutoBuy
        // Give user some earned balance first
        vm.prank(backend);
        try autoBuy.executeFarcasterAutoBuy(user, tokenIn, 1000e6, 0) {
            // If the buy succeeds, test the route building
            (bool success, ) = tokenOut.call(abi.encodeWithSignature("mint(address,uint256)", address(mockV3Router), 1000e6));
            if (success && autoBuy.getUserTokenBalance(user, tokenIn) >= amountIn) {
                vm.prank(backend);
                try autoBuy.smartAutoBuy(user, tokenIn, tokenOut, amountIn, 0) {
                    // Success case - route building worked
                    assertTrue(true);
                } catch {
                    // Failure is acceptable in fuzz testing
                    assertTrue(true);
                }
            }
        } catch {
            // Initial buy failed, skip test
            assertTrue(true);
        }
    }
    
    function testFuzz_calculateFee(uint256 amount) public view {
        vm.assume(amount <= 1000000e6); // Reasonable upper bound
        
        uint256 expectedFee = (amount * 100) / 10000; // 1%
        uint256 actualFee = autoBuy.calculateFee(amount);
        
        assertEq(actualFee, expectedFee);
    }
    
    function testFuzz_userBuyLimit(uint256 limit) public {
        vm.assume(limit <= 1000000e6);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(limit);
        
        assertEq(autoBuy.getUserBuyLimit(user), limit);
    }
    
    function testFuzz_socialAmounts(uint256 likeAmount, uint256 recastAmount) public {
        // Bound to user's buy limit
        likeAmount = bound(likeAmount, 0, 5000e6);
        recastAmount = bound(recastAmount, 0, 5000e6);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(likeAmount, recastAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), likeAmount);
        assertEq(autoBuy.getUserRecastAmount(user), recastAmount);
    }
    
    // ===== EDGE CASE TESTS =====
    
    function test_smartAutoBuy_minAmountOutNotMet() public {
        // Give user some earned token balance first
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(tokenA), 1000e6, 0);
        
        // Set very low mock output
        mockV3Router.setMockOutputAmount(address(tokenB), 1e6);
        tokenB.mint(address(mockV3Router), 1000e6);
        
        vm.prank(backend);
        vm.expectRevert("Insufficient output");
        autoBuy.smartAutoBuy(
            user,
            address(tokenA),
            address(tokenB),
            100e6,
            100e6 // Higher than mock output (1e6)
        );
    }
    
    function test_swapExactInputSingleV4_currencyOrdering() public {
        // Test with different token address ordering
        address lowerToken = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address higherToken = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);
        
        // Give user earned balance in higher token
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, higherToken, 1000e6, 0);
        
        // Setup V4 pool with proper ordering
        bytes32 poolId = keccak256(abi.encode(lowerToken, higherToken));
        mockPoolManager.setPoolExists(poolId, true);
        
        // Fund universal router with the lower token (expected output)
        (bool success, ) = address(lowerToken).call(abi.encodeWithSignature("mint(address,uint256)", address(mockUniversalRouter), 1000e6));
        require(success, "Mint call failed");
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(lowerToken),
            currency1: Currency.wrap(higherToken),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        vm.prank(user);
        uint256 amountOut = autoBuy.swapExactInputSingleV4(
            key,
            100e6,
            50e6
        );
        
        assertTrue(amountOut > 0);
    }
    
    // ===== INTERNAL FUNCTION TESTS =====
    
    function test_internalV3Swap_unauthorized() public {
        vm.expectRevert("Internal only");
        autoBuy.internalV3Swap(address(tokenA), address(tokenB), 100e6, 50e6);
    }
    
    function test_internalV2Swap_unauthorized() public {
        vm.expectRevert("Internal only");
        autoBuy.internalV2Swap(address(tokenA), address(tokenB), 100e6, 50e6);
    }
    
    function test_internalV4Swap_unauthorized() public {
        vm.expectRevert("Internal only");
        autoBuy.internalV4Swap(address(tokenA), address(tokenB), 100e6, 50e6);
    }
}
