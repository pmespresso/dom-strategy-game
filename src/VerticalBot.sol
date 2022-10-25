// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "chainlink/v0.8/AutomationCompatible.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";

import "./interfaces/IDomination.sol";
import "./interfaces/IBaseCharacterNFT.sol";

/**
    A bot the plays the game by only ever going up. If no more space is available, it will go down.
 */
contract VerticalBot is AutomationCompatible, IERC721Receiver {
    using Counters for Counters.Counter;

    address deployer;
    Counters.Counter lastUpkeepTurn = Counters.Counter(1);
    Counters.Counter nonce = Counters.Counter(1);
    uint256 interval;
    IDominationGame game;
    IBaseCharacterNFT baseCharacterNft;

    event Submitting(uint256 turn, bytes commitment);
    event Revealing(uint256 turn, bytes commitment);

    modifier onlyDeployer() {
        require(msg.sender == deployer);
        _;
    }

    constructor(address _game, address _baseCharacterNft) {
        game = IDominationGame(_game);
        deployer = msg.sender;
        baseCharacterNft = IBaseCharacterNFT(_baseCharacterNft);
        interval = game.interval();
    }

    function joinGame (address _byoNft, uint256 _tokenId) external onlyDeployer {
        game.connect(_tokenId, _byoNft);
    }

    function mintDominationCharacter() external onlyDeployer {
        baseCharacterNft.mint(address(this));
    }

    function checkUpkeep(bytes memory) public view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastUpkeepTurn.current()) >= interval;
        performData = bytes("");

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        require(upkeepNeeded, "Time interval not met.");
        
        lastUpkeepTurn.increment();

        (,,,,,,,,,uint256 y,,,) = game.players(address(this));

        int8 direction = y == 0 ? int8(1) : -1; // if at the top border, move down, otherwise move up.

        bytes memory commitment = abi.encodeWithSelector(
            game.move.selector,
            direction // move up
        );

        if (game.gameStage() == GameStage.Submit) {
            game.submit(lastUpkeepTurn.current(), keccak256(abi.encodePacked(lastUpkeepTurn.current(), bytes32(nonce.current()), commitment)));
            emit Submitting(lastUpkeepTurn.current(), commitment);
        } else if (game.gameStage() == GameStage.Reveal) {
            game.reveal(lastUpkeepTurn.current(), bytes32(nonce.current()), commitment);
            emit Revealing(lastUpkeepTurn.current(), commitment);
        }
        
        nonce.increment();
    }

    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    ) external pure returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}