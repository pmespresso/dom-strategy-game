pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/GameKeeper.sol";

contract DeployKeeprMumbai is Script {
    function run() external {
        vm.startBroadcast();
        
        // in production the interval would be 18 hours but for testing make everythign faster
        uint256 INTERVAL = 10 minutes;
        uint256 intendedStartTime = block.timestamp + 10 minutes;
        
        new GameKeeper(INTERVAL, intendedStartTime, address(0xd50647D44ecfb638059e836803a4EB1a44654b03));

        vm.stopBroadcast();
    }
}