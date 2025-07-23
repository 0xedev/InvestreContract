// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";
import { AutoBuyContract } from "../src/AllUniswap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AutoBuyGasTest is Test {
    AutoBuyContract public autoBuy;
    ERC20Mock public usdc;
    ERC20Mock public targetToken;
    
    address public owner = address(0x1);
    address public backend = address(0x2);
    address public user = address(0x3);
    address public feeRecipient = address(0x4);
    
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
        
        // Setup user
        usdc.mint(user, 100000e6);
        targetToken.mint(address(autoBuy), 1000000e18);
        
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
        
        assertLt(gasUsed, 20000, "Gas usage too high for view functions");
    }
}
