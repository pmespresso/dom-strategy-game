// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "chainlink/v0.8/AutomationCompatible.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import "./interfaces/IDominationGame.sol";
import "./interfaces/IBaseCharacterNFT.sol";

struct IPlayer {
    address addr;
    address nftAddress;
    uint256 tokenId;
    uint256 balance;
    uint256 lastMoveTimestamp;
    uint256 allianceId;
    uint256 hp;
    uint256 attack;
    uint256 x;
    uint256 y;
    bytes32 pendingMoveCommitment;
    bytes pendingMove;
    bool inJail;
}

/**
    Goes right for 10 turns the left for 10 turns, whether or not it fights.
 */
contract HorizontalBot is AutomationCompatible, IERC721Receiver {
    address public deployer;
    address public gameAddr;
    address public byoNftAddr;
    uint256 public lastUpkeepTurn;
    uint256 public nonce;
    uint256 public interval;
    IDominationGame game;
    IBaseCharacterNFT baseCharacterNft;

    mapping(uint256 => bool) didSubmitForTurn;
    mapping(uint256 => bool) didRevealForTurn;
    
    event Submitting(uint256 turn, bytes commitment);
    event Revealing(uint256 turn, bytes commitment);
    event Fallback(uint256 amount, uint256 gasLeft);
    event Received(uint256 amount, uint256 gasLeft);

    modifier onlyDeployer() {
        require(msg.sender == deployer);
        _;
    }

    constructor(address _game, address _baseCharacterNft, uint256 _interval) payable {
        game = IDominationGame(_game);
        gameAddr = _game;
        deployer = msg.sender;
        baseCharacterNft = IBaseCharacterNFT(_baseCharacterNft);
        byoNftAddr = _baseCharacterNft;
        interval = _interval;
        nonce = 1;
        lastUpkeepTurn = 1;
    }

    function setByoNftAddress(address _byoNftAddr) external onlyDeployer {
        byoNftAddr = _byoNftAddr;
    }

    function setGameAddress(address _gameAddr) external onlyDeployer {
        gameAddr = _gameAddr;
    }

    function joinGame (uint256 _tokenId) external payable onlyDeployer {
        // require(address(this).balance > 0, "Send some ETH to bot to pay for gas.");
        game.connect{value: msg.value }(_tokenId, byoNftAddr);
    }

    function mintDominationCharacter() external payable onlyDeployer {
        baseCharacterNft.mint{ value: msg.value }(address(this));
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        GameStage gameStage = game.gameStage();
        uint256 currentTurn = game.currentTurn();
        uint256 currentTurnStartTimestamp = game.currentTurnStartTimestamp();
        uint256 gameUpkeepInterval = game.interval();
        uint256 nextTurnTimestamp = currentTurnStartTimestamp + gameUpkeepInterval;

        upkeepNeeded = block.timestamp >= currentTurnStartTimestamp && block.timestamp < nextTurnTimestamp;

        if (gameStage == GameStage.Submit) {
            upkeepNeeded = upkeepNeeded && !didSubmitForTurn[currentTurn];
        } else if (gameStage == GameStage.Reveal) {
            upkeepNeeded = upkeepNeeded && !didRevealForTurn[currentTurn];
        } else if (gameStage == GameStage.Finished) {
            upkeepNeeded = false;
        }

        return (upkeepNeeded, '');
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        lastUpkeepTurn += 1;

        int8 direction = lastUpkeepTurn % 10 == 0 ? int8(2) : int8(-2);

        bytes memory commitment = abi.encodeWithSelector(
            game.move.selector,
            direction
        );

        if (game.gameStage() == GameStage.Submit) {
            game.submit(lastUpkeepTurn, keccak256(abi.encodePacked(lastUpkeepTurn, bytes32(nonce), commitment)));
            didSubmitForTurn[lastUpkeepTurn] = true;
            emit Submitting(lastUpkeepTurn, commitment);
        } else if (game.gameStage() == GameStage.Reveal) {
            game.reveal(lastUpkeepTurn, bytes32(nonce), commitment);
            didRevealForTurn[lastUpkeepTurn] = true;
            emit Revealing(lastUpkeepTurn, commitment);
        } else if (game.gameStage() == GameStage.PendingWithdrawals) {
            game.withdrawWinnerPlayer();
        }
        
        nonce += 1;
    }

    function withdraw() external onlyDeployer {
        require(address(this).balance > 0, "Nothing to withdraw");
        (bool success, ) = address(payable(msg.sender)).call{value: address(this).balance}("");
        require(success, "Failed to send ETH");

        uint256[] memory tokenIds = baseCharacterNft.tokensOwnedBy(address(this));
        baseCharacterNft.safeTransferFrom(address(this), msg.sender, tokenIds[0]);

        for (uint i = 0; i < tokenIds.length; i++) {
            baseCharacterNft.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }
    }

    // Fallback function must be declared as external.5
    fallback() external payable {
        // send / transfer (forwards 2300 gas to this fallback function)
        // call (forwards all of the gas)
        emit Fallback(msg.value, gasleft());
    }

    receive() external payable {
        // custom function code
        emit Received(msg.value, gasleft());
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