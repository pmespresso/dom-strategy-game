pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/BaseCharacter.sol";

contract DeployBaseCharacter is Script {
    function run() external {
        vm.startBroadcast();

        new BaseCharacter();

        vm.stopBroadcast();
    }
}