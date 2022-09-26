// SPDX-License-Identifier: MIT
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

struct JailCell {
    uint256 x;
    uint256 y;
}

contract DomStrategyGame is IERC721Receiver, VRFConsumerBaseV2 {
    Loot public loot;
    JailCell public jailCell;
    mapping(address => Player) public players;
    mapping(uint256 => Alliance) public alliances;
    mapping(uint256 => address[]) public allianceMembers;
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
    address public winnerPlayer;
    uint256 public winnerAllianceId;
    address public vrf_owner;
    address[] inmates;
    bytes32 immutable vrf_keyHash;
    uint16 immutable vrf_requestConfirmations = 3;
    uint32 immutable vrf_callbackGasLimit = 2_500_000;
    uint32 immutable vrf_numWords = 3;
    uint64 public vrf_subscriptionId;
    uint256 public randomness;
    uint256 public vrf_requestId;
    uint256 nextAvailableAllianceId = 1; // start at 1 because 0 means you ain't joined one yet
    uint256 public currentTurn;
    uint256 public currentTurnStartTimestamp;
    uint256 public constant maxPlayers = 100;
    uint256 public activePlayers;
    uint256 public activeAlliances;
    uint256 public winningTeamSpoils;

    uint256 public fieldSize;
    // TODO make random to prevent position sniping...?
    uint256 public nextAvailableRow = 0;
    uint256 public nextAvailableCol = 0;

    error LoserTriedWithdraw();
    error OnlyWinningAllianceMember();

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
    event DamageDealt(address indexed by, address indexed to, uint256 indexed amount);
    event BattleCommenced(address indexed player1, address indexed defender);
    event BattleFinished(address indexed winner, uint256 indexed spoils);
    event WinnerPlayer(address indexed winner);
    event WinnerAlliance(uint indexed allianceId);
    event WinnerWithdrawSpoils(address indexed winner, uint256 indexed spoils);
    constructor(
        Loot _loot,
        address _vrfCoordinator,
        address _linkToken,
        uint64 _subscriptionId,
        bytes32 _keyHash) VRFConsumerBaseV2(_vrfCoordinator)
    payable {
        loot = _loot;
        fieldSize = maxPlayers; // also the max players

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
    
    // FIXME: dev only (use vm.load)
    function setPlayingField(uint x, uint y, address addr) public {
        playingField[x][y] = addr;
    }

    function connect(uint256 tokenId, address byoNft) external payable {
        require(currentTurn == 0, "Already started");
        require(spoils[msg.sender] == 0, "Already joined");
        // Your share of the spoils if you win as part of an alliance are proportional to how much you paid to connect.
        require(msg.value > 0, "Send some eth");

        // N.B. for now just verify ownership, later maybe put it up as collateral as the spoils, instead of the ETH balance.
        // prove ownership of one of the NFTs in the allowList
        uint256 nftBalance = IERC721(byoNft).balanceOf(msg.sender);
        require(nftBalance > 0, "You dont own this NFT you liar");

        Player memory player = Player({
            addr: msg.sender,
            nftAddress: byoNft == address(0) ? address(loot) : byoNft,
            balance: msg.value, // balance can be used to buy shit
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
        // every independent player initially gets counted as an alliance, when they join or leave  or die, retally
        activeAlliances += 1;
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

        jailCell = JailCell({ x: randomness / 1e75, y: randomness % 99});

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

        require(commitment == proof, "No cheating");

        players[msg.sender].pendingMove = data;

        emit Revealed(msg.sender, currentTurn, nonce, data);
    }

    // N.B. roll dice should be done by Chainlink Keeprs
    function rollDice(uint256 turn) external {
        require(turn == currentTurn, "Stale tx");
        require(block.timestamp > currentTurnStartTimestamp + 18 hours);

        requestRandomWords();
    }

    // The turns are processed in random order. The contract offloads sorting the players
    // list off-chain to save gas
    function resolve(uint256 turn, address[] calldata sortedAddrs) external {
        require(turn == currentTurn, "Stale tx");
        require(randomness != 0, "Roll the die first");
        require(sortedAddrs.length == activePlayers, "Not enough players");
        require(block.timestamp > currentTurnStartTimestamp + 18 hours);

        if (turn % 5 == 0) {
            fieldSize -= 2;
        }

        // TODO: this will exceed block gas limit eventually, need to split `resolve` in a way that it can be called incrementally
        for (uint256 i = 0; i < sortedAddrs.length; i++) {
            address addr = sortedAddrs[i];
            Player storage player = players[addr];

            (bool success, bytes memory err) = address(this).call(player.pendingMove);

            if (!success) {
                // Player submitted a bad move
                if (int(player.balance - 0.05 ether) >= 0) {
                    player.balance -= 0.05 ether;
                    emit BadMovePenalty(turn, addr, err);
                } else {
                    sendToJail(player);
                }
            }

            // Outside the field, apply storm damage
            if (player.x > fieldSize || player.y > fieldSize) {
                if (int(player.hp - 10) >= 0) {
                    player.hp -= 10;
                    emit DamageDealt(address(this), player.addr, 10);
                } else {
                    // if he dies, spoils just get added to the total winningTeamSpoils and he goes to jail
                    winningTeamSpoils += spoils[player.addr];
                    sendToJail(player);
                }
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
        If you try to move into an occupied cell, you need to battle. 
        If you do enough damage you take their spoils and move into their cell. If you only do some damage but they have hp remaining, you don't move.
     */
     // TODO: surely I can clean this up
    function move(address player, int8 direction) public {
        require(msg.sender == address(this), "Only via submit/reveal");
        Player storage invader = players[player];

        // Change x & y depending on direction
        if (direction == 1) { // up
            require(int(invader.y - 1) >= 0, "Cannot move up past the edge.");
            address currentOccupant = playingField[invader.x][invader.y - 1];

        if (checkIfCanAttack(invader.addr, currentOccupant)) {            
            // moving logic based on battle result handled in here
                _battle(player, currentOccupant);
            } else {
                playingField[invader.x][invader.y] = address(0);
                invader.y = invader.y -  1;
            }
        } else if (direction == 2) { // down
            require(invader.y + 1 < fieldSize, "Cannot move down past the edge.");
            address currentOccupant = playingField[invader.x][invader.y + 1];

            if (checkIfCanAttack(invader.addr, currentOccupant)) {
                _battle(player, currentOccupant);
            } else {
                playingField[invader.x][invader.y] = address(0);
                invader.y = invader.y + 1;
            }
        } else if (direction == 3) { // left
            require(int(invader.x - 1) >= 0, "Cannot move left past the edge.");
            address currentOccupant = playingField[invader.x - 1][invader.y];

            if (checkIfCanAttack(invader.addr, currentOccupant)) {
                _battle(player, currentOccupant);
            } else {
                playingField[invader.x][invader.y] = address(0);
                invader.x = invader.x - 1;
            }
        } else if (direction == 4) { // right
            require(invader.x + 1 < fieldSize, "Cannot move right past the edge.");
            address currentOccupant = playingField[invader.x + 1][invader.y];

            if (checkIfCanAttack(invader.addr, currentOccupant)) {
                _battle(player, currentOccupant);
            } else {
                playingField[invader.x][invader.y] = address(0);
                invader.x = invader.x + 1;
            }
        }
        playingField[invader.x][invader.y] = player;
        emit Move(invader.addr, invader.x, invader.y);
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
        if (allianceMembers[nextAvailableAllianceId].length > 0) {
            allianceMembers[nextAvailableAllianceId].push(player);
        } else {
            allianceMembers[nextAvailableAllianceId] = [player];
        }
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
        if (allianceMembers[allianceId].length > 0) {
            allianceMembers[allianceId].push(player);
        } else {
            allianceMembers[allianceId] = [player];
        }
        
        activeAlliances -= 1;

        console.log("joinAlliance()...active alliances: ", activeAlliances);

        emit AllianceMemberJoined(players[player].allianceId, player);
    }

    function leaveAlliance(address player) public {
        require(msg.sender == address(this), "Only via submit/reveal");
        uint256 allianceId = players[player].allianceId;
        require(allianceId != 0, "Not in alliance");
        require(player != allianceAdmins[players[player].allianceId], "Admin canot leave alliance");

        players[player].allianceId = 0;
        
        for (uint256 i = 0; i < alliances[allianceId].membersCount; i++) {
            if (allianceMembers[allianceId][i] == player) {
                delete allianceMembers[i];
            }
        }

        alliances[allianceId].membersCount -= 1;
        activeAlliances += 1;

        emit AllianceMemberLeft(allianceId, player);
    }
    
    function withdrawWinnerAlliance() onlyWinningAllianceMember public {
        Alliance memory winningAlliance = alliances[winnerAllianceId];

        uint256 myCut = winningTeamSpoils / winningAlliance.membersCount;

        (bool sent, ) = msg.sender.call{ value: myCut }("");

        require(sent, "Failed to withdraw spoils");
    }

    function withdrawWinnerPlayer() onlyWinner public {
        (bool sent, ) = winnerPlayer.call{ value: spoils[winnerPlayer] }("");
        require(sent, "Failed to withdraw winnings");
        spoils[winnerPlayer] = 0;
        emit WinnerWithdrawSpoils(winnerPlayer, spoils[winnerPlayer]);
    }

    /**** Internal Functions *****/

    function calcWinningAllianceSpoils() internal {
        require(winnerAllianceId != 0);
        
        address[] memory winners = allianceMembers[winnerAllianceId];

        console.log("calcWinningAllianceSpoils(): ");

        uint256 totalSpoils = 0;

        for (uint256 i = 0; i < winners.length; i++) {
            totalSpoils += spoils[winners[i]];
        }

        winningTeamSpoils = totalSpoils;
    }

    function checkIfCanAttack(address meAddr, address otherGuyAddr) internal view returns (bool) {
        Player memory me = players[meAddr];
        Player memory otherGuy = players[otherGuyAddr];

        if (otherGuyAddr == address(0)) { // other guy is address(0)
            return false;
        } else if (otherGuy.allianceId == 0) { // other guy not in an alliance
            return true;
        } else if (me.allianceId == otherGuy.allianceId) { // we're in the same alliance
            return false;
        } else if (otherGuy.allianceId != me.allianceId) { // the other guy is in some alliance but we're not in the same alliance
            return true;
        } else {
            return false;
        }
    }

    /**
        @param attackerAddr the player who initiates the battle by caling move() into the defender's space
        @param defenderAddr the player who just called rest() minding his own business, or just was unfortunate in the move order, i.e. PlayerA and PlayerB both move to Cell{1,3} but if PlayerA is there first, he will have to defend.

        In reality they both attack each other but the attacker will go first.
     */
    function _battle(address attackerAddr, address defenderAddr) internal {
        require(attackerAddr != defenderAddr, "Cannot fight yourself");

        Player storage attacker = players[attackerAddr];
        Player storage defender = players[defenderAddr];

        require(attacker.allianceId == 0 || defender.allianceId == 0 || attacker.allianceId != defender.allianceId, "Allies do not fight");

        emit BattleCommenced(attackerAddr, defenderAddr);

        // take randomness, multiply it against attack to get what % of total attack damange is done to opponent's hp, make it at least 1
        uint256 effectiveDamage1 = (attacker.attack / (randomness % 99)) + 1;
        uint256 effectiveDamage2 = (defender.attack / (randomness % 99)) + 1;

        // Attacker goes first. There is an importance of who goes first, because if both have an effective damage enough to kill the other, the one who strikes first would win.
       if (int(defender.hp) - int(effectiveDamage1) <= 0) {// Case 2: player 2 lost
            console.log("Attacker won");
            // Attacker moves to Defender's old spot
            attacker.x = defender.x;
            attacker.y = defender.y;
            playingField[attacker.x][attacker.y] = attacker.addr;

            // Defender vacates current position
            playingField[defender.x][defender.y] = address(0);
            // And then moves to jail
            sendToJail(defender);

            // Player 1 takes defender's spoils
            spoils[attacker.addr] += spoils[defender.addr];
            spoils[defender.addr] = 0;
            
            // If Loser was in an Alliance
            if (defender.allianceId != 0) {
                // Also will need to leave the alliance cuz ded
                Alliance storage defenderAlliance = alliances[defender.allianceId];
                defenderAlliance.membersCount -= 1;
                defender.allianceId = 0;

                if (defenderAlliance.membersCount == 1) {
                    // if you're down to one member, ain't no alliance left
                    activeAlliances -= 1;
                    activePlayers -= 1;
                }

                console.log("Defender was in an alliance: ", activeAlliances);

                if (activeAlliances == 1) {
                    winnerAllianceId = defenderAlliance.id;
                    calcWinningAllianceSpoils();
                    emit WinnerAlliance(winnerAllianceId);
                }
            } else {
                activePlayers -= 1;
                activeAlliances -= 1;

                Alliance storage attackerAlliance = alliances[attacker.allianceId];
                console.log("Defender was NOT in an alliance: ", activeAlliances);
                if (activePlayers == 1) {
                    // win condition
                    winnerPlayer = attacker.addr;
                    emit WinnerPlayer(winnerPlayer);
                }

                if (activeAlliances == 1) {
                    winnerAllianceId = attackerAlliance.id;
                    calcWinningAllianceSpoils();
                    emit WinnerAlliance(winnerAllianceId);
                }
            }
        } else if (int(attacker.hp) - int(effectiveDamage2) <= 0) {
            console.log("Defender won");
            // Defender remains where he is, Attack goes to jail

            // Attacker vacates current position
            playingField[attacker.x][attacker.y] = address(0);
            // And moves to jail
            sendToJail(attacker);

            // Defender takes Attacker's spoils
            spoils[defender.addr] += spoils[attacker.addr];
            spoils[attacker.addr] = 0;

            if (attacker.allianceId != 0) {
                // Also will need to leave the alliance cuz ded
                Alliance storage attackerAlliance = alliances[attacker.allianceId];
                attackerAlliance.membersCount -= 1;
                attacker.allianceId = 0;

                if (attackerAlliance.membersCount == 1) {
                    // if you're down to one member, ain't no alliance left
                    activeAlliances -= 1;
                    activePlayers -= 1;
                }

                if (activeAlliances == 1) {
                    winnerAllianceId = attackerAlliance.id;
                    calcWinningAllianceSpoils();
                    emit WinnerAlliance(winnerAllianceId);
                }
            } else {
                activePlayers -= 1;

                if (activePlayers == 1) {
                    // win condition
                    winnerPlayer = defender.addr;
                    emit WinnerPlayer(winnerPlayer);
                }
            }
        } else {
            console.log("Neither lost");
            attacker.hp -= effectiveDamage2;
            defender.hp -= effectiveDamage1;
        }

        if (attacker.inJail == false) {
            playingField[attacker.x][attacker.y] = attacker.addr;
        }

        if (defender.inJail == false) {
            playingField[defender.x][defender.y] = defender.addr;
        }

        emit DamageDealt(attacker.addr, defender.addr, effectiveDamage1);
        emit DamageDealt(defender.addr, attacker.addr, effectiveDamage2);
    }

    function sendToJail(Player storage player) internal {
        player.hp = 0;
        player.x = jailCell.x;
        player.y = jailCell.y;
        player.inJail = true;
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

    modifier onlyWinningAllianceMember() {
        require(winnerAllianceId != 0, "Only call this if an alliance has won.");
        
        address[] memory winners = allianceMembers[winnerAllianceId];

        bool winnerFound = false;

        for(uint i = 0; i < winners.length; i++) {
            if (winners[i] == msg.sender) {
                winnerFound = true;
            }
        }
        
        if (winnerFound) {
            _;
        }  else {
            revert OnlyWinningAllianceMember();
        }
    }

    modifier onlyWinner() {
        console.log("msg.sender ", msg.sender);
        console.log("winner ", winnerPlayer);
        if(msg.sender != winnerPlayer) {
            revert LoserTriedWithdraw();
        }
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
