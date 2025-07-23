// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Mock contracts for testing
contract MockUniversalRouter {
    IERC20 public targetToken;
    
    function setTargetToken(address _targetToken) external {
        targetToken = IERC20(_targetToken);
    }
    
    function execute(bytes calldata, bytes[] calldata, uint256) external payable {
        // Simulate a successful swap by transferring target tokens to caller
        if (address(targetToken) != address(0)) {
            uint256 amountOut = 100e6; // Mock return value
            if (targetToken.balanceOf(address(this)) >= amountOut) {
                targetToken.transfer(msg.sender, amountOut);
            }
        }
    }
}

contract MockPoolManager {
    // Handle direct storage access that StateLibrary might use
    fallback() external {
        // Return zero for any unhandled calls to simulate empty pool
        assembly {
            mstore(0x00, 0)
            return(0x00, 0x20)
        }
    }
}

contract MockV3Router {
    IERC20 public targetToken;
    
    constructor(address _targetToken) {
        targetToken = IERC20(_targetToken);
    }
    
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external returns (uint256) {
        // Simulate a successful swap by transferring target tokens to recipient
        uint256 amountOut = 100e6; // Mock return value
        if (targetToken.balanceOf(address(this)) >= amountOut) {
            targetToken.transfer(params.recipient, amountOut);
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
    IERC20 public targetToken;
    
    constructor(address _targetToken) {
        targetToken = IERC20(_targetToken);
    }
    
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = 100e6; // Input amount
        amounts[1] = 100e6; // Output amount
        
        // Transfer tokens to recipient
        if (targetToken.balanceOf(address(this)) >= amounts[1]) {
            targetToken.transfer(to, amounts[1]);
        }
    }
}

contract MockPermit2 {
    // Empty mock for now
}

contract AutoBuyFuzzTest is Test {
    AutoBuyContract public autoBuy;
    ERC20Mock public usdc;
    ERC20Mock public targetToken;
    
    MockUniversalRouter public router;
    MockPoolManager public poolManager;
    MockV3Router public v3Router;
    MockV2Router public v2Router;
    MockPermit2 public permit2;
    
    address public owner = address(0x1);
    address public backend = address(0x2);
    address public feeRecipient = address(0x3);
    
    function setUp() public {
        usdc = new ERC20Mock();
        targetToken = new ERC20Mock();
        
        // Create mock contracts
        router = new MockUniversalRouter();
        poolManager = new MockPoolManager();
        v3Router = new MockV3Router(address(targetToken));
        v2Router = new MockV2Router(address(targetToken));
        permit2 = new MockPermit2();
        
        // Mint tokens to mock routers for swaps
        targetToken.mint(address(v3Router), 1000000e18);
        targetToken.mint(address(v2Router), 1000000e18);
        targetToken.mint(address(router), 1000000e18);
        
        // Set target token for universal router
        router.setTargetToken(address(targetToken));
        
        vm.prank(owner);
        autoBuy = new AutoBuyContract(
            address(router),
            address(poolManager),
            address(permit2),
            address(v3Router),
            address(v2Router),
            address(usdc)
        );
        
        vm.prank(owner);
        autoBuy.authorizeBackend(backend);
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(feeRecipient);
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
        vm.assume(user != address(autoBuy));
        vm.assume(user != owner);
        vm.assume(user != backend);
        vm.assume(user != feeRecipient);
        vm.assume(initialTokens > 0 && initialTokens <= 1000e6); // Use smaller amounts
        vm.assume(withdrawAmount > 0 && withdrawAmount <= initialTokens);
        
        setupUser(user, 100000e6, 50000e6);
        
        // First, let user earn some tokens through a buy
        vm.prank(user);
        autoBuy.setSocialAmounts(initialTokens, 0);
        
        vm.prank(backend);
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "like", 0);
        
        uint256 userTokenBalance = autoBuy.getUserTokenBalance(user, address(targetToken));
        vm.assume(userTokenBalance >= withdrawAmount);
        
        uint256 userInitialBalance = targetToken.balanceOf(user);
        
        vm.prank(user);
        autoBuy.withdrawUserBalance(address(targetToken), withdrawAmount);
        
        assertEq(targetToken.balanceOf(user), userInitialBalance + withdrawAmount);
        assertEq(
            autoBuy.getUserTokenBalance(user, address(targetToken)),
            userTokenBalance - withdrawAmount
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
        vm.assume(user != address(autoBuy));
        vm.assume(user != owner);
        vm.assume(user != backend);
        vm.assume(user != feeRecipient);
        
        // Use simpler constraints to avoid rejection
        buyLimit = bound(buyLimit, 1000e6, 5000e6);
        likeAmount = bound(likeAmount, 100e6, buyLimit / 2);
        firstBuy = bound(firstBuy, 100e6, buyLimit / 2);
        secondBuy = bound(secondBuy, 100e6, buyLimit / 2);
        
        uint256 totalNeeded = firstBuy + secondBuy + likeAmount;
        setupUser(user, totalNeeded + 2000e6, buyLimit);
        
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

    // FUZZ TEST: Owner fee withdrawal
    function testFuzz_withdrawFees(uint256 feeAmount) public {
        vm.assume(feeAmount > 0 && feeAmount <= 1000000e6);
        
        // Simulate fees accumulated in the contract
        deal(address(usdc), address(autoBuy), feeAmount);
        
        uint256 feeRecipientInitialBalance = usdc.balanceOf(feeRecipient);
        
        vm.prank(owner);
        autoBuy.withdrawFees(address(usdc));
        
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientInitialBalance + feeAmount);
    }
}
