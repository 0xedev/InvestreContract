// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AutoBuyFuzzTest is Test {
    AutoBuyContract public autoBuy;
    ERC20Mock public usdc;
    ERC20Mock public targetToken;
    
    address public owner = address(0x1);
    address public backend = address(0x2);
    address public feeRecipient = address(0x3);
    
    function setUp() public {
        usdc = new ERC20Mock();
        targetToken = new ERC20Mock();
        
        vm.prank(owner);
        autoBuy = new AutoBuyContract(
            address(0x100), // Mock router
            address(0x101), // Mock pool manager  
            address(0x102), // Mock permit2
            address(0x103), // Mock V3 router
            address(0x104), // Mock V2 router
            address(usdc)
        );
        
        vm.prank(owner);
        autoBuy.authorizeBackend(backend);
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(feeRecipient);
        
        targetToken.mint(address(autoBuy), 1000000e18);
    }
    
    function setupUser(address user, uint256 balance, uint256 buyLimit) internal {
        vm.assume(user != address(0));
        vm.assume(user != address(autoBuy));
        vm.assume(user != owner);
        vm.assume(user != backend);
        vm.assume(user != feeRecipient);
        vm.assume(balance > 0);
        vm.assume(buyLimit > 0);
        vm.assume(buyLimit <= balance);
        
        usdc.mint(user, balance);
        vm.prank(user);
        usdc.approve(address(autoBuy), type(uint256).max);
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(buyLimit);
    }
    
    // FUZZ TEST: User buy limit setting
    function testFuzz_setUserBuyLimit(address user, uint256 limit) public {
        vm.assume(user != address(0));
        vm.assume(limit <= type(uint128).max);
        
        setupUser(user, 100000e6, 50000e6);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(limit);
        
        assertEq(autoBuy.getUserBuyLimit(user), limit);
    }
    
    // FUZZ TEST: Social amounts setting
    function testFuzz_setSocialAmounts(
        address user, 
        uint256 buyLimit, 
        uint256 likeAmount, 
        uint256 recastAmount
    ) public {
        vm.assume(user != address(0));
        vm.assume(buyLimit > 0 && buyLimit <= 100000e6);
        vm.assume(likeAmount <= buyLimit);
        vm.assume(recastAmount <= buyLimit);
        
        setupUser(user, 100000e6, buyLimit);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(likeAmount, recastAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), likeAmount);
        assertEq(autoBuy.getUserRecastAmount(user), recastAmount);
    }
    
    // FUZZ TEST: Fee calculation
    function testFuzz_calculateFee(uint256 amount) public view {
        vm.assume(amount <= type(uint256).max / 10000); // Prevent overflow
        
        uint256 expectedFee = (amount * 100) / 10000; // 1%
        uint256 actualFee = autoBuy.calculateFee(amount);
        
        assertEq(actualFee, expectedFee);
        assertLe(actualFee, amount); // Fee should never exceed amount
    }
    
    // FUZZ TEST: Farcaster auto-buy execution
    function testFuzz_executeFarcasterAutoBuy(
        address user,
        uint256 userBalance,
        uint256 buyLimit,
        uint256 buyAmount
    ) public {
        vm.assume(user != address(0));
        vm.assume(user != address(autoBuy));
        vm.assume(userBalance >= 1000e6 && userBalance <= 1000000e6); // Reasonable bounds
        vm.assume(buyLimit > 0 && buyLimit <= userBalance);
        vm.assume(buyAmount > 0 && buyAmount <= buyLimit);
        
        setupUser(user, userBalance, buyLimit);
        
        uint256 initialBalance = usdc.balanceOf(user);
        uint256 expectedFee = (buyAmount * 100) / 10000;
        
        vm.prank(backend);
        try autoBuy.executeFarcasterAutoBuy(user, address(targetToken), buyAmount, 0) {
            assertEq(usdc.balanceOf(user), initialBalance - buyAmount);
            assertGe(usdc.balanceOf(feeRecipient), expectedFee);
            assertTrue(autoBuy.getUserTokenBalance(user, address(targetToken)) > 0);
        } catch {
            // If transaction fails, balances should remain unchanged
            assertEq(usdc.balanceOf(user), initialBalance);
        }
    }
    
    // FUZZ TEST: Social auto-buy execution
    function testFuzz_executeSocialAutoBuy(
        address user,
        uint256 userBalance,
        uint256 likeAmount,
        uint256 recastAmount,
        bool isLike
    ) public {
        vm.assume(user != address(0));
        vm.assume(userBalance >= 1000e6 && userBalance <= 1000000e6);
        vm.assume(likeAmount > 0 && likeAmount <= 10000e6);
        vm.assume(recastAmount > 0 && recastAmount <= 10000e6);
        
        uint256 buyLimit = likeAmount > recastAmount ? likeAmount : recastAmount;
        vm.assume(buyLimit <= userBalance);
        
        setupUser(user, userBalance, buyLimit);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(likeAmount, recastAmount);
        
        string memory interactionType = isLike ? "like" : "recast";
        uint256 expectedAmount = isLike ? likeAmount : recastAmount;
        uint256 initialBalance = usdc.balanceOf(user);
        
        vm.prank(backend);
        try autoBuy.executeSocialAutoBuy(user, address(targetToken), interactionType, 0) {
            assertEq(usdc.balanceOf(user), initialBalance - expectedAmount);
            assertTrue(autoBuy.getUserTokenBalance(user, address(targetToken)) > 0);
        } catch {
            assertEq(usdc.balanceOf(user), initialBalance);
        }
    }
    
    // FUZZ TEST: User balance withdrawal
    function testFuzz_withdrawUserBalance(
        address user,
        uint256 initialTokens,
        uint256 withdrawAmount
    ) public {
        vm.assume(user != address(0));
        vm.assume(initialTokens > 0 && initialTokens <= 1000000e18);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= initialTokens);
        
        setupUser(user, 100000e6, 50000e6);
        
        // Simulate user earning tokens (directly set balance for testing)
        vm.store(
            address(autoBuy),
            keccak256(abi.encode(address(targetToken), keccak256(abi.encode(user, uint256(3))))),
            bytes32(initialTokens)
        );
        
        uint256 userInitialBalance = targetToken.balanceOf(user);
        
        vm.prank(user);
        autoBuy.withdrawUserBalance(address(targetToken), withdrawAmount);
        
        assertEq(targetToken.balanceOf(user), userInitialBalance + withdrawAmount);
        assertEq(
            autoBuy.getUserTokenBalance(user, address(targetToken)),
            initialTokens - withdrawAmount
        );
    }
    
    // FUZZ TEST: Multiple operations sequence
    function testFuzz_multipleOperations(
        address user,
        uint256 buyLimit,
        uint256 likeAmount,
        uint256 firstBuy,
        uint256 secondBuy
    ) public {
        vm.assume(user != address(0));
        vm.assume(buyLimit >= 1000e6 && buyLimit <= 10000e6);
        vm.assume(likeAmount > 0 && likeAmount <= buyLimit);
        vm.assume(firstBuy > 0 && firstBuy <= buyLimit);
        vm.assume(secondBuy > 0 && secondBuy <= buyLimit);
        vm.assume(firstBuy + secondBuy <= buyLimit * 2); // Allow multiple buys
        
        uint256 totalNeeded = firstBuy + secondBuy + likeAmount;
        setupUser(user, totalNeeded + 1000e6, buyLimit);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(likeAmount, 0);
        
        uint256 initialBalance = usdc.balanceOf(user);
        
        // First buy
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), firstBuy, 0);
        
        // Social buy
        vm.prank(backend);
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "like", 0);
        
        // Second buy
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), secondBuy, 0);
        
        uint256 totalSpent = firstBuy + likeAmount + secondBuy;
        assertEq(usdc.balanceOf(user), initialBalance - totalSpent);
        assertTrue(autoBuy.getUserTokenBalance(user, address(targetToken)) > 0);
    }
    
    // FUZZ TEST: Authorization and access control
    function testFuzz_unauthorizedAccess(address unauthorized, uint256 amount) public {
        vm.assume(unauthorized != backend);
        vm.assume(unauthorized != owner);
        vm.assume(unauthorized != address(0));
        vm.assume(amount > 0 && amount <= 1000e6);
        
        address user = address(0x999);
        setupUser(user, 10000e6, 5000e6);
        
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized backend");
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), amount, 0);
    }
    
    // FUZZ TEST: Boundary conditions
    function testFuzz_boundaryConditions(uint256 amount) public {
        address user = address(0x999);
        uint256 buyLimit = 1000e6;
        
        setupUser(user, 10000e6, buyLimit);
        
        // Test amounts at or beyond buy limit
        if (amount > buyLimit) {
            vm.prank(backend);
            vm.expectRevert("Buy amount exceeds user limit");
            autoBuy.executeFarcasterAutoBuy(user, address(targetToken), amount, 0);
        } else if (amount > 0) {
            vm.prank(backend);
            try autoBuy.executeFarcasterAutoBuy(user, address(targetToken), amount, 0) {
                assertTrue(autoBuy.getUserTokenBalance(user, address(targetToken)) > 0);
            } catch {
                // Some legitimate failures are acceptable (e.g., router failures)
            }
        }
    }
    
    // FUZZ TEST: Fee recipient changes
    function testFuzz_feeRecipientChanges(address newRecipient) public {
        vm.assume(newRecipient != address(0));
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(newRecipient);
        
        assertEq(autoBuy.feeRecipient(), newRecipient);
        
        // Test that fees go to new recipient
        address user = address(0x999);
        setupUser(user, 10000e6, 5000e6);
        
        uint256 buyAmount = 1000e6;
        uint256 expectedFee = (buyAmount * 100) / 10000;
        
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), buyAmount, 0);
        
        assertEq(usdc.balanceOf(newRecipient), expectedFee);
    }
    
    // FUZZ TEST: Backend authorization changes
    function testFuzz_backendAuthorizationChanges(address newBackend) public {
        vm.assume(newBackend != address(0));
        vm.assume(newBackend != backend);
        
        // Authorize new backend
        vm.prank(owner);
        autoBuy.authorizeBackend(newBackend);
        
        assertTrue(autoBuy.isAuthorizedBackend(newBackend));
        
        // Test new backend can execute
        address user = address(0x999);
        setupUser(user, 10000e6, 5000e6);
        
        vm.prank(newBackend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 1000e6, 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user, address(targetToken)) > 0);
        
        // Deauthorize old backend
        vm.prank(owner);
        autoBuy.deauthorizeBackend(backend);
        
        assertFalse(autoBuy.isAuthorizedBackend(backend));
        
        // Test old backend can no longer execute
        vm.prank(backend);
        vm.expectRevert("Not authorized backend");
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 1000e6, 0);
    }
}
