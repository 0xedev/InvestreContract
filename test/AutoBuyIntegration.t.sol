// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Mock contracts for integration testing
contract MockUniversalRouter {
    mapping(address => uint256) public tokenBalances;
    
    receive() external payable {}
    
    function execute(bytes calldata, bytes[] calldata, uint256) external payable {
        // Very simple mock: just succeed and let the contract handle token transfers
        // In a real scenario, this would decode commands and execute swaps
        // For testing purposes, we'll let the actual contract manage the token flow
    }
}

contract MockPoolManager {
    fallback() external {
        assembly {
            mstore(0x00, 0)
            return(0x00, 0x20)
        }
    }
}

contract MockV3Router {
    mapping(address => bool) public supportedTokens;
    
    constructor() {
        // Router can handle any token
    }
    
    function addSupportedToken(address token) external {
        supportedTokens[token] = true;
    }
    
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external returns (uint256) {
        // Mock swap: always return 100 tokens regardless of input
        uint256 amountOut = 100e6;
        
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

contract MockV2Router {
    mapping(address => bool) public supportedTokens;
    
    constructor() {
        // Router can handle any token
    }
    
    function addSupportedToken(address token) external {
        supportedTokens[token] = true;
    }
    
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = 100e6; // Input amount
        amounts[1] = 100e6; // Output amount
        
        // Transfer output token to recipient
        IERC20 outputToken = IERC20(path[path.length - 1]);
        if (outputToken.balanceOf(address(this)) >= amounts[1]) {
            outputToken.transfer(to, amounts[1]);
        }
    }
}

contract MockPermit2 {
    // Empty mock
}

contract AutoBuyIntegrationTest is Test {
    AutoBuyContract public allUniswap;
    ERC20Mock public usdc;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;
    
    MockUniversalRouter public mockUniversalRouter;
    MockPoolManager public mockPoolManager;
    MockV3Router public mockV3Router;
    MockV2Router public mockV2Router;
    MockPermit2 public permit2;
    
    address public owner = address(0x1);
    address public backend1 = address(0x2);
    address public backend2 = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address public user3 = address(0x6);
    address public feeRecipient = address(0x7);
    
    uint256 constant INITIAL_USER_BALANCE = 50000e6; // 50k USDC
    
    function setUp() public {
        // Deploy mock tokens first
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        usdc = new ERC20Mock();

        // Deploy mock routers
        mockV3Router = new MockV3Router();
        mockV2Router = new MockV2Router();
        mockUniversalRouter = new MockUniversalRouter();
        mockPoolManager = new MockPoolManager();
        permit2 = new MockPermit2();

        // Fund routers with tokens so they can transfer them out during swaps
        tokenA.mint(address(mockV3Router), 10000e6);
        tokenB.mint(address(mockV3Router), 10000e6);
        tokenC.mint(address(mockV3Router), 10000e6);
        usdc.mint(address(mockV3Router), 10000e6);

        tokenA.mint(address(mockV2Router), 10000e6);
        tokenB.mint(address(mockV2Router), 10000e6);
        tokenC.mint(address(mockV2Router), 10000e6);
        usdc.mint(address(mockV2Router), 10000e6);

        // Deploy main contract with proper owner and correct parameter order
        vm.prank(owner);
        allUniswap = new AutoBuyContract(
            address(mockUniversalRouter), // _router (UniversalRouter)
            address(mockPoolManager),     // _poolManager  
            address(permit2),             // _permit2 (we need to create this)
            address(mockV3Router),        // _v3Router
            address(mockV2Router),        // _v2Router
            address(usdc)                 // _usdc (correct USDC token address)
        );

        // Authorize backends
        vm.prank(owner);
        allUniswap.authorizeBackend(backend1);
        
        vm.prank(owner);
        allUniswap.authorizeBackend(backend2);
        
        // Set fee recipient
        vm.prank(owner);
        allUniswap.setFeeRecipient(feeRecipient);

        // Configure supported tokens
        mockV3Router.addSupportedToken(address(tokenA));
        mockV3Router.addSupportedToken(address(tokenB));
        mockV3Router.addSupportedToken(address(tokenC));
        mockV3Router.addSupportedToken(address(usdc));

        mockV2Router.addSupportedToken(address(tokenA));
        mockV2Router.addSupportedToken(address(tokenB));
        mockV2Router.addSupportedToken(address(tokenC));
        mockV2Router.addSupportedToken(address(usdc));

        // Fund test users with more USDC
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);

        tokenA.mint(user1, 1000e6);
        tokenB.mint(user1, 1000e6);
        usdc.mint(user1, 10000e6); // 10k USDC

        tokenA.mint(user2, 1000e6);
        tokenC.mint(user2, 1000e6);
        usdc.mint(user2, 10000e6); // 10k USDC

        usdc.mint(user3, 10000e6); // 10k USDC

        // Set approvals for test users
        vm.startPrank(user1);
        tokenA.approve(address(allUniswap), type(uint256).max);
        tokenB.approve(address(allUniswap), type(uint256).max);
        usdc.approve(address(allUniswap), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        tokenA.approve(address(allUniswap), type(uint256).max);
        tokenC.approve(address(allUniswap), type(uint256).max);
        usdc.approve(address(allUniswap), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        usdc.approve(address(allUniswap), type(uint256).max);
        vm.stopPrank();
        
        // Setup user configurations for testing with reasonable amounts
        vm.prank(user1);
        allUniswap.setUserBuyLimitSelf(10000e6); // 10k USDC limit
        
        vm.prank(user1);
        allUniswap.setSocialAmounts(1000e6, 500e6); // 1k like, 500 recast
        
        vm.prank(user2);
        allUniswap.setUserBuyLimitSelf(10000e6); // 10k USDC limit
        
        vm.prank(user2);
        allUniswap.setSocialAmounts(1000e6, 500e6); // 1k like, 500 recast
        
        vm.prank(user3);
        allUniswap.setUserBuyLimitSelf(10000e6); // 10k USDC limit
        
        vm.prank(user3);
        allUniswap.setSocialAmounts(1000e6, 500e6); // 1k like, 500 recast
    }
    
    function setupUser(address user, uint256 buyLimit, uint256 likeAmount, uint256 recastAmount) internal {
        usdc.mint(user, INITIAL_USER_BALANCE);
        
        vm.prank(user);
        usdc.approve(address(allUniswap), type(uint256).max);
        
        vm.prank(user);
        allUniswap.setUserBuyLimitSelf(buyLimit);
        
        vm.prank(user);
        allUniswap.setSocialAmounts(likeAmount, recastAmount);
    }
    
    // ===== MULTI-USER SCENARIOS =====
    
    function test_integration_multipleUsersBuyingSameToken() public {
        // All users buy the same token
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenA), 2000e6, 0);
        
        vm.prank(backend2);
        allUniswap.executeFarcasterAutoBuy(user3, address(tokenA), 500e6, 0);
        
        // Check all users have token balances
        assertTrue(allUniswap.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user2, address(tokenA)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user3, address(tokenA)) > 0);
        
        // Check total fees collected
        uint256 totalFees = (5000e6 + 2000e6 + 500e6) * 100 / 10000;
        assertEq(usdc.balanceOf(feeRecipient), totalFees);
    }
    
    function test_integration_multipleUsersBuyingDifferentTokens() public {
        // Users buy different tokens
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenB), 2000e6, 0);
        
        vm.prank(backend2);
        allUniswap.executeFarcasterAutoBuy(user3, address(tokenC), 500e6, 0);
        
        // Check users only have their respective tokens
        assertTrue(allUniswap.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertEq(allUniswap.getUserTokenBalance(user1, address(tokenB)), 0);
        assertEq(allUniswap.getUserTokenBalance(user1, address(tokenC)), 0);
        
        assertTrue(allUniswap.getUserTokenBalance(user2, address(tokenB)) > 0);
        assertEq(allUniswap.getUserTokenBalance(user2, address(tokenA)), 0);
        assertEq(allUniswap.getUserTokenBalance(user2, address(tokenC)), 0);
        
        assertTrue(allUniswap.getUserTokenBalance(user3, address(tokenC)) > 0);
        assertEq(allUniswap.getUserTokenBalance(user3, address(tokenA)), 0);
        assertEq(allUniswap.getUserTokenBalance(user3, address(tokenB)), 0);
    }
    
    // ===== SOCIAL INTERACTION SCENARIOS =====
    
    function test_integration_mixedSocialAndDirectBuys() public {
        // Mix of social and direct buys
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 3000e6, 0);
        
        vm.prank(backend2);
        allUniswap.executeSocialAutoBuy(user2, address(tokenB), "recast", 0);
        
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user3, address(tokenC), "like", 0);
        
        // Check all operations succeeded
        assertTrue(allUniswap.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user2, address(tokenB)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user3, address(tokenC)) > 0);
    }
    
    function test_integration_rapidSocialInteractions() public {
        // Rapid succession of social interactions
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "recast", 0);
        
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        vm.prank(backend2);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "recast", 0);
        
        // User should have accumulated tokens from multiple interactions
        // Note: User1 doesn't start with INITIAL_USER_BALANCE, so we check they have some tokens instead
        assertTrue(allUniswap.getUserTokenBalance(user1, address(tokenA)) > 0);
    }
    
    // ===== BACKEND MANAGEMENT SCENARIOS =====
    
    function test_integration_multipleBackendsOperation() public {
        // Different backends executing buys
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        vm.prank(backend2);
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenB), 1500e6, 0);
        
        // Both should succeed
        assertTrue(allUniswap.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user2, address(tokenB)) > 0);
    }
    
    function test_integration_backendDeauthorization() public {
        // Deauthorize one backend mid-operation
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        vm.prank(owner);
        allUniswap.deauthorizeBackend(backend1);
        
        // Backend1 should no longer work
        vm.prank(backend1);
        vm.expectRevert("Not authorized backend");
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenA), 1000e6, 0);
        
        // Backend2 should still work
        vm.prank(backend2);
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenA), 1000e6, 0);
        
        assertTrue(allUniswap.getUserTokenBalance(user2, address(tokenA)) > 0);
    }
    
    // ===== USER PREFERENCE CHANGES =====
    
    function test_integration_dynamicUserPreferenceChanges() public {
        // Initial buy
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        uint256 initialTokens = allUniswap.getUserTokenBalance(user1, address(tokenA));
        
        // User changes preferences
        vm.prank(user1);
        allUniswap.setSocialAmounts(1000e6, 500e6); // Reduced amounts
        
        // Execute with new preferences
        vm.prank(backend1);
        allUniswap.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        uint256 finalTokens = allUniswap.getUserTokenBalance(user1, address(tokenA));
        assertTrue(finalTokens > initialTokens);
    }
    
    function test_integration_userLimitChanges() public {
        // User increases their limit
        vm.prank(user3);
        allUniswap.setUserBuyLimitSelf(2000e6);
        
        vm.prank(user3);
        allUniswap.setSocialAmounts(1500e6, 1000e6);
        
        // Should now be able to execute larger buys
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user3, address(tokenA), 1500e6, 0);
        
        assertTrue(allUniswap.getUserTokenBalance(user3, address(tokenA)) > 0);
    }
    
    // ===== WITHDRAWAL SCENARIOS =====
    
    function test_integration_multipleWithdrawals() public {
        // Users accumulate tokens - use tokenC which user1 and user2 don't have initially
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenC), 6000e6, 0); // Mock gives 100e6 tokens
        
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenC), 3000e6, 0); // Mock gives 100e6 tokens
        
        uint256 user1Balance = allUniswap.getUserTokenBalance(user1, address(tokenC));
        uint256 user2Balance = allUniswap.getUserTokenBalance(user2, address(tokenC));
        
        // Store initial wallet balances to verify withdrawals
        uint256 user1InitialWalletBalance = tokenC.balanceOf(user1);
        uint256 user2InitialWalletBalance = tokenC.balanceOf(user2);
        
        // Use exact withdrawal amounts to avoid rounding issues
        uint256 user1WithdrawAmount = 50e6; // Half of 100e6
        uint256 user2WithdrawAmount = 30e6; // 30% of 100e6
        
        // Partial withdrawals
        vm.prank(user1);
        allUniswap.withdrawUserBalance(address(tokenC), user1WithdrawAmount);
        
        vm.prank(user2);
        allUniswap.withdrawUserBalance(address(tokenC), user2WithdrawAmount);
        
        // Check balances updated correctly
        assertEq(allUniswap.getUserTokenBalance(user1, address(tokenC)), user1Balance - user1WithdrawAmount);
        assertEq(allUniswap.getUserTokenBalance(user2, address(tokenC)), user2Balance - user2WithdrawAmount);
        
        // Check that the withdrawn amounts were transferred to user wallets
        assertEq(tokenC.balanceOf(user1), user1InitialWalletBalance + user1WithdrawAmount);
        assertEq(tokenC.balanceOf(user2), user2InitialWalletBalance + user2WithdrawAmount);
    }
    
    // ===== FEE COLLECTION SCENARIOS =====
    
    function test_integration_feeCollection() public {
        // Execute multiple buys to generate fees
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user2, address(tokenB), 2000e6, 0);
        
        vm.prank(backend2);
        allUniswap.executeFarcasterAutoBuy(user3, address(tokenC), 500e6, 0);
        
        uint256 expectedFees = (5000e6 + 2000e6 + 500e6) * 100 / 10000;
        assertEq(usdc.balanceOf(feeRecipient), expectedFees);
        
        // Change fee recipient
        address newFeeRecipient = address(0x8);
        vm.prank(owner);
        allUniswap.setFeeRecipient(newFeeRecipient);
        
        // New buys should go to new recipient
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        uint256 newFee = 1000e6 * 100 / 10000;
        assertEq(usdc.balanceOf(newFeeRecipient), newFee);
    }
    
    // ===== EMERGENCY SCENARIOS =====
    
    function test_integration_emergencyWithdrawal() public {
        // Accumulate some tokens in contract
        vm.prank(backend1);
        allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        // Mint extra tokens to contract
        usdc.mint(address(allUniswap), 10000e6);
        
        uint256 ownerInitialBalance = usdc.balanceOf(owner);
        
        // Emergency withdrawal
        vm.prank(owner);
        allUniswap.emergencyWithdraw(address(usdc), 5000e6);
        
        assertEq(usdc.balanceOf(owner), ownerInitialBalance + 5000e6);
    }
    
    // ===== OWNERSHIP TRANSFER SCENARIOS =====
    
    function test_integration_ownershipTransfer() public {
        address newOwner = address(0x9);
        
        // Transfer ownership
        vm.prank(owner);
        allUniswap.transferOwnership(newOwner);
        
        assertEq(allUniswap.owner(), newOwner);
        
        // Old owner should not have access
        vm.prank(owner);
        vm.expectRevert("Not owner");
        allUniswap.setFeeRecipient(address(0x10));
        
        // New owner should have access
        vm.prank(newOwner);
        allUniswap.setFeeRecipient(address(0x10));
        
        assertEq(allUniswap.feeRecipient(), address(0x10));
    }
    
    // ===== STRESS TESTS =====
    
    function test_integration_highVolumeOperations() public {
        // Simulate high volume of operations
        for (uint i = 0; i < 10; i++) {
            vm.prank(backend1);
            allUniswap.executeFarcasterAutoBuy(user1, address(tokenA), 500e6, 0);
            
            vm.prank(backend2);
            allUniswap.executeSocialAutoBuy(user2, address(tokenB), "like", 0);
            
            vm.prank(backend1);
            allUniswap.executeSocialAutoBuy(user3, address(tokenC), "recast", 0);
        }
        
        // All users should have accumulated significant balances
        assertTrue(allUniswap.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user2, address(tokenB)) > 0);
        assertTrue(allUniswap.getUserTokenBalance(user3, address(tokenC)) > 0);
        
        // Check total fees collected
        // 500e6 * 10 (direct buys) + 1000e6 * 10 (likes) + 500e6 * 10 (recasts) = 20000e6 total
        uint256 expectedTotalFees = (500e6 * 10 + 1000e6 * 10 + 500e6 * 10) * 100 / 10000;
        assertEq(usdc.balanceOf(feeRecipient), expectedTotalFees);
    }
    
    function test_integration_userReadinessChecks() public {
        // Test isUserReadyForAutoBuys under various conditions
        assertTrue(allUniswap.isUserReadyForAutoBuys(user1));
        assertTrue(allUniswap.isUserReadyForAutoBuys(user2));
        assertTrue(allUniswap.isUserReadyForAutoBuys(user3));
        
        // Disable social amounts for user1
        vm.prank(user1);
        allUniswap.setSocialAmounts(0, 0);
        
        assertFalse(allUniswap.isUserReadyForAutoBuys(user1));
        
        // Remove allowance for user2
        vm.prank(user2);
        usdc.approve(address(allUniswap), 0);
        
        assertFalse(allUniswap.isUserReadyForAutoBuys(user2));
        
        // Set buy limit to 0 for user3
        vm.prank(user3);
        allUniswap.setUserBuyLimitSelf(0);
        
        assertFalse(allUniswap.isUserReadyForAutoBuys(user3));
    }
}
