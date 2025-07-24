// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Mock contracts for gas testing
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
    fallback() external {
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
        uint256 amountOut = 100e6;
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
        amounts[0] = 100e6;
        amounts[1] = 100e6;
        
        if (targetToken.balanceOf(address(this)) >= amounts[1]) {
            targetToken.transfer(to, amounts[1]);
        }
    }
}

contract MockPermit2 {
    // Empty mock
}

contract AutoBuyGasTest is Test {
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
    address public user = address(0x3);
    address public feeRecipient = address(0x4);
    
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
        
        // Setup user
        usdc.mint(user, 100000e6);
        
        vm.prank(user);
        usdc.approve(address(autoBuy), type(uint256).max);
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(10000e6);
        
        vm.prank(user);
        autoBuy.setSocialAmounts(100e6, 250e6);
    }
    
    function test_gas_executeFarcasterAutoBuy() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 1000e6, 0);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for executeFarcasterAutoBuy:", gasUsed);
        
        // Assert reasonable gas usage (adjust based on actual measurements)
        assertLt(gasUsed, 500000, "Gas usage too high for Farcaster auto-buy");
    }
    
    function test_gas_executeSocialAutoBuy() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(backend);
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "like", 0);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for executeSocialAutoBuy:", gasUsed);
        
        assertLt(gasUsed, 500000, "Gas usage too high for social auto-buy");
    }
    
    function test_gas_setSocialAmounts() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(user);
        autoBuy.setSocialAmounts(150e6, 300e6);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for setSocialAmounts:", gasUsed);
        
        assertLt(gasUsed, 100000, "Gas usage too high for setting social amounts");
    }
    
    function test_gas_setUserBuyLimit() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(user);
        autoBuy.setUserBuyLimitSelf(15000e6);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for setUserBuyLimit:", gasUsed);
        
        assertLt(gasUsed, 50000, "Gas usage too high for setting buy limit");
    }
    
    function test_gas_withdrawUserBalance() public {
        // First execute a buy to have balance to withdraw
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 1000e6, 0);
        
        uint256 userBalance = autoBuy.getUserTokenBalance(user, address(targetToken));
        
        uint256 gasBefore = gasleft();
        
        vm.prank(user);
        autoBuy.withdrawUserBalance(address(targetToken), userBalance / 2);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for withdrawUserBalance:", gasUsed);
        
        assertLt(gasUsed, 100000, "Gas usage too high for withdrawal");
    }
    
    function test_gas_multipleOperations() public {
        uint256 gasBefore = gasleft();
        
        // Multiple operations in sequence
        vm.prank(backend);
        autoBuy.executeFarcasterAutoBuy(user, address(targetToken), 500e6, 0);
        
        vm.prank(backend);
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "like", 0);
        
        vm.prank(backend);
        autoBuy.executeSocialAutoBuy(user, address(targetToken), "recast", 0);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for multiple operations:", gasUsed);
        
        assertLt(gasUsed, 1500000, "Gas usage too high for multiple operations");
    }
    
    function test_gas_viewFunctions() public view {
        uint256 gasBefore = gasleft();
        
        autoBuy.getUserTokenBalance(user, address(targetToken));
        autoBuy.getUserBuyLimit(user);
        autoBuy.getUserLikeAmount(user);
        autoBuy.getUserRecastAmount(user);
        autoBuy.isUserReadyForAutoBuys(user);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for view functions:", gasUsed);
        
        assertLt(gasUsed, 50000, "Gas usage too high for view functions");
    }
}
