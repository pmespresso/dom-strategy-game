// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

import "./HelperConfig.sol";
import "../src/DominationGame.sol";
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
        ,
        ,
        uint64 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash
        ) = helperConfig.activeNetworkConfig();

        address pisko = 0x39db606889F4Db66e780630d51a259e6096C7407;
        address w1nt3r = 0xCf01547b6a3a41C459985EBA6874FEeaE0e3Fe8D;
        
        vm.startBroadcast();
        
        // test params
        // call resolve every 5 minutes
        // start game 10 minutes after deploy
        DominationGame game = new DominationGame(vrfCoordinator, link, keyHash, subscriptionId, 5 minutes);

        // Mint Domination Base Characters to test accounts
        BaseCharacter character = new BaseCharacter();
        character.mint(pisko);
        character.mint(w1nt3r);
        // TODO: Mint to Bot as well

        // Register Game as VRF Consumer
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(subscriptionId, address(game));

        console.log(msg.sender);

        vm.stopBroadcast();
    }
}