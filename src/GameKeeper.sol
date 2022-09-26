// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "chainlink/v0.8/interfaces/KeeperCompatibleInterface.sol";

interface IDomStrategyGame {
    function activePlayers() external returns (uint256);
    function maxPlayers() external returns (uint256);
    function currentTurn() external returns (uint256);
    function start() external;
    function resolve(uint256 turn, address[] calldata sortedAddrs) external;
}

contract GameKeeper is KeeperCompatibleInterface {
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
            IDomStrategyGame(game).resolve(turn, sortedAddrs);
        } else {
            uint256 maxPlayers = IDomStrategyGame(game).maxPlayers();
            uint256 activePlayers = IDomStrategyGame(game).activePlayers();
            gameStartRemainingTime = int(gameStartTimestamp - block.timestamp);

            // check if max players or game start time reached
            if (activePlayers == maxPlayers || gameStartRemainingTime <= 0) {
                IDomStrategyGame(game).start();
                // now set interval to every 18 hours
                interval = 18 hours;
            }
        }
    }
}
