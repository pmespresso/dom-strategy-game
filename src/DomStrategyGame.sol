// SPDX-License-Identifier: CC0
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "chainlink/v0.8/interfaces/LinkTokenInterface.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/VRFConsumerBaseV2.sol";

import "./Loot.sol";

struct Player {
    // TODO: Pack this struct once we know all the fields
    address addr;
    address nftAddress;
    uint256 balance;
    uint256 tokenId;
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
    uint256 membersCount;
    uint256 maxMembers;
    string name;
}

contract DomStrategyGame is IERC721Receiver, VRFConsumerBaseV2 {
    Loot public loot;
    mapping(address => Player) public players;
    mapping(uint256 => Alliance) public alliances;
    mapping(uint256 => address) public allianceAdmins;
    mapping(address => uint256) public spoils;
    mapping(uint256 => mapping(uint256 => address)) public playingField;

    // bring your own NFT kinda
    // BAYC, Sappy Seal, Pudgy Penguins, Azuki, Doodles
    // address[] allowedNFTs = [
    //     0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D, 0x364C828eE171616a39897688A831c2499aD972ec, 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8, 0xED5AF388653567Af2F388E6224dC7C4b3241C544, 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e
    // ];

    VRFCoordinatorV2Interface immutable COORDINATOR;
    LinkTokenInterface immutable LINKTOKEN;
    address public vrf_owner;
    bytes32 immutable vrf_keyHash;
    uint16 immutable vrf_requestConfirmations = 3;
    uint32 immutable vrf_callbackGasLimit = 2_500_000;
    uint32 immutable vrf_numWords = 3;
    uint64 public vrf_subscriptionId;
    uint256 public randomness;
    uint256 public vrf_requestId;
    uint256 nextAvailableAllianceId = 0;
    uint256 public currentTurn;
    uint256 public currentTurnStartTimestamp;
    uint256 public activePlayers;
    uint256 public fieldSize;
    // TODO make random to prevent position sniping...?
    uint256 public nextAvailableRow = 0;
    uint256 public nextAvailableCol = 0;
    uint256[2] internal jailCell;

    event ReturnedRandomness(uint256[] randomWords);
    event Constructed(address owner, uint64 subscriptionId);
    event Joined(address indexed addr);
    event TurnStarted(uint256 indexed turn, uint256 timestamp);
    event Submitted(
        address indexed addr,
        uint256 indexed turn,
        bytes32 commitment
    );
    event Revealed(
        address indexed addr,
        uint256 indexed turn,
        bytes32 nonce,
        bytes data
    );
    event BadMovePenalty(
        uint256 indexed turn,
        address indexed player,
        bytes details
    );

    event AllianceCreated(
        address indexed admin,
        uint256 indexed allianceId,
        string name
    );
    event AllianceMemberJoined(
        uint256 indexed allianceId,
        address indexed player
    );
    event AllianceMemberLeft(
        uint256 indexed allianceId,
        address indexed player
    );
    event Move(address indexed who, uint newX, uint newY);
    event BattleCommenced(address indexed player1, address indexed player2);
    event BattleFinished(address indexed winner, uint256 spoils);

    constructor(
        Loot _loot,
        address _vrfCoordinator,
        address _linkToken,
        uint64 _subscriptionId,
        bytes32 _keyHash) VRFConsumerBaseV2(_vrfCoordinator)
    {
        loot = _loot;
        fieldSize = 100;

        // VRF
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(_linkToken);
        vrf_keyHash = _keyHash;
        vrf_owner = msg.sender;
        vrf_subscriptionId = _subscriptionId;

        emit Constructed(vrf_owner, vrf_subscriptionId);
    }

    function init() external {
        requestRandomWords();
    }

    function connect(uint256 tokenId, address byoNft) external payable {
        require(currentTurn == 0, "Already started");
        require(players[msg.sender].balance == 0, "Already joined");
        require(msg.value > 0, "Send some eth");

        // prove ownership of one of the NFTs in the allowList
        uint256 nftBalance = IERC721(byoNft).balanceOf(msg.sender);
        require(nftBalance > 0, "You dont own this NFT you liar");

        IERC721(byoNft).safeTransferFrom(msg.sender, address(this), tokenId, "");

        Player memory player = Player({
            addr: msg.sender,
            nftAddress: byoNft == address(0) ? address(loot) : byoNft,
            balance: msg.value,
            tokenId: tokenId,
            lastMoveTimestamp: block.timestamp,
            allianceId: 0,
            hp: 1000,
            attack: 10,
            x: nextAvailableCol,
            y: nextAvailableRow,
            pendingMoveCommitment: bytes32(0),
            pendingMove: "",
            inJail: false
        });

        playingField[nextAvailableRow][nextAvailableCol] = msg.sender;
        spoils[msg.sender] = msg.value;
        players[msg.sender] = player;
        activePlayers += 1;
        nextAvailableCol = (nextAvailableCol + 2) % fieldSize;
        nextAvailableRow = nextAvailableCol == 0 ? nextAvailableRow + 1 : nextAvailableRow;

        emit Joined(msg.sender);
    }
    // TODO: Somebody needs to call this, maybe make this a Keeper managed Cron job?
    function start() external {
        require(currentTurn == 0, "Already started");
        require(activePlayers > 1, "No players");
        require(randomness != 0, "Need randomness for jail cell");

        currentTurn = 1;
        currentTurnStartTimestamp = block.timestamp;

        jailCell = [randomness / 1e75, randomness % 99];

        emit TurnStarted(currentTurn, currentTurnStartTimestamp);
    }

    function submit(uint256 turn, bytes32 commitment) external {
        require(currentTurn > 0, "Not started");
        require(turn == currentTurn, "Stale tx");
        require(block.timestamp <= currentTurnStartTimestamp + 18 hours);

        players[msg.sender].pendingMoveCommitment = commitment;

        emit Submitted(msg.sender, currentTurn, commitment);
    }

    function reveal(
        uint256 turn,
        bytes32 nonce,
        bytes calldata data
    ) external {
        require(turn == currentTurn, "Stale tx");
        require(block.timestamp > currentTurnStartTimestamp + 18 hours);
        require(block.timestamp < currentTurnStartTimestamp + 36 hours);

        bytes32 commitment = players[msg.sender].pendingMoveCommitment;
        bytes32 proof = keccak256(abi.encodePacked(turn, nonce, data));

        console.log("Commitment");
        console.logBytes32(commitment);
        console.log("Proof");
        console.logBytes32(proof);

        require(commitment == proof, "No cheating");

        players[msg.sender].pendingMove = data;

        emit Revealed(msg.sender, currentTurn, nonce, data);
    }

    // who rolls the dice and when?
    function rollDice(uint256 turn) external {
        require(turn == currentTurn, "Stale tx");
        // require(randomness == 0, "Already rolled");
        // require(vrf_requestId == 0, "Already rolling");
        // require(block.timestamp > currentTurnStartTimestamp + 18 hours);

        requestRandomWords();
    }

    // The turns are processed in random order. The contract offloads sorting the players
    // list off-chain to save gas
    function resolve(uint256 turn, address[] calldata sortedAddrs) external {
        require(turn == currentTurn, "Stale tx");
        require(randomness != 0, "Roll the die first");
        require(sortedAddrs.length == activePlayers, "Not enough players");
        // require(block.timestamp > currentTurnStartTimestamp + 36 hours);

        if (turn % 5 == 0) {
            fieldSize -= 2;
        }

        // TODO: this will exceed block gas limit eventually, need to split `resolve` in a way that it can be called incrementally
        for (uint256 i = 0; i < sortedAddrs.length; i++) {
            address addr = sortedAddrs[i];
            Player storage player = players[addr];
            
            // TODO: What did w1nt3r intend with sorting the hashed addresses?
            // bytes32 currentHash = keccak256(abi.encodePacked(addr, randomness));
            // require(currentHash > lastHash, "Not sorted");
            // lastHash = currentHash;

            (bool success, bytes memory err) = address(this).call(player.pendingMove);

            if (!success) {
                // Player submitted a bad move
                // TODO: check underflow, kick if out of spoils
                player.balance -= 0.05 ether;
                emit BadMovePenalty(turn, addr, err);
            }

            // Outside the field, apply storm damage
            if (player.x > fieldSize || player.y > fieldSize) {
                // TODO: Check for underflow, emit event
                player.hp -= 10;
            }

            player.pendingMove = "";
            player.pendingMoveCommitment = bytes32(0);
        }

        randomness = 0;
        currentTurn += 1;
        currentTurnStartTimestamp = block.timestamp;

        emit TurnStarted(currentTurn, currentTurnStartTimestamp);
    }

    /**
        @param direction: 1=up, 2=down, 3=left, 4=right
     */

    function move(address player, int8 direction) public {
        require(msg.sender == address(this), "Only via submit/reveal");
        Player storage playa = players[player];
        // Change x & y depending on direction
        playingField[playa.x][playa.y] = address(0);
        if (direction == 1) { // up
            require(playa.y - 1 > 0, "Cannot move up past the edge.");
            playa.y = playa.y -  1;
        } else if (direction == 2) { // down
            require(playa.y + 1 < fieldSize, "Cannot move down past the edge.");
            playa.y = playa.y + 1;
        } else if (direction == 3) { // left
            require(playa.x - 1 > 0, "Cannot move left past the edge.");
            playa.x = playa.x - 1;
        } else if (direction == 4) { // right
            require(playa.x + 1 < fieldSize, "Cannot move right past the edge.");
            playa.x = playa.x + 1;
        }
        playingField[playa.x][playa.y] = player;
    }

    function rest(address player) public {
        require(msg.sender == address(this), "Only via submit/reveal");
        players[player].hp += 2;
    }

    function createAlliance(address player, uint256 maxMembers, string calldata name) public {
        require(msg.sender == address(this), "Only via submit/reveal");
        require(players[player].allianceId == 0, "Already in alliance");

        players[player].allianceId = nextAvailableAllianceId;
        allianceAdmins[nextAvailableAllianceId] = player;

        Alliance memory newAlliance = Alliance({
            admin: player,
            id: nextAvailableAllianceId,
            membersCount: 1,
            maxMembers: maxMembers,
            name: name
        });
        alliances[nextAvailableAllianceId] = newAlliance;
        nextAvailableAllianceId += 1;

        emit AllianceCreated(player, nextAvailableAllianceId, name);
    }

    function joinAlliance(
        address player,
        uint256 allianceId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(msg.sender == address(this), "Only via submit/reveal");

        // Admin must sign the application off-chain. Applications are per-move based, so the player
        // can't reuse the application from the previous move
        bytes memory application = abi.encodePacked(currentTurn, allianceId);

        bytes32 hash = keccak256(application);
        // address admin = ECDSA.recover(hash, signature
        address admin = ecrecover(hash, v, r, s);

        require(allianceAdmins[allianceId] == admin, "Not signed by admin");
        players[player].allianceId = allianceId;
        
        Alliance memory alliance = alliances[allianceId];
        
        require(alliance.membersCount < alliance.maxMembers - 1, "Cannot exceed max members count.");

        alliances[allianceId].membersCount += 1;

        emit AllianceMemberJoined(players[player].allianceId, player);
    }

    function leaveAlliance(address player) public {
        require(msg.sender == address(this), "Only via submit/reveal");
        require(players[player].allianceId != 0, "Not in alliance");
        require(player != allianceAdmins[players[player].allianceId], "Admin canot leave alliance");

        uint256 allianceId = players[player].allianceId;
        players[player].allianceId = 0;
        alliances[allianceId].membersCount -= 1;

        emit AllianceMemberLeft(allianceId, player);
    }

    function _battle(address player1Addr, address player2Addr) internal {
        require(player1Addr != player2Addr, "Cannot fight yourself");

        Player storage player1 = players[player1Addr];
        Player storage player2 = players[player2Addr];

        emit BattleCommenced(player1Addr, player2Addr);

        // take randomness, multiply it against attack to get what % of total attack damange is done to opponent's hp, make it at least 1
        uint effectiveDamage1 = (player1.attack / (randomness % 99)) + 1;
        uint effectiveDamage2 = (player2.attack / (randomness % 99)) + 1;

        // There is an importance of who goes first, because if both have an effective damage enough to kill the other, the one who strikes first would win. Leave it to chance. Maybe later leave it to an item/powerup.
        if (randomness % 2 == 0) {
            // Case 1: player 1 lost
            if (player1.hp - effectiveDamage2 <= 0) {
                // player1 becomes prisoner of war
                player1.hp = 0;
                player1.x = jailCell[0];
                player1.y = jailCell[1];
                player1.inJail = true;

                // Player 2 takes Player1's spoils
                (bool sent,) = player2.addr.call{value: spoils[player1.addr]}("");
                spoils[player2.addr] += spoils[player1.addr];
                spoils[player1.addr] = 0;
                require(sent, "Failed to send spoils");
            } else if (player2.hp - effectiveDamage1 <= 0) {// Case 2: player 2 lost
                player2.hp = 0;
                player2.x = jailCell[0];
                player2.y = jailCell[1];
                player2.inJail = true;

                // Player 1 takes Player2's spoils
                (bool sent,) = player1.addr.call{value: spoils[player2.addr]}("");
                spoils[player1.addr] += spoils[player2.addr];
                spoils[player2.addr] = 0;
                require(sent, "Failed to send spoils");
            } else {
                player1.hp -= effectiveDamage2;
                player2.hp -= effectiveDamage1;
            }
        } else { // same as above, but player2 goes first
            if (player2.hp - effectiveDamage1 <= 0) {// Case 2: player 2 lost
                player2.hp = 0;
                player2.x = jailCell[0];
                player2.y = jailCell[1];
                player2.inJail = true;

                // Player 1 takes Player2's spoils
                (bool sent,) = player1.addr.call{value: spoils[player2.addr]}("");

                spoils[player1.addr] += spoils[player2.addr];
                spoils[player2.addr] = 0;
                require(sent, "Failed to send spoils");
            } else if (player1.hp - effectiveDamage2 <= 0) {
                // player1 becomes prisoner of war
                player1.hp = 0;
                player1.x = jailCell[0];
                player1.y = jailCell[1];
                player1.inJail = true;

                // Player 2 takes Player1's spoils
                (bool sent,) = player2.addr.call{value: spoils[player1.addr]}("");
                spoils[player1.addr] += spoils[player2.addr];
                spoils[player2.addr] = 0;
                require(sent, "Failed to send spoils");
            } else {
                player1.hp -= effectiveDamage2;
                player2.hp -= effectiveDamage1;
            }
        }
    }

    // Callbacks
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        require(vrf_requestId == requestId);

        randomness = randomWords[0];
        vrf_requestId = 0;
        emit ReturnedRandomness(randomWords);
    }

    /**
    * @notice Requests randomness
    * Assumes the subscription is funded sufficiently; "Words" refers to unit of data in Computer Science
    */
    function requestRandomWords() public onlyOwner {
        // Will revert if subscription is not set and funded.
        vrf_requestId = COORDINATOR.requestRandomWords(
        vrf_keyHash,
        vrf_subscriptionId,
        vrf_requestConfirmations,
        vrf_callbackGasLimit,
        vrf_numWords
        );
    }

    modifier onlyOwner() {
        require(msg.sender == vrf_owner);
        _;
    }

    function setSubscriptionId(uint64 subId) public onlyOwner {
        vrf_subscriptionId = subId;
    }

    function setOwner(address owner) public onlyOwner {
        vrf_owner = owner;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        // require(msg.sender == address(loot) || msg.sender == address(bayc));
        return IERC721Receiver.onERC721Received.selector;
    }
}
