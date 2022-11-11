// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import "chainlink/v0.8/interfaces/LinkTokenInterface.sol";

import "./HelperConfig.sol";
import "../src/DominationGame.sol";
import "../src/BaseCharacter.sol";
import "../src/HorizontalBot.sol";

contract DeployBots is Script {
    function run() external {
        vm.startBroadcast();
        address game = vm.envAddress("GAME");
        address nft = vm.envAddress("NFT");
        
        HorizontalBot bot1 = new HorizontalBot(game, nft, 300);
        HorizontalBot bot2 = new HorizontalBot(game, nft, 300);

        console.log("Bot1: ", address(bot1));
        console.log("Bot2: ", address(bot2));

        vm.stopBroadcast();
    }

}