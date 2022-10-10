// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "chainlink/v0.8/AutomationCompatible.sol";

interface IDomStrategyGame {
    function activePlayersCount() external returns (uint256);
    function maxPlayers() external returns (uint256);
    function currentTurn() external returns (uint256);
    function start() external;
    function resolve(uint256 turn) external;
}

contract GameKeeper is AutomationCompatible {
    uint256 public interval;
    uint256 public lastTimestamp;
    uint256 public gameStartTimestamp;
    int256 public gameStartRemainingTime;
    bool gameStarted;
    address game;

    constructor(uint256 updateInterval, uint256 _gameStartTimestamp, address _game) {
        interval = updateInterval;
        lastTimestamp = block.timestamp;
        gameStartTimestamp = _gameStartTimestamp;
        gameStartRemainingTime = int(gameStartTimestamp - block.timestamp);
        game = _game;
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

        if (gameStarted) {
            uint256 turn = IDomStrategyGame(game).currentTurn() + 1;
            // TODO: figure out how to get sortedAddrs from an offchain source to here
            // actually this doesn't necessarily need to be sorted, can be random order using VRf
            IDomStrategyGame(game).resolve(turn);
        } else {
            uint256 maxPlayers = IDomStrategyGame(game).maxPlayers();
            uint256 activePlayersCount = IDomStrategyGame(game).activePlayersCount();
            gameStartRemainingTime = int(gameStartTimestamp - block.timestamp);

            // check if max players or game start time reached
            if (activePlayersCount == maxPlayers || gameStartRemainingTime <= 0) {
                IDomStrategyGame(game).start();
                // now set interval to every 18 hours
                interval = 18 hours;
            }
        }
    }
}
