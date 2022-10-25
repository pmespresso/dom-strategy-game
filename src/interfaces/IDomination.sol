
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

enum GameStage {
    Submit,
    Reveal,
    Resolve
}

interface IDominationGame {
    function currentTurnStartTimestamp() view external returns (uint256);
    function gameStage() view external returns (GameStage);
    function move(address player, int8 direction) external;
    function players(address player) view external returns (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bytes32, bytes memory, bool);
    function interval() view external returns (uint256);
    function connect(uint256 tokenId, address byoNft) external;
    function submit(uint256 turn, bytes32 commitment) external;
    function reveal(uint256 turn, bytes32 nonce, bytes calldata data) external;
}
