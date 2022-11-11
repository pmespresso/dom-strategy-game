
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import "../src/interfaces/IBaseCharacterNFT.sol";

contract SeedBalances is Script {
    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("MUMBAI_PRIVATE_KEY");
        // address deployer = vm.addr(deployerPrivateKey);

        address game = vm.envAddress("GAME");
        address bot1 = vm.envAddress("BOT1");
        address bot2 = vm.envAddress("BOT2");
        address nft = vm.envAddress("NFT");

        vm.startBroadcast();

        (bool success, ) = address(bot1).call{value: 0.1 ether}("");
        (success, ) = address(bot2).call{value: 0.1 ether}("");

        IBaseCharacterNFT(nft).mint{ value: 0.01 ether }(address(bot1));
        IBaseCharacterNFT(nft).mint{ value: 0.01 ether }(address(bot2));

        vm.stopBroadcast();
    }
}