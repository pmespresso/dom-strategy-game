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
    Creates and alliance as quickly as possible or joins one if it exists already.
    Then moves around in a square.
 */
contract AllianceBot is AutomationCompatible, IERC721Receiver {
    address public deployer;
    address public gameAddr;
    address public byoNftAddr;
    uint256 public byoNftTokenId;
    uint256 public lastUpkeepTurn;
    uint256 public nonce;
    uint256 public interval;
    uint256 public STARTING_SPOILS = 0.0069 ether;
    IDominationGame game;
    IBaseCharacterNFT baseCharacterNft;

    mapping(uint256 => bool) didSubmitForTurn;
    mapping(uint256 => bool) didRevealForTurn;
    
    event JoinAlliance(uint256 indexed allianceId, uint256 indexed turn, string indexed allianceName);
    event CreateAlliance(uint256 indexed allianceId, uint256 indexed turn, string indexed allianceName);
    event Submitting(uint256 turn, bytes commitment);
    event Revealing(uint256 turn, bytes commitment);
    event Fallback(uint256 amount, uint256 gasLeft);
    event Received(uint256 amount, uint256 gasLeft);
    event WithdrewWinnings();
    event NoMoreToDo();

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
        byoNftTokenId = 0;
        interval = _interval;
        nonce = 1;
        lastUpkeepTurn = 1;
    }

    function setByoNftTokenId(uint256 _byoNftTokenId) external onlyDeployer {
        byoNftTokenId = _byoNftTokenId;
    }

    function setByoNftAddress(address _byoNftAddr) external onlyDeployer {
        byoNftAddr = _byoNftAddr;
    }

    function setGameAddress(address _gameAddr) external onlyDeployer {
        gameAddr = _gameAddr;
    }

    function joinGame (uint256 _tokenId) internal {
        game.connect{value: STARTING_SPOILS}(_tokenId, byoNftAddr);
    }

    function mintDominationCharacter() external payable onlyDeployer {
        baseCharacterNft.mint{ value: msg.value }(address(this));
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        GameStage gameStage = game.gameStage();
        bool gameStarted = game.gameStarted();
        uint256 currentTurn = game.currentTurn();
        uint256 currentTurnStartTimestamp = game.currentTurnStartTimestamp();
        uint256 gameUpkeepInterval = game.interval();
        uint256 nextTurnTimestamp = currentTurnStartTimestamp + gameUpkeepInterval;
    
        upkeepNeeded = block.timestamp >= currentTurnStartTimestamp && block.timestamp < nextTurnTimestamp;

        if (!gameStarted) {
           return (true, '');
        }

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

        (address addr,,,,,uint256 allianceId,,,,,,,) = game.players(address(this));

        if (!game.gameStarted() || addr == address(0)) {
            joinGame(byoNftTokenId);
            return;
        }

        int8 direction = lastUpkeepTurn % 2 == 0 ? int8(2) : lastUpkeepTurn % 3 == 0 ? int8(1) : lastUpkeepTurn % 5 == 0 ? int8(-1) : int8(-2);

        bytes memory commitment;
        uint256 nextAllianceId = game.nextAvailableAllianceId();

        // if not in alliance, join one or create one
        if (allianceId == 0) {
            if (nextAllianceId == 1) { // no other alliances exist
                commitment = abi.encodeWithSelector(game.createAlliance.selector, address(this), 3, "Beep Boop Alliance");
                emit CreateAlliance(nextAllianceId, lastUpkeepTurn, "Beep Boop Alliance");
            } else {
                (,,, uint256 membersCount, uint256 maxMembers,, string memory allianceName) = game.alliances(nextAllianceId - 1);

                if (membersCount < maxMembers) {
                    commitment = abi.encodeWithSelector(game.joinAlliance.selector, allianceId);
                    emit JoinAlliance(allianceId, lastUpkeepTurn, allianceName);
                }
                
            }
        } else {
            commitment = abi.encodeWithSelector(
                game.move.selector,
                direction
            );
        }

        if (game.gameStage() == GameStage.Submit) {
            game.submit(lastUpkeepTurn, keccak256(abi.encodePacked(lastUpkeepTurn, bytes32(nonce), commitment)));
            didSubmitForTurn[lastUpkeepTurn] = true;
            emit Submitting(lastUpkeepTurn, commitment);
        } else if (game.gameStage() == GameStage.Reveal) {
            game.reveal(lastUpkeepTurn, bytes32(nonce), commitment);
            didRevealForTurn[lastUpkeepTurn] = true;
            emit Revealing(lastUpkeepTurn, commitment);
        } else if (game.gameStage() == GameStage.PendingWithdrawals) {
            if (game.spoils(address(this)) > 0) {
                game.withdrawWinnerPlayer();
                emit WithdrewWinnings();
            } else if (game.winnerAllianceId() == allianceId) {
                game.withdrawWinnerAlliance();
                emit WithdrewWinnings();
            } else {
                emit NoMoreToDo();
            }
            emit NoMoreToDo();
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