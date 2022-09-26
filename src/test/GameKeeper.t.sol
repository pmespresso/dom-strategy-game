// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../GameKeeper.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

contract GameKeeperTest is Test {
    GameKeeper public gameKeeper;
    uint256 public staticTime;
    uint256 public INTERVAL = 20 seconds;
    uint256 public intendedStartTime = block.timestamp + 30 seconds;

    function setUp() public {
        staticTime = block.timestamp;
        gameKeeper = new GameKeeper(INTERVAL, intendedStartTime);
        vm.warp(staticTime);
    }

    function testCheckupReturnsFalseBeforeTime() public {
        (bool upkeepNeeded, ) = gameKeeper.checkUpkeep("0x");
        assertTrue(!upkeepNeeded);
    }

    function testCheckupReturnsTrueAfterTime() public {
        vm.warp(staticTime + INTERVAL + 1); // Needs to be more than the interval
        (bool upkeepNeeded, ) = gameKeeper.checkUpkeep("0x");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepUpdatesTime() public {
        // Expect to start at 31
        uint256 gameStartTime = gameKeeper.gameStartTimestamp();
        // 30 seconds till start
        uint256 timeRemainingTillStart = gameKeeper.gameStartRemainingTime();

        assertTrue(timeRemainingTillStart == 30 seconds);

        // Fastforward to 22
        vm.warp(staticTime + INTERVAL + 1);
        
        // Act
        gameKeeper.performUpkeep("0x");

        // Assert
        assertTrue(gameKeeper.lastTimestamp() == block.timestamp);
        assertTrue(block.timestamp + 9 seconds == gameStartTime);
        assertTrue(gameKeeper.gameStartRemainingTime() == 9 seconds);
    }

    function testFuzzingExample(bytes memory variant) public {
        // We expect this to fail, no matter how different the input is!
        vm.expectRevert(bytes("Time interval not met."));
        gameKeeper.performUpkeep(variant);
    }
}
