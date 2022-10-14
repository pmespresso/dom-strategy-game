// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "./HelperConfig.sol";
import "../src/DomStrategyGame.sol";
import "../src/BaseCharacter.sol";

contract DeployGame is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (
        ,
        ,
        ,
        address link,
        ,
        ,
        uint64 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash
        ) = helperConfig.activeNetworkConfig();
        
        vm.startBroadcast();
        
        // test params
        // call resolve every 10 minutes
        // start game 5 minutes after deploy
        new DomStrategyGame(vrfCoordinator, link, subscriptionId, keyHash, 10 minutes, block.timestamp + 5 minutes);

        BaseCharacter character = new BaseCharacter();

        character.mint(address(msg.sender));

        console.log(msg.sender);

        vm.stopBroadcast();
    }
}