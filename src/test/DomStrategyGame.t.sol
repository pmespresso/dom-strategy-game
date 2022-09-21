// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./mocks/MockVRFCoordinatorV2.sol";
import "../../script/HelperConfig.sol";
import "../DomStrategyGame.sol";
import "../Loot.sol";

contract MockBAYC is ERC721 {
    using Strings for uint256;

    string baseURI;
    
    error NonExistentTokenUri();
    constructor() ERC721("Bored Ape Yacht Club", "BAYC") {

    }
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) {
            revert NonExistentTokenUri();
        }

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }
}

contract DomStrategyGameTest is Test {
    using stdStorage for StdStorage;

    DomStrategyGame public game;
    Loot public loot;
    MockBAYC public bayc;

    string mnemonic1 = "test test test test test test test test test test test junk";
    string mnemonic2 = "blind lesson awful swamp borrow rapid snake unique oak blue depart exercise";
    address w1nt3r;
    address dhof;
    uint256 w1nt3r_pk;
    uint256 dhof_pk;

    // N.B. this should be done offchain IRL
    address[] sortedAddrs = new address[](2);

    HelperConfig helper = new HelperConfig();
    MockVRFCoordinatorV2 vrfCoordinator;

    function setUp() public {
        (
            ,
            ,
            ,
            address link,
            ,
            ,
            ,
            ,
            bytes32 keyHash
        ) = helper.activeNetworkConfig();

        w1nt3r_pk = vm.deriveKey(mnemonic1, 0);
        w1nt3r = vm.addr(w1nt3r_pk);

        dhof_pk = vm.deriveKey(mnemonic2, 0);
        dhof = vm.addr(dhof_pk);

        vrfCoordinator = new MockVRFCoordinatorV2();
        uint64 subscriptionId = vrfCoordinator.createSubscription();
        uint96 FUND_AMOUNT = 1000 ether;
        vrfCoordinator.fundSubscription(subscriptionId, FUND_AMOUNT);

        bayc = new MockBAYC();
        loot = new Loot();
        game = new DomStrategyGame(loot, address(vrfCoordinator), link, subscriptionId, keyHash);

        vrfCoordinator.addConsumer(subscriptionId, address(game));

        game.init();
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );

        vm.deal(w1nt3r, 1 ether);
        vm.deal(dhof, 100 ether);

        sortedAddrs[0] = dhof;
        sortedAddrs[1] = w1nt3r;
    }

    function connect() public {
        vm.startPrank(w1nt3r);

        loot.mint(w1nt3r, 1);
        loot.setApprovalForAll(address(game), true);
        game.connect{value: 1 ether}(1, address(loot));
        vm.stopPrank();

        vm.startPrank(dhof);
        
        bayc.mint(dhof, 1);
        bayc.setApprovalForAll(address(game), true);
        game.connect{value: 6.9 ether}(1, address(bayc));
        vm.stopPrank();
    }

    function revealAndResolve(uint256 turn, bytes32 nonce1,bytes32 nonce2,bytes memory call1, bytes memory call2) public {
        vm.prank(w1nt3r);
        game.reveal(turn, nonce1, call1);

        vm.prank(dhof);
        game.reveal(turn, nonce2, call2);

        game.rollDice(turn);
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );
        
        game.resolve(turn, sortedAddrs);
    }

    function testConnect() public {
        connect();
        (,,,,,,,,uint256 x_w1nt3r,uint256 y_w1nt3r,,,) = game.players(w1nt3r);
        (,,,,,,,,uint256 x_dhof,uint256 y_dhof,,,) = game.players(dhof);

        require(game.spoils(w1nt3r) > 0, "Cannot play with 0 spoils, pleb.");
        require(game.spoils(dhof) > 0, "Cannot play with 0 spoils, pleb.");
        require(address(game).balance == 7.9 ether, "Game contract should escrow all the spoils.");
        require(x_w1nt3r == 0 && y_w1nt3r == 0, "First connector should occupy (0, 0)");
        require(x_dhof == 2 && y_dhof == 0, "Second connector should occupy (2, 0)");
    }

    function testGame() public {
        connect();
        
        game.start();

        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";
        uint256 turn = 1;

        // To make a move, you submit a hash of the intended move with the current turn, a nonce, and a call to either move or rest. Everyone's move is collected and then revealed at once after 18 hours
        vm.prank(w1nt3r);
        bytes memory call1 = abi.encodeWithSelector(
            DomStrategyGame.rest.selector,
            w1nt3r
        );
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, call1)));
        
        vm.prank(dhof);
        bytes memory call2 = abi.encodeWithSelector(
            DomStrategyGame.move.selector,
            dhof,
            int8(4)
        );
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, call2)));

        // every 18 hours all players need to reveal their respective move for that turn.
        vm.warp(block.timestamp + 19 hours);

        revealAndResolve(turn, nonce1, nonce2, call1, call2);

        (,,,,,,uint256 hp_w1nt3r,,uint256 x_w1nt3r,uint256 y_w1nt3r,bytes32 pendingMoveCommitment_w1nt3r,,) = game.players(w1nt3r);
        (,,,,,,uint256 hp_dhof,,uint256 x_dhof,uint256 y_dhof,bytes32 pendingMoveCommitment_dhof,,) = game.players(dhof);

        require(x_w1nt3r == 0 && y_w1nt3r == 0, "W1nt3r should have remained in place from rest()");
        require(x_dhof == 3 && y_dhof == 0, "Dhof should have moved right one square from move(4)");
        require(game.playingField(3, 0) == dhof, "Playing field should record dhof new position");
        require(game.playingField(0, 0) == w1nt3r, "Playing field should record w1nt3r new position");
        require(hp_dhof == 1000, "W1nt3r should have recovered 2 hp from rest()");
        require(hp_w1nt3r == 1002, "Dhof should have same hp remaining as before from move()");
        require(pendingMoveCommitment_dhof == "" && pendingMoveCommitment_w1nt3r == "", "Pending move commitment for both should be cleared after resolution.");
    }

    function testAlliance() public {
        connect();

        uint256 turn = game.currentTurn() + 1;
        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";

        game.start();
        // dhof
        vm.prank(dhof);

        bytes memory createAllianceCall = abi.encodeWithSelector(DomStrategyGame.createAlliance.selector, dhof, 5, "The Dominators");

        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, createAllianceCall)));

        // w1nt3r
        vm.prank(w1nt3r);
        bytes memory restCall = abi.encodeWithSelector(DomStrategyGame.rest.selector, w1nt3r);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, restCall)));

        vm.warp(block.timestamp + 19 hours);
        
        revealAndResolve(turn, nonce2, nonce1, restCall, createAllianceCall);

        (address admin, uint256 allianceId, uint256 membersCount, uint256 maxMembersCount,) = game.alliances(0);
        (,,,,,uint256 allianceId_dhof,,,,,,,) = game.players(dhof);

        require(game.allianceAdmins(allianceId) == dhof && admin == dhof, "Dhof should be the alliance admin.");
        require(allianceId == 0, "First alliance id should be 0");
        require(membersCount == 1, "Admin should be the only initial member of alliance");
        require(maxMembersCount == 5, "Max members count should be as specified by creator");
        require(allianceId == allianceId_dhof, "Alliance Id should match in Player and Alliance structs (Foreign Key)");

        turn = turn + 1;
        bytes32 nonce3 = hex"03";
        bytes32 nonce4 = hex"04";

        vm.prank(dhof);
        bytes memory dhofMoveCall = abi.encodeWithSelector(DomStrategyGame.move.selector, dhof, int8(2));
        // Dhof, the admin, must sign the application offchain
        bytes memory application = abi.encodePacked(turn, allianceId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(dhof_pk, keccak256(application));
        
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, dhofMoveCall)));

        vm.prank(w1nt3r);
        bytes memory w1nt3rApplyToAllianceCall = abi.encodeWithSelector(DomStrategyGame.joinAlliance.selector, w1nt3r, 0, v, r, s);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, w1nt3rApplyToAllianceCall)));

        vm.warp(block.timestamp + 19 hours);

        revealAndResolve(turn, nonce4, nonce3, w1nt3rApplyToAllianceCall, dhofMoveCall);

        (, , uint256 membersCount_post_join,, ) = game.alliances(0);
        (,,,,,uint256 allianceId_w1nt3r,,,,,,,) = game.players(w1nt3r);

        require(membersCount_post_join == 2, "Alliance should have 2 members after w1nt3r joins.");
        require(allianceId_w1nt3r == 0, "w1nt3r should be member of alliance 0");
    }

    function testBattle() public {
        connect();

        uint256 turn = game.currentTurn() + 1;
        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";

        game.start();

        /********* Turn 1 *********/

        // w1nt3r
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(w1nt3r)
            .depth(8)
            .checked_write(4);

        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(w1nt3r)
            .depth(9)
            .checked_write(5);

        game.setPlayingField(4, 5, w1nt3r);
        
        vm.prank(w1nt3r);
        bytes memory w1nt3rMoveUp = abi.encodeWithSelector(DomStrategyGame.move.selector, w1nt3r, int8(1));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, w1nt3rMoveUp)));
        vm.stopPrank();

        // dhof
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(dhof)
            .depth(8) // player.x
            .checked_write(4);

        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(dhof)
            .depth(9) // player.y
            .checked_write(4);
        
        game.setPlayingField(4, 4, dhof);

        vm.prank(dhof);
        bytes memory dhofRest = abi.encodeWithSelector(DomStrategyGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, dhofRest)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);

        revealAndResolve(turn, nonce1, nonce2, w1nt3rMoveUp, dhofRest);

        // Usual
        // On first contact nobody will die, just damage dealt.
        // check hp
        (,,,,,,uint dhof_hp,uint dhof_attack,,,,,) = game.players(dhof);
        (,,,,,,uint w1nt3r_hp,uint w1nt3r_attack,,,,,) = game.players(w1nt3r);

        console.log("d hp", dhof_hp);
        console.log("w hp", w1nt3r_hp);
        console.log("d att", dhof_attack);
        console.log("w hp", w1nt3r_attack);

        // dhof gets +2 for rest
        require(dhof_hp < 1002 && dhof_hp >= dhof_hp - w1nt3r_attack, "Some damage should have been dealt between 1 - player.attack.");
        require(w1nt3r_hp < 1000 && w1nt3r_hp >= w1nt3r_hp - dhof_attack, "Some damage should have been dealt between 1 - player.attack.");

        /********* Turn 2 *********/
        // Assume w1nt3r loses and dhof wins
        bytes32 nonce3 = hex"03";
        bytes32 nonce4 = hex"04";
        turn += 1;

        console.log("==== HERE ===== ");

        // give dhof insane attack
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(dhof)
            .depth(7) // player.attack
            .checked_write(9000);

        // give w1nt3r shit hp
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(w1nt3r)
            .depth(6) // player.hp
            .checked_write(1);

        // w1nt3r didn't manage to kill dhof last round, he moves again to where he thinks dhof again to finish the job.
        vm.prank(w1nt3r);
        bytes memory w1nt3rMoveUpAgain = abi.encodeWithSelector(DomStrategyGame.move.selector, w1nt3r, int8(1));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, w1nt3rMoveUpAgain)));
        vm.stopPrank();

        vm.prank(dhof);
        bytes memory dhofRestAgain = abi.encodeWithSelector(DomStrategyGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, dhofRest)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);

        revealAndResolve(turn, nonce3, nonce4, w1nt3rMoveUpAgain, dhofRestAgain);
        
        // w1nt3r made a mistake in poking the sleeping lion, he die, give all spoils to dhof
        uint256 loser_spoils = game.spoils(w1nt3r);
        uint256 winner_spoils = game.spoils(dhof);
        require(loser_spoils == 0, "Loser gets all their spoils taken.");
        require(winner_spoils == 7.9 ether, "Winner gets all the spoils of the defeated.");

        // (,,,,,,,,uint256 x_w1nt3r_after,uint256 y_w1nt3r_after,,) = game.players(w1nt3r);
        // require(x_w1nt3r_after )
        // check player count reduced
        // check only winner occupies the disputed cell after battle
    }
}
