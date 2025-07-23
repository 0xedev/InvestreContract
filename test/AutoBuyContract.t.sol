// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Mock contracts for testing
contract MockUniversalRouter {
    bool public shouldFail;
    IERC20 public targetToken;
    
    function setTargetToken(address _targetToken) external {
        targetToken = IERC20(_targetToken);
    }
    
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
    
    function execute(bytes calldata, bytes[] calldata, uint256) external payable {
        if (shouldFail) revert("Mock router failure");
        
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
    mapping(bytes32 => uint160) public sqrtPrices;
    mapping(bytes32 => int24) public ticks;
    mapping(bytes32 => uint24) public protocolFees;
    mapping(bytes32 => uint256) public liquidities;
    
    function setSqrtPrice(bytes32 poolId, uint160 sqrtPrice) external {
        sqrtPrices[poolId] = sqrtPrice;
    }
    
    function getSlot0(bytes32 poolId) external view returns (uint160, int24, uint24, uint256) {
        return (sqrtPrices[poolId], ticks[poolId], protocolFees[poolId], liquidities[poolId]);
    }
    
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
    bool public shouldFail;
    IERC20 public targetToken;
    
    constructor(address _targetToken) {
        targetToken = IERC20(_targetToken);
    }
    
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
    
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external returns (uint256) {
        if (shouldFail) revert("Mock V3 router failure");
        
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
    bool public shouldFail;
    IERC20 public targetToken;
    
    constructor(address _targetToken) {
        targetToken = IERC20(_targetToken);
    }
    
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
    
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address to,
        uint256
    ) external returns (uint256[] memory) {
        if (shouldFail) revert("Mock V2 router failure");
        
        // Simulate a successful swap by transferring target tokens to recipient
        uint256 amountOut = 100e6;
        if (targetToken.balanceOf(address(this)) >= amountOut) {
            targetToken.transfer(to, amountOut);
        }
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = amountOut;
        return amounts;
    }
}

contract MockPermit2 {
    // Empty mock for now
}

contract AutoBuyContractTest is Test {
    AutoBuyContract public autoBuy;
    ERC20Mock public usdc;
    ERC20Mock public targetToken;
    MockUniversalRouter public mockRouter;
    MockPoolManager public mockPoolManager;
    MockV3Router public mockV3Router;
    MockV2Router public mockV2Router;
    MockPermit2 public mockPermit2;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    address public backend = address(0x3);
    address public feeRecipient = address(0x4);
    
    uint256 constant INITIAL_BALANCE = 10000e6; // 10k USDC
    uint256 constant USER_BUY_LIMIT = 1000e6; // 1k USDC
    uint256 constant LIKE_AMOUNT = 10e6; // 10 USDC
    uint256 constant RECAST_AMOUNT = 25e6; // 25 USDC
    
    event AutoBuyExecuted(address indexed user, address indexed tokenOut, uint256 usdcAmount, uint256 tokenAmount, uint256 fee);
    event FeeCollected(address indexed token, uint256 amount);
    event UserLimitSet(address indexed user, uint256 newLimit);
    event UserSocialAmountsSet(address indexed user, uint256 likeAmount, uint256 recastAmount);

    function setUp() public {
        // Deploy mock contracts
        usdc = new ERC20Mock();
        targetToken = new ERC20Mock();
        mockRouter = new MockUniversalRouter();
        mockPoolManager = new MockPoolManager();
        mockV3Router = new MockV3Router(address(targetToken));
        mockV2Router = new MockV2Router(address(targetToken));
        mockPermit2 = new MockPermit2();
        
        // Deploy AutoBuyContract first
        vm.prank(owner);
        autoBuy = new AutoBuyContract(
            address(mockRouter),
            address(mockPoolManager),
            address(mockPermit2),
            address(mockV3Router),
            address(mockV2Router),
            address(usdc)
        );
        
        // Give target tokens to the mock routers for swaps
        targetToken.mint(address(mockV3Router), INITIAL_BALANCE);
        targetToken.mint(address(mockV2Router), INITIAL_BALANCE);
        targetToken.mint(address(mockRouter), INITIAL_BALANCE);
        
        // Set target token for universal router
        mockRouter.setTargetToken(address(targetToken));
        
        // Setup initial state
        vm.prank(owner);
        autoBuy.authorizeBackend(backend);
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(feeRecipient);
        
        // Mint tokens to users
        usdc.mint(user, INITIAL_BALANCE);
        
        // Setup mock pool manager to return zero sqrt price for ALL pool IDs
        // This will force the contract to use V3/V2 routes which our mocks handle
        // We don't set any sqrt price, so it defaults to 0 for all pools
        
        // Setup user permissions
        vm.prank(user);
        usdc.approve(address(autoBuy), type(uint256).max);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(USER_BUY_LIMIT);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(LIKE_AMOUNT, RECAST_AMOUNT);
    }

    // ===== BASIC FUNCTIONALITY TESTS =====
    
    function test_deployment() public view{
        assertEq(autoBuy.owner(), owner);
        assertEq(autoBuy.feeRecipient(), feeRecipient);
        assertEq(address(autoBuy.router()), address(mockRouter));
        assertEq(autoBuy.USDC(), address(usdc));
        assertEq(autoBuy.FEE_BASIS_POINTS(), 100);
        assertEq(autoBuy.BASIS_POINTS(), 10000);
        assertTrue(autoBuy.isAuthorizedBackend(owner)); // Deployer auto-authorized
        assertTrue(autoBuy.isAuthorizedBackend(backend));
    }
    
    function test_setUserBuyLimit() public {
        uint256 newLimit = 2000e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserLimitSet(user, newLimit);
        
        vm.prank(owner);
        autoBuy.setUserBuyLimit(user, newLimit);
        
        assertEq(autoBuy.getUserBuyLimit(user), newLimit);
    }
    
    function test_setUserBuyLimitSelf() public {
        uint256 newLimit = 1500e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserLimitSet(user, newLimit);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(newLimit);
        
        assertEq(autoBuy.getUserBuyLimit(user), newLimit);
    }
    
    function test_setSocialAmounts() public {
        uint256 newLikeAmount = 15e6;
        uint256 newRecastAmount = 30e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserSocialAmountsSet(user, newLikeAmount, newRecastAmount);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(newLikeAmount, newRecastAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), newLikeAmount);
        assertEq(autoBuy.getUserRecastAmount(user), newRecastAmount);
    }
    
    function test_setSocialAmounts_revertsIfExceedsLimit() public {
        uint256 invalidAmount = USER_BUY_LIMIT + 1;
        
        vm.prank(user);
        vm.expectRevert("Like amount exceeds buy limit");
        autoBuy.setSocialAmounts(invalidAmount, RECAST_AMOUNT);
        
        vm.prank(user);
        vm.expectRevert("Recast amount exceeds buy limit");
        autoBuy.setSocialAmounts(LIKE_AMOUNT, invalidAmount);
    }
    
    function test_setUserPreferences() public {
        uint256 newLimit = 1500e6;
        uint256 newLikeAmount = 20e6;
        uint256 newRecastAmount = 40e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserLimitSet(user, newLimit);
        vm.expectEmit(true, false, false, true);
        emit UserSocialAmountsSet(user, newLikeAmount, newRecastAmount);
        
        vm.prank(user);
        autoBuy.setUserPreferences(newLimit, newLikeAmount, newRecastAmount);
        
        assertEq(autoBuy.getUserBuyLimit(user), newLimit);
        assertEq(autoBuy.getUserLikeAmount(user), newLikeAmount);
        assertEq(autoBuy.getUserRecastAmount(user), newRecastAmount);
    }
    
    // ===== ACCESS CONTROL TESTS =====
    
    function test_onlyOwner_modifier() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        autoBuy.authorizeBackend(address(0x5));
        
        vm.prank(user);
        vm.expectRevert("Not owner");
        autoBuy.setFeeRecipient(address(0x5));
        
        vm.prank(user);
        vm.expectRevert("Not owner");
        autoBuy.transferOwnership(address(0x5));
    }
    
    function test_onlyAuthorized_modifier() public {
        vm.prank(user);
        vm.expectRevert("Not authorized backend");
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 100e6, 0);
    }
    
    function test_authorizeBackend() public {
        address newBackend = address(0x5);
        
        vm.prank(owner);
        autoBuy.authorizeBackend(newBackend);
        
        assertTrue(autoBuy.isAuthorizedBackend(newBackend));
    }
    
    function test_deauthorizeBackend() public {
        vm.prank(owner);
        autoBuy.deauthorizeBackend(backend);
        
        assertFalse(autoBuy.isAuthorizedBackend(backend));
    }
    
    function test_transferOwnership() public {
        address newOwner = address(0x5);
        
        vm.prank(owner);
        autoBuy.transferOwnership(newOwner);
        
        assertEq(autoBuy.owner(), newOwner);
    }
    
    function test_transferOwnership_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid new owner");
        autoBuy.transferOwnership(address(0));
    }
    
    // ===== FARCASTER AUTO-BUY TESTS =====
    
    function test_executeFarcasterAutoBuy_success() public {
        uint256 buyAmount = 100e6;
        uint256 expectedFee = (buyAmount * 100) / 10000; // 1% fee
        // uint256 swapAmount = buyAmount - expectedFee;
        
        vm.expectEmit(true, true, false, true);
        emit FeeCollected(address(usdc), expectedFee);
        
        vm.prank(backend);
        uint256 amountOut = autoBuy.executeFarcasterAutoBuy(user, address(targetToken), buyAmount, 0);
        
        // Check balances
        assertEq(usdc.balanceOf(user), INITIAL_BALANCE - buyAmount);
        assertEq(usdc.balanceOf(feeRecipient), expectedFee);
        assertTrue(amountOut > 0);
        assertEq(autoBuy.getUserTokenBalance(user, address(targetToken)), amountOut);
    }
    
    function test_executeFarcasterAutoBuy_revertsIfNoBuyLimit() public {
        address newUser = address(0x6);
        usdc.mint(newUser, INITIAL_BALANCE);
        
        vm.prank(newUser);
        usdc.approve(address(autoBuy), type(uint256).max);
        
        vm.prank(backend);
        vm.expectRevert("User has not set buy limit");
        autoBuy.executeFarcasterAutoBuy(newUser, address(targetToken), 100e6, 0);
    }
    
    function test_executeFarcasterAutoBuy_revertsIfExceedsLimit() public {
        uint256 exceedsLimit = USER_BUY_LIMIT + 1;
        
        vm.prank(backend);
        vm.expectRevert("Buy amount exceeds user limit");
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), exceedsLimit, 0);
    }
    
    function test_executeFarcasterAutoBuy_revertsIfInsufficientAllowance() public {
        vm.prank(user);
        usdc.approve(address(autoBuy), 50e6); // Less than buy amount
        
        vm.prank(backend);
        vm.expectRevert("Insufficient USDC allowance");
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 100e6, 0);
    }
    
    // ===== SOCIAL AUTO-BUY TESTS =====
    
    function test_executeSocialAutoBuy_like() public {
        vm.prank(backend);
        uint256 amountOut = autoBuy.executeSocialAutoBuy(user, address(targetToken), "like", 0);
        
        assertTrue(amountOut > 0);
        assertEq(autoBuy.getUserTokenBalance(user, address(targetToken)), amountOut);
    }
    
    function test_executeSocialAutoBuy_recast() public {
        vm.prank(backend);
        uint256 amountOut = autoBuy.executeSocialAutoBuy(user, address(targetToken), "recast", 0);
        
        assertTrue(amountOut > 0);
        assertEq(autoBuy.getUserTokenBalance(user, address(targetToken)), amountOut);
    }
    
    function test_executeSocialAutoBuy_revertsInvalidType() public {
        vm.prank(backend);
        vm.expectRevert("Invalid interaction type");
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "invalid", 0);
    }
    
    function test_executeSocialAutoBuy_revertsIfNoLikeAmount() public {
        vm.prank(user);
        autoBuy.setSocialAmounts(0, RECAST_AMOUNT); // Zero like amount
        
        vm.prank(backend);
        vm.expectRevert("User has not set like amount");
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "like", 0);
    }
    
    // ===== WITHDRAWAL TESTS =====
    
    function test_withdrawUserBalance() public {
        // First, execute a buy to have some balance
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 100e6, 0);
        
        uint256 userBalance = autoBuy.getUserTokenBalance(user, address(targetToken));
        uint256 withdrawAmount = userBalance / 2;
        
        vm.prank(user);
        autoBuy.withdrawUserBalance(address(targetToken), withdrawAmount);
        
        assertEq(targetToken.balanceOf(user), withdrawAmount);
        assertEq(autoBuy.getUserTokenBalance(user, address(targetToken)), userBalance - withdrawAmount);
    }
    
    function test_withdrawUserBalance_revertsInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        autoBuy.withdrawUserBalance(address(targetToken), 1000e6);
    }
    
    function test_withdrawFees() public {
        // Execute a buy to generate fees
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 100e6, 0);
        
        uint256 feeBalance = usdc.balanceOf(feeRecipient);
        
        // Mint some extra USDC to the contract for testing
        usdc.mint(address(autoBuy), 500e6);
        
        // Get the contract balance before withdrawal
        uint256 contractBalance = usdc.balanceOf(address(autoBuy));
        
        vm.prank(owner);
        autoBuy.withdrawFees(address(usdc));
        
        // The withdrawFees function transfers the entire contract balance
        assertEq(usdc.balanceOf(feeRecipient), feeBalance + contractBalance);
    }
    
    function test_emergencyWithdraw() public {
        usdc.mint(address(autoBuy), 1000e6);
        
        vm.prank(owner);
        autoBuy.emergencyWithdraw(address(usdc), 500e6);
        
        assertEq(usdc.balanceOf(owner), 500e6);
    }
    
    // ===== VIEW FUNCTION TESTS =====
    
    function test_isUserReadyForAutoBuys() public {
        assertTrue(autoBuy.isUserReadyForAutoBuys(user));
        
        // Test with zero buy limit
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(0);
        assertFalse(autoBuy.isUserReadyForAutoBuys(user));
        
        // Reset buy limit
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(USER_BUY_LIMIT);
        
        // Test with zero allowance
        vm.prank(user);
        usdc.approve(address(autoBuy), 0);
        assertFalse(autoBuy.isUserReadyForAutoBuys(user));
        
        // Reset allowance
        vm.prank(user);
        usdc.approve(address(autoBuy), type(uint256).max);
        
        // Test with zero social amounts
        vm.prank(user);
        autoBuy.setSocialAmounts(0, 0);
        assertFalse(autoBuy.isUserReadyForAutoBuys(user));
    }
    
    function test_getUserSocialAmounts() public view {
        (uint256 likeAmount, uint256 recastAmount) = autoBuy.getUserSocialAmounts(user);
        assertEq(likeAmount, LIKE_AMOUNT);
        assertEq(recastAmount, RECAST_AMOUNT);
    }
    
    // ===== UTILITY FUNCTION TESTS =====
    
    function test_disableSocialAutoBuying() public {
        vm.expectEmit(true, false, false, true);
        emit UserSocialAmountsSet(user, 0, 0);
        
        vm.prank(user);
        autoBuy.disableSocialAutoBuying();
        
        assertEq(autoBuy.getUserLikeAmount(user), 0);
        assertEq(autoBuy.getUserRecastAmount(user), 0);
    }
    
    function test_enableSocialAutoBuying() public {
        uint256 newLikeAmount = 50e6;
        uint256 newRecastAmount = 75e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserSocialAmountsSet(user, newLikeAmount, newRecastAmount);
        
        vm.prank(user);
        autoBuy.enableSocialAutoBuying(newLikeAmount, newRecastAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), newLikeAmount);
        assertEq(autoBuy.getUserRecastAmount(user), newRecastAmount);
    }
    
    function test_updateLikeAmount() public {
        uint256 newAmount = 20e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserSocialAmountsSet(user, newAmount, RECAST_AMOUNT);
        
        vm.prank(user);
        autoBuy.updateLikeAmount(newAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), newAmount);
        assertEq(autoBuy.getUserRecastAmount(user), RECAST_AMOUNT); // Unchanged
    }
    
    function test_updateRecastAmount() public {
        uint256 newAmount = 50e6;
        
        vm.expectEmit(true, false, false, true);
        emit UserSocialAmountsSet(user, LIKE_AMOUNT, newAmount);
        
        vm.prank(user);
        autoBuy.updateRecastAmount(newAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), LIKE_AMOUNT); // Unchanged
        assertEq(autoBuy.getUserRecastAmount(user), newAmount);
    }
    
    // ===== FUZZ TESTS =====
    
    function testFuzz_setUserBuyLimit(uint256 limitUSDC) public {
        vm.assume(limitUSDC <= type(uint128).max); // Reasonable upper bound
        
        vm.prank(owner);
        autoBuy.setUserBuyLimit(user, limitUSDC);
        
        assertEq(autoBuy.getUserBuyLimit(user), limitUSDC);
    }
    
    function testFuzz_setSocialAmounts(uint256 likeAmount, uint256 recastAmount) public {
        vm.assume(likeAmount <= USER_BUY_LIMIT);
        vm.assume(recastAmount <= USER_BUY_LIMIT);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(likeAmount, recastAmount);
        
        assertEq(autoBuy.getUserLikeAmount(user), likeAmount);
        assertEq(autoBuy.getUserRecastAmount(user), recastAmount);
    }
    
    function testFuzz_executeFarcasterAutoBuy(uint256 buyAmount) public {
        vm.assume(buyAmount > 0);
        vm.assume(buyAmount <= USER_BUY_LIMIT);
        vm.assume(buyAmount <= usdc.balanceOf(user));
        
        uint256 expectedFee = (buyAmount * 100) / 10000;
        uint256 initialBalance = usdc.balanceOf(user);
        
        vm.prank(backend);
        uint256 amountOut = autoBuy.executeFarcasterAutoBuy(user, address(targetToken), buyAmount, 0);
        
        assertEq(usdc.balanceOf(user), initialBalance - buyAmount);
        assertEq(usdc.balanceOf(feeRecipient), expectedFee);
        assertTrue(amountOut > 0);
    }
    
    function testFuzz_calculateFee(uint256 amount) public view {
        vm.assume(amount <= type(uint256).max / 100); // Prevent overflow
        
        uint256 expectedFee = (amount * 100) / 10000; // 1%
        uint256 actualFee = autoBuy.calculateFee(amount);
        
        assertEq(actualFee, expectedFee);
    }
    
    // ===== EDGE CASE TESTS =====
    
    function test_executeFarcasterAutoBuy_zeroMinAmount() public {
        vm.prank(backend);
        uint256 amountOut = autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 100e6, 0);
        assertTrue(amountOut > 0);
    }
    
    function test_executeFarcasterAutoBuy_maxBuyLimit() public {
        vm.prank(backend);
        uint256 amountOut = autoBuy.executeFarcasterAutoBuy(user, address(targetToken), USER_BUY_LIMIT, 0);
        assertTrue(amountOut > 0);
    }
    
    function test_multipleExecutions() public {
        // Execute multiple buys
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 100e6, 0);
        
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 200e6, 0);
        
        assertTrue(autoBuy.getUserTokenBalance(user, address(targetToken)) > 0);
        assertEq(usdc.balanceOf(user), INITIAL_BALANCE - 300e6);
    }
    
    function test_setFeeRecipient() public {
        address newRecipient = address(0x7);
        
        vm.prank(owner);
        autoBuy.setFeeRecipient(newRecipient);
        
        assertEq(autoBuy.feeRecipient(), newRecipient);
    }
    
    function test_setFeeRecipient_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid fee recipient");
        autoBuy.setFeeRecipient(address(0));
    }
}
