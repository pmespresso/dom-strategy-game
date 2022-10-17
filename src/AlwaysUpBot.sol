// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "chainlink/v0.8/AutomationCompatible.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import "./DomStrategyGame.sol";

interface IDominationGame {
    function currentTurnStartTimestamp() view external returns (uint256);
    function players(address player) view external returns (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bytes32, bytes memory, bool);
    function interval() view external returns (uint256);
    function connect(uint256 tokenId, address byoNft) external;
    function submit(uint256 turn, bytes32 commitment) external;
    function reveal(uint256 turn, bytes32 nonce, bytes calldata data) external;
}

/**
    A bot the plays the game by only ever going up. If no more space is available, it will go down.
 */
contract AlwaysUpBot is AutomationCompatible, IERC721Receiver {
    address deployer;
    uint256 lastUpkeepTurn = 1;
    uint256 nonce = 1;
    uint256 interval;
    IDominationGame game;

    modifier onlyDeployer() {
        require(msg.sender == deployer);
        _;
    }

    constructor(address _game, address _deployer) {
        game = IDominationGame(_game);
        deployer = _deployer;
        interval = game.interval();
    }

    function joinGame (address _byoNft, uint256 _tokenId) external onlyDeployer {
        game.connect(_tokenId, _byoNft);
    }

    function checkUpkeep(bytes memory) public view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastUpkeepTurn) >= interval;
        performData = bytes("");

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        require(upkeepNeeded, "Time interval not met.");
        
        lastUpkeepTurn += 1;

        (,,,,,,,,,uint256 y,,,) = game.players(address(this));

        int8 direction = y == 0 ? int8(1) : -1; // if at the top border, move down, otherwise move up.

        bytes memory commitment = abi.encodeWithSelector(
            DomStrategyGame.move.selector,
            direction // move up
        );

        if (block.timestamp <= game.currentTurnStartTimestamp() + interval) {
            game.submit(lastUpkeepTurn, keccak256(abi.encodePacked(lastUpkeepTurn, bytes32(nonce), commitment)));
        } else {
            game.reveal(lastUpkeepTurn, bytes32(nonce), commitment);
        }
    }

    //
    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    ) external pure returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}