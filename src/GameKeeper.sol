// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "chainlink/v0.8/interfaces/KeeperCompatibleInterface.sol";

contract GameKeeper is KeeperCompatibleInterface {
    uint256 public interval;
    uint256 public lastTimestamp;
    uint256 public gameStartTimestamp;
    uint256 public gameStartRemainingTime;

    constructor(uint256 updateInterval, uint256 _gameStartTimestamp) {
        interval = updateInterval;
        lastTimestamp = block.timestamp;
        gameStartTimestamp = _gameStartTimestamp;
        gameStartRemainingTime = gameStartTimestamp - block.timestamp;
    }

    function checkUpkeep(bytes memory) public view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimestamp) > interval;
        performData = bytes("");

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        require(upkeepNeeded, "Time interval not met.");
        
        lastTimestamp = block.timestamp;
        gameStartRemainingTime = gameStartTimestamp - block.timestamp;
    }
}
