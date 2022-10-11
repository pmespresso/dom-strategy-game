// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../script/HelperConfig.sol";
import "./mocks/MockVRFCoordinatorV2.sol";
import "../DomStrategyGame.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

contract GameKeeperTest is Test {
    DomStrategyGame public game;
    MockVRFCoordinatorV2 vrfCoordinator;
    HelperConfig helper = new HelperConfig();
    uint256 public staticTime;
    uint256 public INTERVAL = 20 seconds;
    uint256 public intendedStartTime = block.timestamp + 30 seconds;

    function setUp() public {
        (
            ,
            ,
            ,
            address link,
            ,
            ,
            ,
            ,
            bytes32 keyHash
        ) = helper.activeNetworkConfig();

        vrfCoordinator = new MockVRFCoordinatorV2();
        uint64 subscriptionId = vrfCoordinator.createSubscription();
        uint96 FUND_AMOUNT = 1000 ether;
        vrfCoordinator.fundSubscription(subscriptionId, FUND_AMOUNT);

        game = new DomStrategyGame(address(vrfCoordinator), link, subscriptionId, keyHash, INTERVAL, intendedStartTime);

        staticTime = block.timestamp;
        vm.warp(staticTime);
    }

    function testCheckupReturnsFalseBeforeTime() public {
        (bool upkeepNeeded, ) = game.checkUpkeep("0x");
        assertTrue(!upkeepNeeded);
    }

    function testCheckupReturnsTrueAfterTime() public {
        vm.warp(staticTime + INTERVAL + 1); // Needs to be more than the interval
        (bool upkeepNeeded, ) = game.checkUpkeep("0x");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepUpdatesTime() public {
        // Expect to start at 31
        uint256 gameStartTime = game.gameStartTimestamp();
        // 30 seconds till start
        int256 timeRemainingTillStart = game.gameStartRemainingTime();

        assertTrue(timeRemainingTillStart == 30 seconds);

        // Fastforward to 22
        vm.warp(staticTime + INTERVAL + 1);
        
        // Act
        game.performUpkeep("0x");

        // Assert
        assertTrue(game.lastTimestamp() == block.timestamp);
        assertTrue(block.timestamp + 9 seconds == gameStartTime);
        assertTrue(game.gameStartRemainingTime() == 9 seconds);
    }

    function testFuzzingExample(bytes memory variant) public {
        // We expect this to fail, no matter how different the input is!
        vm.expectRevert(bytes("Time interval not met."));
        game.performUpkeep(variant);
    }
}
