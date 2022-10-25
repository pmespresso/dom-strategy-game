// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/VerticalBot.sol";
import "../src/BaseCharacter.sol";

interface IBaseCharacter {
    function tokensOwnedBy(address who) external view returns (uint256[] memory);
}

contract DeployBots is Script {
    function run() external {
        address gameAddr = vm.envAddress("GAME_ADDR");
        address baseCharacterAddr = vm.envAddress("BASE_CHARACTER_ADDR");

        vm.startBroadcast();

        VerticalBot verticalBot = new VerticalBot(gameAddr, baseCharacterAddr);

        verticalBot.mintDominationCharacter();

        uint256 tokenId = IBaseCharacter(baseCharacterAddr).tokensOwnedBy(address(verticalBot))[0];

        verticalBot.joinGame(baseCharacterAddr, tokenId);
        
        vm.stopBroadcast();
    }
}