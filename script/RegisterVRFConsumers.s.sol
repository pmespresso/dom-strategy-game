// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import "chainlink/v0.8/interfaces/LinkTokenInterface.sol";

import "./HelperConfig.sol";

contract RegisterVRFConsumers is Script {

    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (
        ,
        ,
        ,
        ,
        ,
        ,
        ,
        ,
        uint64 subscriptionId,
        address vrfCoordinator,
        ) = helperConfig.activeNetworkConfig();

        address deployer = vm.envAddress("MUMBAI_ADDRESS");

        console.log("Deployer: ", deployer);

        address game = vm.envAddress("GAME");
        address bot1 = vm.envAddress("BOT1");
        address bot2 = vm.envAddress("BOT2");
        
        vm.startBroadcast();
        // Register Game as VRF Consumer
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(subscriptionId, address
        (game));
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(subscriptionId, address(bot1));
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(subscriptionId, address(bot2));

        vm.stopBroadcast();
    }
}