// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "chainlink/v0.8/AutomationCompatible.sol";
import "chainlink/v0.8/interfaces/LinkTokenInterface.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/VRFConsumerBaseV2.sol";

import "./interfaces/IDominationGame.sol";

contract DominationGame is IERC721Receiver, AutomationCompatible, VRFConsumerBaseV2, IDominationGame {
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    // TODO: get rid of this in favor of governance
    address public admin;
    JailCell public jailCell;
    mapping(address => Player) public players;
    mapping(uint256 => mapping(uint256 => address)) public playingField;
    mapping(uint256 => Alliance) public alliances;
    mapping(uint256 => address[]) public allianceMembers;
    EnumerableMap.UintToAddressMap internal allianceAdmins;
    EnumerableMap.UintToAddressMap private activePlayers;
    mapping(address => uint256) public spoils;

    // Keepers
    uint256 public interval;
    uint256 public lastUpkeepTimestamp;
    uint256 public gameStartTimestamp;
    bool public gameStarted;
    bool public gameEnded;

    // VRF
    VRFCoordinatorV2Interface immutable COORDINATOR;
    LinkTokenInterface immutable LINKTOKEN;
    address internal vrf_owner;
    // FIXME: change to 0
    uint256 internal randomness = 78541660797044910968829902406342334108369226379826116161446442989268089806461;
    uint256 public vrf_requestId;
    bytes32 immutable vrf_keyHash;
    uint16 immutable vrf_requestConfirmations = 3;
    uint32 immutable vrf_callbackGasLimit = 500_000;
    uint32 immutable vrf_numWords = 1;
    uint64 internal vrf_subscriptionId;

    // Game
    uint256 public currentTurn;
    uint256 public currentTurnStartTimestamp;
    uint256 public constant maxPlayers = 100;
    uint256 public activePlayersCount = 0;
    uint256 public activeAlliancesCount = 0;
    uint256 public winningTeamSpoils;
    uint256 public nextAvailableRow = 0; // TODO make random to prevent position sniping...?
    uint256 public nextAvailableCol = 0;
    uint256 public winnerAllianceId;
    uint256 public fieldSize;
    uint256 internal nextInmateId = 0;
    uint256 internal inmatesCount = 0;
    uint256 public nextAvailableAllianceId = 1; // start at 1 because 0 means you ain't joined one yet
    address public winnerPlayer;
    address[] public inmates = new address[](maxPlayers);
    
    GameStage public gameStage;

    modifier onlyGame() {
        require(msg.sender == address(this), "Only callable by game contract");
        _;
    }

    modifier onlyOwnerAndSelf() {
        require(msg.sender == vrf_owner || msg.sender == address(this));
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

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this");
        _;
    }

    modifier onlyWinner() {
        if (winnerPlayer == address(this)) {
            require(msg.sender == admin, "Only admin can withdraw if game was the ultimate winner.");
        } else {
            require(msg.sender == winnerPlayer, "Only winner can call this");
        }
        _;
    }

    modifier onlyViaSubmitReveal() {
        require(msg.sender == address(this), "Only via submit/reveal");
        _;
    }

    constructor(
        address vrfCoordinator,
        address linkToken,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint256 updateInterval) VRFConsumerBaseV2(vrfCoordinator) 
    payable {
        // FIXME with governance
        admin = msg.sender;
        fieldSize = maxPlayers; // also the max players

        // VRF
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(linkToken);
        vrf_keyHash = keyHash;
        vrf_owner = msg.sender;
        vrf_subscriptionId = subscriptionId;

        // Keeper
        interval = updateInterval;
        lastUpkeepTimestamp = block.timestamp;
        gameStartTimestamp = block.timestamp + updateInterval;

        emit Constructed(vrf_owner, vrf_subscriptionId, gameStartTimestamp);
    }

    function connect(uint256 tokenId, address byoNft) external payable {
        require(currentTurn == 0, "Already started");
        require(spoils[msg.sender] == 0, "Already joined");
        require(players[msg.sender].addr == address(0), "Already joined");
        require(activePlayersCount < maxPlayers, "Already at max players");
        // Your share of the spoils if you win as part of an alliance are proportional to how much you paid to connect.
        require(msg.value > 0, "Send some eth");

        // Verify Ownership
        uint256 nftBalance = IERC721(byoNft).balanceOf(msg.sender);
        require(nftBalance > 0, "You dont own this NFT you liar");

        // Approve for confiscation if misbehave during game
        IERC721(byoNft).setApprovalForAll(address(this), true);

        Player memory player = Player({
            addr: msg.sender,
            nftAddress: byoNft,
            balance: msg.value, // balance can be used to buy items/powerups in the marketplace
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
        activePlayers.set(activePlayersCount + 1, msg.sender);

        activePlayersCount += 1;
        nextAvailableCol = (nextAvailableCol + 2) % fieldSize;
        nextAvailableRow = nextAvailableCol == 0 ? nextAvailableRow + 1 : nextAvailableRow;

        emit Joined(msg.sender);
    }

    function start() public {
        require(currentTurn == 0, "Already started");
        require(activePlayersCount > 1, "Not enough players");
        require(randomness != 0, "Need randomness for jail cell");

        currentTurn = 1;
        currentTurnStartTimestamp = block.timestamp;
        gameStarted = true;
        gameStage = GameStage.Submit;
        emit NewGameStage(GameStage.Submit, currentTurn);

        jailCell = JailCell({ x: randomness / 1e75, y: randomness % 99 });

        emit TurnStarted(currentTurn, currentTurnStartTimestamp);
    }

    function submit(uint256 turn, bytes32 commitment) external {
        require(currentTurn > 0, "Not started");
        require(turn == currentTurn, "Stale tx");
        // submit stage is interval set by deployer
        require(gameStage == GameStage.Submit, "Only callable during the Submit Game Stage");

        players[msg.sender].pendingMoveCommitment = commitment;

        emit Submitted(msg.sender, currentTurn, commitment);
    }

    function reveal(
        uint256 turn,
        bytes32 nonce,
        bytes calldata data
    ) external {
        require(turn == currentTurn, "Stale tx");
        require(gameStage == GameStage.Reveal, "Only callable during the Reveal Game Stage");

        bytes32 commitment = players[msg.sender].pendingMoveCommitment;
        bytes32 proof = keccak256(abi.encodePacked(turn, nonce, data));

        require(commitment == proof, "No cheating");

        players[msg.sender].pendingMove = data;

        emit Revealed(msg.sender, currentTurn, nonce, data);
    }

    // (-1, 1) = (up, down)
    // (-2, 2) = (left, right)
    function move(address player, int8 direction) external onlyViaSubmitReveal {
        Player storage invader = players[player];
        uint256 newX = invader.x;
        uint256 newY = invader.y;

        for (int8 i = -2; i <= 2; i++) {
            if (i == 0) { continue; }
            if (direction == i) {
                if (direction > 0) { // down, right
                    newX = direction == 2 ? uint(int(invader.x) + direction - 1) % fieldSize : invader.x;
                    newY = direction == 1 ? uint(int(invader.y) + direction) % fieldSize : invader.y;
                    require(
                        direction == 2
                            ? newX <= fieldSize
                            : newY <= fieldSize
                        );
                } else { // up, left
                    newX = direction == -2 ? uint(int(invader.x) + direction + 1)  % fieldSize : invader.x;
                    newY = direction == -1 ? uint(int(invader.y) + direction) % fieldSize: invader.y;
                    require( 
                        direction == 1
                            ? newX >= 0
                            : newY >= 0
                    );
                }
                break;
            }
        }

        address currentOccupant = playingField[newX][newY];
        if (newX == jailCell.x && newY == jailCell.y) {
            emit AttemptJailBreak(msg.sender, jailCell.x, jailCell.y);
            _jailbreak(msg.sender);
        }

        if (_checkIfCanAttack(invader.addr, currentOccupant)) {
            _battle(player, currentOccupant);
        } else {
            playingField[invader.x][invader.y] = address(0);
            invader.x = newX;
            invader.y = newY;
        }

        playingField[invader.x][invader.y] = player;
        emit Move(invader.addr, invader.x, invader.y);        
    }

    function rest(address player) external onlyViaSubmitReveal {
        players[player].hp += 2;
        emit Rest(players[player].addr, players[player].x, players[player].y);
    }

    function createAlliance(address player, uint256 maxMembers, string calldata name) external onlyViaSubmitReveal {
        require(players[player].allianceId == 0, "Already in alliance");

        players[player].allianceId = nextAvailableAllianceId;
        allianceAdmins.set(nextAvailableAllianceId, player);

        Alliance memory newAlliance = Alliance({
            admin: player,
            id: nextAvailableAllianceId,
            activeMembersCount: 1,
            membersCount: 1,
            maxMembers: maxMembers,
            totalBalance: players[player].balance,
            name: name
        });
        if (allianceMembers[nextAvailableAllianceId].length > 0) {
            allianceMembers[nextAvailableAllianceId].push(player);
        } else {
            allianceMembers[nextAvailableAllianceId] = [player];
        }
        alliances[nextAvailableAllianceId] = newAlliance;
        nextAvailableAllianceId += 1;
        activeAlliancesCount += 1;

        emit AllianceCreated(player, nextAvailableAllianceId, name);
    }

    function joinAlliance(
        address player,
        uint256 allianceId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyViaSubmitReveal {

        // Admin must sign the application off-chain. Applications are per-move based, so the player
        // can't reuse the application from the previous move
        bytes memory application = abi.encodePacked(currentTurn, allianceId);

        bytes32 hash = keccak256(application);
        // address admin = ECDSA.recover(hash, signature
        address allianceAdmin = ecrecover(hash, v, r, s);

        require(allianceAdmins.get(allianceId) == allianceAdmin, "Not signed by admin");
        players[player].allianceId = allianceId;
        
        Alliance memory alliance = alliances[allianceId];
        
        require(alliance.membersCount < alliance.maxMembers - 1, "Cannot exceed max members count.");

        alliances[allianceId].activeMembersCount += 1;
        alliances[allianceId].membersCount += 1;
        alliances[allianceId].totalBalance += players[player].balance;
        if (allianceMembers[allianceId].length > 0) {
            allianceMembers[allianceId].push(player);
        } else {
            allianceMembers[allianceId] = [player];
        }

        emit AllianceMemberJoined(players[player].allianceId, player);
    }

    function leaveAlliance(address player) external onlyViaSubmitReveal {
        uint256 allianceId = players[player].allianceId;
        require(allianceId != 0, "Not in alliance");
        require(player != allianceAdmins.get(players[player].allianceId), "Admin canot leave alliance");

        players[player].allianceId = 0;
        
        for (uint256 i = 0; i < alliances[allianceId].membersCount; i++) {
            if (allianceMembers[allianceId][i] == player) {
                delete allianceMembers[i];
            }
        }

        alliances[allianceId].membersCount -= 1;
        alliances[allianceId].activeMembersCount -= 1;
        alliances[allianceId].totalBalance -= players[player].balance;

        if (alliances[allianceId].membersCount <= 1) {
            _destroyAlliance(allianceId);
        }

        emit AllianceMemberLeft(allianceId, player);
    }
    
    function withdrawWinnerAlliance() onlyWinningAllianceMember external {
        uint256 winningAllianceTotalBalance = alliances[winnerAllianceId].totalBalance;
        uint256 withdrawerBalance = players[msg.sender].balance;
        uint256 myCut = (withdrawerBalance * winningTeamSpoils) / winningAllianceTotalBalance;

        (bool sent, ) = msg.sender.call{ value: myCut }("");

        require(sent, "Failed to withdraw spoils");

        gameStage = GameStage.Finished;
        emit GameFinished(currentTurn, winningTeamSpoils);
    }

    function withdrawWinnerPlayer() onlyWinner external {
        if (winnerPlayer == address(this) || winnerPlayer == address(admin)) {
            (bool sent, ) = winnerPlayer.call{ value: address(this).balance }("");
            require(sent, "Failed to withdraw winnings");
        }

        (bool sent, ) = winnerPlayer.call{ value: spoils[winnerPlayer] }("");
        require(sent, "Failed to withdraw winnings");
        spoils[winnerPlayer] = 0;
        emit WinnerWithdrawSpoils(winnerPlayer, spoils[winnerPlayer]);
        gameStage = GameStage.Finished;
        emit GameFinished(currentTurn, winningTeamSpoils);
    }

    /**** Internal Functions *****/
    function _handleBattleLoser(address _loser, address _winner) internal {
        Player storage loser = players[_loser];
        Player storage winner = players[_winner];

        // Winner moves into Loser's old spot
        winner.x = loser.x;
        winner.y = loser.y;
        playingField[winner.x][winner.y] = winner.addr;

        // Loser vacates current position and then moves to jail 
        playingField[loser.x][loser.y] = address(0);
        _sendToJail(loser.addr);

        // Winner takes Loser's spoils
        spoils[winner.addr] += spoils[loser.addr];
        spoils[loser.addr] = 0;
        
        // Case: Winner was in an Alliance
        if (winner.allianceId != 0) {
            Alliance storage attackerAlliance = alliances[winner.allianceId];
            attackerAlliance.totalBalance += spoils[loser.addr];
        }

        // Case: Loser was not in an Alliance
        if (loser.allianceId == 0) {
            _checkWinCondition();
        } else { 
            // Case: Loser was in an Alliance
            
             // Also will need to leave the alliance cuz ded
            Alliance storage loserAlliance = alliances[loser.allianceId];
            loserAlliance.totalBalance -= spoils[loser.addr];
            loserAlliance.membersCount -= 1;
            loserAlliance.activeMembersCount -= 1;
            loser.allianceId = 0;

            if (loserAlliance.membersCount <= 1) {
                // if you're down to one member, ain't no alliance left
                _destroyAlliance(loser.allianceId);
            }

            _checkWinCondition();
        }
    }

    function _destroyAlliance(uint256 allianceId) internal {
    // if you're down to one member, ain't no alliance left
        activeAlliancesCount -= 1;
        delete alliances[allianceId];
        allianceAdmins.set(allianceId, address(0));
    }

    // If one player remains, they get the spoils
    // If no one remains, the contract gets the spoils
    function _declareWinner(address who) internal {
        winnerPlayer = who;
        emit WinnerPlayer(who);
        gameStarted = false;
        gameStage = GameStage.PendingWithdrawals;
        emit NewGameStage(GameStage.PendingWithdrawals, currentTurn);
    }
    
    // If an alliance won
    function _declareWinner(uint256 _winnerAllianceId) internal {
        winnerAllianceId = _winnerAllianceId;
        emit WinnerAlliance(_winnerAllianceId);
        _calcWinningAllianceSpoils();
        gameStarted = false;
        gameStage = GameStage.PendingWithdrawals;
        emit NewGameStage(GameStage.PendingWithdrawals, currentTurn);
    }

    function _checkWinCondition() internal {
        emit CheckingWinCondition(activeAlliancesCount, activePlayersCount);

        if (activeAlliancesCount == 1) {
            for (uint256 i = 1; i <= nextAvailableAllianceId; i++) {
                if (alliances[i].activeMembersCount == activePlayersCount) {
                    _declareWinner(alliances[i].id);
                    break;
                }
            }
        } else {
            address who;
            if (activePlayersCount == 1) {
                for (uint256 i = 1; i < activePlayersCount; i++) {
                    if (activePlayers.get(i) != address(0)) {
                        who = activePlayers.get(i);
                        break;
                    }
                }
            } else if (activePlayersCount == 0) {
                who = address(this);
            }
            if (who != address(0)) {
                _declareWinner(who);
            }
        }
    }

    function _calcWinningAllianceSpoils() internal {
        require(winnerAllianceId != 0);
        
        address[] memory winners = allianceMembers[winnerAllianceId];

        uint256 totalSpoils = 0;

        for (uint256 i = 0; i < winners.length; i++) {
            totalSpoils += spoils[winners[i]];
        }

        winningTeamSpoils = totalSpoils;
    }

    function _jailbreak(address breakerOuter) internal {
        // if it's greater than threshold everybody get out, including non alliance members
        if (randomness % 99 > 50) {
            for (uint256 i = 0; i < inmates.length; i++) {
                address inmate = inmates[i];
                if (inmate != address(0)) {
                    _freeFromJail(inmate, i);
                }
            }
            inmates = new address[](maxPlayers); // everyone broke free so just reset
        } else {
            // if lower then roller gets jailed as well lol
            _sendToJail(breakerOuter);
        }
    }

    // N.b right now the scope is to just free if somebody lands on the cell and rolls a good number.
    // could be fun to make an option for a player to bribe (pay some amount to free just alliance members)
    function _freeFromJail(address playerAddress, uint256 inmateIndex) internal {
        Player storage player = players[playerAddress];

        player.hp = 50;
        player.x = jailCell.x;
        player.y = jailCell.y;
        player.inJail = false;
        activePlayersCount += 1;

        delete inmates[inmateIndex];
        inmatesCount -= 1;

        if (player.allianceId != 0) {
            Alliance storage alliance = alliances[player.allianceId];
            alliance.activeMembersCount += 1;
        }

        emit JailBreak(player.addr, inmatesCount);
    }

    // N.B. only external/public functions have a .selector so change visibiltiy or call it another way.
    function _sendToJail(address playerAddress) public onlyGame {
        Player storage player = players[playerAddress];

        player.hp = 0;
        player.x = jailCell.x;
        player.y = jailCell.y;
        player.inJail = true;
        activePlayersCount -= 1;
        inmates[nextInmateId] = player.addr;
        nextInmateId += 1;
        inmatesCount += 1;

        if (player.allianceId != 0) {
            Alliance storage alliance = alliances[player.allianceId];
            alliance.activeMembersCount -= 1;
        }

        emit Jail(player.addr, inmatesCount);
    }

    function _checkIfCanAttack(address meAddr, address otherGuyAddr) internal view returns (bool) {
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

        Player memory attacker = players[attackerAddr];
        Player memory defender = players[defenderAddr];

        require(attacker.allianceId == 0 || defender.allianceId == 0 || attacker.allianceId != defender.allianceId, "Allies do not fight");

        emit BattleCommenced(attackerAddr, defenderAddr);

        // take randomness, multiply it against attack to get what % of total attack damange is done to opponent's hp, make it at least 1
        uint256 effectiveDamage1 = (attacker.attack / (randomness % 99)) + 1;
        uint256 effectiveDamage2 = (defender.attack / (randomness % 99)) + 1;

        // Attacker goes first. There is an importance of who goes first, because if both have an effective damage enough to kill the other, the one who strikes first would win.
       if (int(defender.hp) - int(effectiveDamage1) <= 0) {
            _handleBattleLoser(defender.addr, attacker.addr);
        } else if (int(attacker.hp) - int(effectiveDamage2) <= 0) {
            _handleBattleLoser(attacker.addr, defender.addr);
        } else {
            attacker.hp -= effectiveDamage2;
            defender.hp -= effectiveDamage1;
            emit BattleStalemate(attacker.hp, defender.hp);
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

    function requestRandomWords() public {
        
        // Will revert if subscription is not set and funded.
        vrf_requestId = COORDINATOR.requestRandomWords(
        vrf_keyHash,
        vrf_subscriptionId,
        vrf_requestConfirmations,
        vrf_callbackGasLimit,
        vrf_numWords
        );
        emit RolledDice(vrf_requestId, currentTurn + 1);
    }

    function setSubscriptionId(uint64 subId) public onlyOwnerAndSelf {
        vrf_subscriptionId = subId;
    }

    function setOwner(address owner) public onlyOwnerAndSelf {
        vrf_owner = owner;
    }

    function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory performData) {
        performData = bytes("");
        bool upkeepNeeded = (block.timestamp - lastUpkeepTimestamp) >= interval && gameStage != GameStage.Finished && gameStage != GameStage.PendingWithdrawals;

        if (upkeepNeeded) {
            address[] memory playersWithPendingMoves = new address[](activePlayersCount);
            bytes[] memory pendingMoveCalls = new bytes[](activePlayersCount);
            bytes[] memory confiscationCalls = new bytes[](activePlayersCount);
            bytes[] memory sendToJailCalls = new bytes[](activePlayersCount);

            for (uint256 i = 1; i <= activePlayersCount; i++) {
                Player memory player = players[activePlayers.get(i)];

                if (!player.inJail) {
                    playersWithPendingMoves[i - 1] = player.addr;
                }
                // If player straight up didn't submit then confiscate their NFT and send to jail
                if (player.pendingMoveCommitment == bytes32(0)) {
                    // emit NoSubmit(player.addr, currentTurn);
                    
                    confiscationCalls[i - 1] = abi.encodeWithSelector(
                        bytes4(
                            keccak256(
                                bytes("safeTransferFrom(address,address,uint256,bytes)"))), player.addr, address(this), player.tokenId, "");

                    sendToJailCalls[i - 1] = abi.encodeWithSelector(
                        bytes4(
                            keccak256(
                                bytes("_sendToJail(address)"))), player.addr);

                    continue;
                } else if (player.pendingMoveCommitment != bytes32(0) && player.pendingMove.length == 0) { // If player submitted but forgot to reveal, move them to jail
                    sendToJailCalls[i - 1] = abi.encodeWithSelector(
                                bytes4(
                                    keccak256(
                                        bytes("_sendToJail(address)"))), player.addr);

                    // if you are in jail but your alliance wins, you still get a cut of the spoils
                    continue;
                }

                pendingMoveCalls[i - 1] = player.pendingMove;
            }

            performData = abi.encode(playersWithPendingMoves, pendingMoveCalls, confiscationCalls, sendToJailCalls);
        }

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        if (gameStarted) {
            _checkWinCondition();
            if (gameStage == GameStage.Submit) {
                gameStage = GameStage.Reveal;
                emit NewGameStage(GameStage.Reveal, currentTurn);
            } else if (gameStage == GameStage.Reveal) {
                gameStage = GameStage.Resolve;
                emit NewGameStage(GameStage.Resolve, currentTurn);

                require(randomness != 0, "Roll the die first");

                (address[] memory playersWithPendingMoves, bytes[] memory pendingMoveCalls, bytes[] memory confiscationCalls,bytes[] memory sendToJailCalls) = abi.decode(performData, (address[], bytes[],  bytes[], bytes[]));

                for (uint256 i = 1; i <= playersWithPendingMoves.length; i++) {
                    Player memory player = players[activePlayers.get(i)];

                    if (keccak256(pendingMoveCalls[i - 1]) != keccak256(bytes(""))) {
                        (bool success, bytes memory err) = address(this).call(pendingMoveCalls[i - 1]);

                        if (!success) {
                            // Player submitted a bad move
                            if (int(player.balance - 0.05 ether) >= 0) {
                                player.balance -= 0.05 ether;
                                spoils[player.addr] = player.balance;
                                emit BadMovePenalty(currentTurn, player.addr, err);
                            } else {
                                player.balance = 0;
                                spoils[player.addr] = player.balance;
                                _sendToJail(player.addr);
                                _checkWinCondition();
                            }
                        }
                    }
                    
                    if (keccak256(confiscationCalls[i - 1]) != keccak256(bytes(""))) {
                        (bool success, ) = address(player.nftAddress).call(confiscationCalls[i - 1]);

                        if (success) {
                            emit NoSubmit(player.addr, currentTurn);
                            emit NftConfiscated(player.addr, player.nftAddress, player.tokenId);
                        }    
                    }

                    if (keccak256(sendToJailCalls[i - 1]) != keccak256(bytes(""))) {
                        (bool success, ) = address(this).call(sendToJailCalls[i - 1]);

                        if (success) {
                            emit NoReveal(player.addr, currentTurn);
                        }
                    }
                    
                    if (playersWithPendingMoves[i - 1] != address(0)) {
                        players[playersWithPendingMoves[i - 1]].pendingMove = "";
                        players[playersWithPendingMoves[i - 1]].pendingMoveCommitment = bytes32(0);
                    }   
                }
                
                currentTurn += 1;
                currentTurnStartTimestamp = block.timestamp;
                emit TurnStarted(currentTurn, currentTurnStartTimestamp);
            } else if (gameStage == GameStage.Resolve) {
                gameStage = GameStage.Submit;
                emit NewGameStage(GameStage.Submit, currentTurn);
            }
        } else {
            // check if max players or game start time reached
            if (activePlayersCount == maxPlayers || gameStartTimestamp <= block.timestamp) {
                if (activePlayersCount >= 2) {
                    start();
                } else {
                    requestRandomWords();
                    // not enough people joined then keep pushing it back till the day comes ㅠㅠ
                    gameStartTimestamp = block.timestamp + interval;
                    emit GameStartDelayed(gameStartTimestamp);
                }
            }
        }
        lastUpkeepTimestamp = block.timestamp;
    }

    // Fallback function must be declared as external.
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
