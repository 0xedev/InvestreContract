// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/AllUniswap.sol";

contract DeployBase is Script {
    // Base Mainnet Contract Addresses
    
    // Universal Router (Base)
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    
    // Uniswap V4 (Base)
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    
    // Permit2 (Base)
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // Uniswap V3 SwapRouter (Base)
    address constant V3_SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    
    // Uniswap V2 Router (Base)
    address constant V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; 
                         
    // USDC (Base)
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the AutoBuyContract
        AutoBuyContract autoBuy = new AutoBuyContract(
            UNIVERSAL_ROUTER,  // _router
            POOL_MANAGER,      // _poolManager
            PERMIT2,           // _permit2
            V3_SWAP_ROUTER,    // _v3Router
            V2_ROUTER,         // _v2Router
            USDC               // _usdc
        );
        
        vm.stopBroadcast();
        
        console.log("=== Deployment Complete ===");
        console.log("AutoBuyContract deployed at:", address(autoBuy));
        console.log("");
        console.log("Contract addresses used:");
        console.log("Universal Router:", UNIVERSAL_ROUTER);
        console.log("Pool Manager (V4):", POOL_MANAGER);
        console.log("Permit2:", PERMIT2);
        console.log("V3 SwapRouter:", V3_SWAP_ROUTER);
        console.log("V2 Router:", V2_ROUTER);
        console.log("USDC:", USDC);
        console.log("");
        console.log("Owner:", deployer);
        console.log("Fee Recipient:", deployer);
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify the contract on Basescan");
        console.log("2. Set up additional backend wallets if needed");
        console.log("3. Configure fee recipient if different from deployer");
    }
    
    // Verification helper - call this after deployment
    function verify() external pure {
        console.log("Verification parameters:");
        console.log("Constructor args (in order):");
        console.log("_router:", UNIVERSAL_ROUTER);
        console.log("_poolManager:", POOL_MANAGER);
        console.log("_permit2:", PERMIT2);
        console.log("_v3Router:", V3_SWAP_ROUTER);
        console.log("_v2Router:", V2_ROUTER);
        console.log("_usdc:", USDC);
    }
}
