// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AutoBuyIntegrationTest is Test {
    AutoBuyContract public autoBuy;
    ERC20Mock public usdc;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;
    
    address public owner = address(0x1);
    address public backend1 = address(0x2);
    address public backend2 = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address public user3 = address(0x6);
    address public feeRecipient = address(0x7);
    
    uint256 constant INITIAL_USER_BALANCE = 50000e6; // 50k USDC
    
    function setUp() public {
        // Deploy tokens
        usdc = new ERC20Mock();
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        
        // Deploy AutoBuyContract
        vm.prank(owner);
        autoBuy = new AutoBuyContract(
            address(0x100), // Mock router
            address(0x101), // Mock pool manager
            address(0x102), // Mock permit2
            address(0x103), // Mock V3 router
            address(0x104), // Mock V2 router
            address(usdc)
        );
        
        // Setup contract
        vm.prank(owner);
        autoBuy.authorizeBackend(backend1);
        
        vm.prank(owner);
        autoBuy.authorizeBackend(backend2);
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(feeRecipient);
        
        // Setup users
        setupUser(user1, 10000e6, 5000e6, 2500e6); // High limits
        setupUser(user2, 5000e6, 2500e6, 1000e6);  // Medium limits
        setupUser(user3, 1000e6, 500e6, 250e6);    // Low limits
        
        // Mint target tokens to contract for swaps
        tokenA.mint(address(autoBuy), 1000000e18);
        tokenB.mint(address(autoBuy), 1000000e18);
        tokenC.mint(address(autoBuy), 1000000e18);
    }
    
    function setupUser(address user, uint256 buyLimit, uint256 likeAmount, uint256 recastAmount) internal {
        usdc.mint(user, INITIAL_USER_BALANCE);
        
        vm.prank(user);
        usdc.approve(address(autoBuy), type(uint256).max);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(buyLimit);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(likeAmount, recastAmount);
    }
    
    // ===== MULTI-USER SCENARIOS =====
    
    function test_integration_multipleUsersBuyingSameToken() public {
        // All users buy the same token
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenA), 2000e6, 0);
        
        vm.prank(backend2);
        autoBuy.executeFarcasterAutoBuy(user3, address(tokenA), 500e6, 0);
        
        // Check all users have token balances
        assertTrue(autoBuy.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user2, address(tokenA)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user3, address(tokenA)) > 0);
        
        // Check total fees collected
        uint256 totalFees = (5000e6 + 2000e6 + 500e6) * 100 / 10000;
        assertEq(usdc.balanceOf(feeRecipient), totalFees);
    }
    
    function test_integration_multipleUsersBuyingDifferentTokens() public {
        // Users buy different tokens
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenB), 2000e6, 0);
        
        vm.prank(backend2);
        autoBuy.executeFarcasterAutoBuy(user3, address(tokenC), 500e6, 0);
        
        // Check users only have their respective tokens
        assertTrue(autoBuy.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertEq(autoBuy.getUserTokenBalance(user1, address(tokenB)), 0);
        assertEq(autoBuy.getUserTokenBalance(user1, address(tokenC)), 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user2, address(tokenB)) > 0);
        assertEq(autoBuy.getUserTokenBalance(user2, address(tokenA)), 0);
        assertEq(autoBuy.getUserTokenBalance(user2, address(tokenC)), 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user3, address(tokenC)) > 0);
        assertEq(autoBuy.getUserTokenBalance(user3, address(tokenA)), 0);
        assertEq(autoBuy.getUserTokenBalance(user3, address(tokenB)), 0);
    }
    
    // ===== SOCIAL INTERACTION SCENARIOS =====
    
    function test_integration_mixedSocialAndDirectBuys() public {
        // Mix of social and direct buys
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 3000e6, 0);
        
        vm.prank(backend2);
        autoBuy.executeSocialAutoBuy(user2, address(tokenB), "recast", 0);
        
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user3, address(tokenC), "like", 0);
        
        // Check all operations succeeded
        assertTrue(autoBuy.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user2, address(tokenB)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user3, address(tokenC)) > 0);
    }
    
    function test_integration_rapidSocialInteractions() public {
        // Rapid succession of social interactions
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "recast", 0);
        
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        vm.prank(backend2);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "recast", 0);
        
        // User should have accumulated tokens from multiple interactions
        uint256 expectedSpent = (5000e6 + 2500e6) * 2; // like + recast amounts × 2 iterations
        uint256 actualSpent = INITIAL_USER_BALANCE - usdc.balanceOf(user1);
        assertEq(actualSpent, expectedSpent);
    }
    
    // ===== BACKEND MANAGEMENT SCENARIOS =====
    
    function test_integration_multipleBackendsOperation() public {
        // Different backends executing buys
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        vm.prank(backend2);
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenB), 1500e6, 0);
        
        // Both should succeed
        assertTrue(autoBuy.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user2, address(tokenB)) > 0);
    }
    
    function test_integration_backendDeauthorization() public {
        // Deauthorize one backend mid-operation
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        vm.prank(owner);
        autoBuy.deauthorizeBackend(backend1);
        
        // Backend1 should no longer work
        vm.prank(backend1);
        vm.expectRevert("Not authorized backend");
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenA), 1000e6, 0);
        
        // Backend2 should still work
        vm.prank(backend2);
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenA), 1000e6, 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user2, address(tokenA)) > 0);
    }
    
    // ===== USER PREFERENCE CHANGES =====
    
    function test_integration_dynamicUserPreferenceChanges() public {
        // Initial buy
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        uint256 initialTokens = autoBuy.getUserTokenBalance(user1, address(tokenA));
        
        // User changes preferences
        vm.prank(user1);
        autoBuy.setSocialAmounts(1000e6, 500e6); // Reduced amounts
        
        // Execute with new preferences
        vm.prank(backend1);
        autoBuy.executeSocialAutoBuy(user1, address(tokenA), "like", 0);
        
        uint256 finalTokens = autoBuy.getUserTokenBalance(user1, address(tokenA));
        assertTrue(finalTokens > initialTokens);
    }
    
    function test_integration_userLimitChanges() public {
        // User increases their limit
        vm.prank(user3);
        autoBuy.setUserBuyLimitSelf(2000e6);
        
        vm.prank(user3);
        autoBuy.setSocialAmounts(1500e6, 1000e6);
        
        // Should now be able to execute larger buys
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user3, address(tokenA), 1500e6, 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user3, address(tokenA)) > 0);
    }
    
    // ===== WITHDRAWAL SCENARIOS =====
    
    function test_integration_multipleWithdrawals() public {
        // Users accumulate tokens
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenA), 2000e6, 0);
        
        uint256 user1Balance = autoBuy.getUserTokenBalance(user1, address(tokenA));
        uint256 user2Balance = autoBuy.getUserTokenBalance(user2, address(tokenA));
        
        // Partial withdrawals
        vm.prank(user1);
        autoBuy.withdrawUserBalance(address(tokenA), user1Balance / 2);
        
        vm.prank(user2);
        autoBuy.withdrawUserBalance(address(tokenA), user2Balance / 3);
        
        // Check balances updated correctly
        assertEq(autoBuy.getUserTokenBalance(user1, address(tokenA)), user1Balance / 2);
        assertEq(autoBuy.getUserTokenBalance(user2, address(tokenA)), user2Balance * 2 / 3);
        
        assertEq(tokenA.balanceOf(user1), user1Balance / 2);
        assertEq(tokenA.balanceOf(user2), user2Balance / 3);
    }
    
    // ===== FEE COLLECTION SCENARIOS =====
    
    function test_integration_feeCollection() public {
        // Execute multiple buys to generate fees
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 5000e6, 0);
        
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user2, address(tokenB), 2000e6, 0);
        
        vm.prank(backend2);
        autoBuy.executeFarcasterAutoBuy(user3, address(tokenC), 500e6, 0);
        
        uint256 expectedFees = (5000e6 + 2000e6 + 500e6) * 100 / 10000;
        assertEq(usdc.balanceOf(feeRecipient), expectedFees);
        
        // Change fee recipient
        address newFeeRecipient = address(0x8);
        vm.prank(owner);
        autoBuy.setFeeRecipient(newFeeRecipient);
        
        // New buys should go to new recipient
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        uint256 newFee = 1000e6 * 100 / 10000;
        assertEq(usdc.balanceOf(newFeeRecipient), newFee);
    }
    
    // ===== EMERGENCY SCENARIOS =====
    
    function test_integration_emergencyWithdrawal() public {
        // Accumulate some tokens in contract
        vm.prank(backend1);
        autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 1000e6, 0);
        
        // Mint extra tokens to contract
        usdc.mint(address(autoBuy), 10000e6);
        
        uint256 ownerInitialBalance = usdc.balanceOf(owner);
        
        // Emergency withdrawal
        vm.prank(owner);
        autoBuy.emergencyWithdraw(address(usdc), 5000e6);
        
        assertEq(usdc.balanceOf(owner), ownerInitialBalance + 5000e6);
    }
    
    // ===== OWNERSHIP TRANSFER SCENARIOS =====
    
    function test_integration_ownershipTransfer() public {
        address newOwner = address(0x9);
        
        // Transfer ownership
        vm.prank(owner);
        autoBuy.transferOwnership(newOwner);
        
        assertEq(autoBuy.owner(), newOwner);
        
        // Old owner should not have access
        vm.prank(owner);
        vm.expectRevert("Not owner");
        autoBuy.setFeeRecipient(address(0x10));
        
        // New owner should have access
        vm.prank(newOwner);
        autoBuy.setFeeRecipient(address(0x10));
        
        assertEq(autoBuy.feeRecipient(), address(0x10));
    }
    
    // ===== STRESS TESTS =====
    
    function test_integration_highVolumeOperations() public {
        // Simulate high volume of operations
        for (uint i = 0; i < 10; i++) {
            vm.prank(backend1);
            autoBuy.executeFarcasterAutoBuy(user1, address(tokenA), 500e6, 0);
            
            vm.prank(backend2);
            autoBuy.executeSocialAutoBuy(user2, address(tokenB), "like", 0);
            
            vm.prank(backend1);
            autoBuy.executeSocialAutoBuy(user3, address(tokenC), "recast", 0);
        }
        
        // All users should have accumulated significant balances
        assertTrue(autoBuy.getUserTokenBalance(user1, address(tokenA)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user2, address(tokenB)) > 0);
        assertTrue(autoBuy.getUserTokenBalance(user3, address(tokenC)) > 0);
        
        // Check total fees collected
        uint256 expectedTotalFees = (500e6 * 10 + 5000e6 * 10 + 250e6 * 10) * 100 / 10000;
        assertEq(usdc.balanceOf(feeRecipient), expectedTotalFees);
    }
    
    function test_integration_userReadinessChecks() public {
        // Test isUserReadyForAutoBuys under various conditions
        assertTrue(autoBuy.isUserReadyForAutoBuys(user1));
        assertTrue(autoBuy.isUserReadyForAutoBuys(user2));
        assertTrue(autoBuy.isUserReadyForAutoBuys(user3));
        
        // Disable social amounts for user1
        vm.prank(user1);
        autoBuy.setSocialAmounts(0, 0);
        
        assertFalse(autoBuy.isUserReadyForAutoBuys(user1));
        
        // Remove allowance for user2
        vm.prank(user2);
        usdc.approve(address(autoBuy), 0);
        
        assertFalse(autoBuy.isUserReadyForAutoBuys(user2));
        
        // Set buy limit to 0 for user3
        vm.prank(user3);
        autoBuy.setUserBuyLimitSelf(0);
        
        assertFalse(autoBuy.isUserReadyForAutoBuys(user3));
    }
}
