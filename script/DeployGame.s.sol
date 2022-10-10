// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

        DomStrategyGame game = new DomStrategyGame(vrfCoordinator, link, subscriptionId, keyHash, 10 minutes, block.timestamp + 10 minutes);

        BaseCharacter character = new BaseCharacter();

        character.mint(address(msg.sender));

        console.log(msg.sender);

        vm.stopBroadcast();
    }
}