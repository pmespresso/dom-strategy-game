
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

enum GameStage {
    Submit,
    Reveal,
    Resolve,
    PendingWithdrawals,
    Finished
}

struct Player {
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

struct Alliance {
    address admin;
    uint256 id;
    uint256 activeMembersCount; // if in Jail, not active
    uint256 membersCount;
    uint256 maxMembers;
    uint256 totalBalance; // used for calc cut of spoils in win condition
    string name;
}

struct JailCell {
    uint256 x;
    uint256 y;
}

interface IDominationGame {
    error LoserTriedWithdraw();
    error OnlyWinningAllianceMember();

    event AttemptJailBreak(address indexed who, uint256 x, uint256 y);
    event AllianceCreated(address indexed admin, uint256 indexed allianceId, string name);
    event AllianceMemberJoined(uint256 indexed allianceId, address indexed player);
    event AllianceMemberLeft(uint256 indexed allianceId,address indexed player);
    event BadMovePenalty(uint256 indexed turn, address indexed player, bytes details);
    event BattleCommenced(address indexed player1, address indexed defender);
    event BattleFinished(address indexed winner, uint256 indexed spoils);
    event BattleStalemate(uint256 indexed attackerHp, uint256 indexed defenderHp);
    event CheckingWinCondition(uint256 indexed activeAlliancesCount, uint256 indexed  activePlayersCount);
    event Constructed(address indexed owner, uint64 indexed subscriptionId, uint256 indexed _gameStartTimestamp);
    event DamageDealt(address indexed by, address indexed to, uint256 indexed amount);
    event GameStartDelayed(uint256 indexed newStartTimeStamp);
    event GameFinished(uint256 indexed turn, uint256 indexed winningTeamTotalSpoils);
    event Fallback(uint256 indexed value, uint256 indexed gasLeft);
    event Jail(address indexed who, uint256 indexed inmatesCount);
    event JailBreak(address indexed who, uint256 newInmatesCount);
    event Joined(address indexed addr);
    event Move(address indexed who, uint newX, uint newY);
    event NewGameStage(GameStage indexed newGameStage, uint256 indexed turn);
    event NftConfiscated(address indexed who, address indexed nftAddress, uint256 indexed tokenId);
    event NoReveal(address indexed who, uint256 indexed turn);
    event NoSubmit(address indexed who, uint256 indexed turn);
    event Received(uint256 indexed value, uint256 indexed gasLeft);
    event Rest(address indexed who, uint256 indexed x, uint256 indexed y);
    event ReturnedRandomness(uint256[] randomWords);
    event Revealed(address indexed addr, uint256 indexed turn, bytes32 nonce, bytes data);
    event RolledDice(uint256 indexed turn, uint256 indexed vrf_request_id);
    event SkipInmateTurn(address indexed who, uint256 indexed turn);
    event Submitted(address indexed addr, uint256 indexed turn, bytes32 commitment);
    event TurnStarted(uint256 indexed turn, uint256 timestamp);
    event UpkeepCheck(uint256 indexed currentTimestamp, uint256 indexed lastUpkeepTimestamp, bool indexed upkeepNeeded);
    event WinnerPlayer(address indexed winner);
    event WinnerAlliance(uint indexed allianceId);
    event WinnerWithdrawSpoils(address indexed winner, uint256 indexed spoils);
    

    function currentTurnStartTimestamp() view external returns (uint256);
    function gameStage() view external returns (GameStage);
    function move(address player, int8 direction) external;
    function players(address player) view external returns (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bytes32, bytes memory, bool);
    function interval() view external returns (uint256);
    function connect(uint256 tokenId, address byoNft) external payable;
    function submit(uint256 turn, bytes32 commitment) external;
    function reveal(uint256 turn, bytes32 nonce, bytes calldata data) external;
}


