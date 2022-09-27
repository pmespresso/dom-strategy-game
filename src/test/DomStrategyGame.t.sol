// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import "./mocks/MockVRFCoordinatorV2.sol";
import "../../script/HelperConfig.sol";
import "../DomStrategyGame.sol";
import "../Loot.sol";

contract DomStrategyGameTest is Test {
    using stdStorage for StdStorage;

    DomStrategyGame public game;
    Loot public loot;

    string mnemonic1 = "test test test test test test test test test test test junk";
    string mnemonic2 = "blind lesson awful swamp borrow rapid snake unique oak blue depart exercise";
    string mnemonic3 = "ancient spawn mobile flag joy cable measure water crucial blame luggage amateur";
    string mnemonic4 = "lady teach unveil first caution shine kitten kidney jacket spell carry couple";
    
    address w1nt3r;
    address dhof;
    address piskomate;
    address arthur;

    uint256 w1nt3r_pk;
    uint256 dhof_pk;
    uint256 piskomate_pk;
    uint256 arthur_pk;

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

        piskomate_pk = vm.deriveKey(mnemonic3, 0);
        piskomate = vm.addr(piskomate_pk);

        arthur_pk = vm.deriveKey(mnemonic4, 0);
        arthur = vm.addr(arthur_pk);

        vrfCoordinator = new MockVRFCoordinatorV2();
        uint64 subscriptionId = vrfCoordinator.createSubscription();
        uint96 FUND_AMOUNT = 1000 ether;
        vrfCoordinator.fundSubscription(subscriptionId, FUND_AMOUNT);

        loot = new Loot();
        game = new DomStrategyGame(address(vrfCoordinator), link, subscriptionId, keyHash);

        vrfCoordinator.addConsumer(subscriptionId, address(game));

        game.init();
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );

        vm.deal(w1nt3r, 1 ether);
        vm.deal(dhof, 6.9 ether);
        vm.deal(piskomate, 1 ether);
        vm.deal(arthur, 1 ether);
        
        console.log("piskomate: ", piskomate);
        console.log("dhof: ", dhof);
        console.log("arthur: ", arthur);
        console.log("w1nt3r: ", w1nt3r);
    }

    function connect2() public {
        vm.startPrank(piskomate);
        loot.mint(piskomate, 1);
        loot.setApprovalForAll(address(game), true);
        game.connect{value: 1 ether}(1, address(loot));
        vm.stopPrank();

        vm.startPrank(dhof);
        loot.mint(dhof, 2);
        loot.setApprovalForAll(address(game), true);
        game.connect{value: 6.9 ether}(2, address(loot));
        vm.stopPrank();
    }

    function connect4() public {
        connect2();
        
        vm.startPrank(arthur);
        loot.mint(arthur, 3);
        loot.setApprovalForAll(address(game), true);
        game.connect{value: 1 ether}(3, address(loot));
        vm.stopPrank();
        vm.startPrank(w1nt3r);

        loot.mint(w1nt3r, 4);
        loot.setApprovalForAll(address(game), true);
        game.connect{value: 1 ether}(4, address(loot));
        vm.stopPrank();
    }

    function revealAndResolve2P(uint256 turn, bytes32 nonce1,bytes32 nonce2,bytes memory call1, bytes memory call2) public {
        vm.prank(piskomate);
        game.reveal(turn, nonce1, call1);

        vm.prank(dhof);
        game.reveal(turn, nonce2, call2);
        
        // N.B. roll dice, resolve should be done by Chainlink Keeprs
        game.rollDice(turn);
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );
        
        game.resolve(turn);
        vm.stopPrank();
    }

    function revealAndResolve4P(uint256 turn, bytes32 nonce1,bytes32 nonce2,bytes32 nonce3,bytes32 nonce4, bytes memory call1, bytes memory call2, bytes memory call3, bytes memory call4) public {
        revealAndResolve2P(turn, nonce1, nonce2, call1, call2);

        vm.prank(arthur);
        game.reveal(turn, nonce3, call3);

        vm.prank(w1nt3r);
        game.reveal(turn, nonce4, call4);

        // N.B. roll dice, resolve should be done by Chainlink Keeprs
        game.rollDice(turn);
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );
        
        game.resolve(turn);
        vm.stopPrank();
    }


    function testConnect() public {
        connect2();
        (,address pisko_nft,uint256 pisko_tokenId,,,,,,uint256 x_piskomate,uint256 y_piskomate,,,) = game.players(piskomate);
        (,address dhof_nft,uint256 dhof_tokenId,,,,,,uint256 x_dhof,uint256 y_dhof,,,) = game.players(dhof);

        require(game.spoils(piskomate) > 0, "Cannot play with 0 spoils, pleb.");
        require(game.spoils(dhof) > 0, "Cannot play with 0 spoils, pleb.");
        require(address(game).balance == 7.9 ether, "Game contract should escrow all the spoils.");
        require(x_piskomate == 0 && y_piskomate == 0, "First connector should occupy (0, 0)");
        require(x_dhof == 2 && y_dhof == 0, "Second connector should occupy (2, 0)");
        require(IERC721(pisko_nft).balanceOf(piskomate) == 1, "Pisko should have 1 Loot");
        require(IERC721(dhof_nft).balanceOf(dhof) == 1, "Dhof should have 1 Loot");
    }

    function testGame() public {
        connect2();
        
        game.start();

        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";
        uint256 turn = 1;

        // To make a move, you submit a hash of the intended move with the current turn, a nonce, and a call to either move or rest. Everyone's move is collected and then revealed at once after 18 hours
        vm.prank(piskomate);
        bytes memory call1 = abi.encodeWithSelector(
            DomStrategyGame.rest.selector,
            piskomate
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

        revealAndResolve2P(turn, nonce1, nonce2, call1, call2);

        (,,,,,,uint256 hp_piskomate,,uint256 x_piskomate,uint256 y_piskomate,bytes32 pendingMoveCommitment_piskomate,,) = game.players(piskomate);
        (,,,,,,uint256 hp_dhof,,uint256 x_dhof,uint256 y_dhof,bytes32 pendingMoveCommitment_dhof,,) = game.players(dhof);

        require(x_piskomate == 0 && y_piskomate == 0, "piskomate should have remained in place from rest()");
        require(x_dhof == 3 && y_dhof == 0, "Dhof should have moved right one square from move(4)");
        require(game.playingField(3, 0) == dhof, "Playing field should record dhof new position");
        require(game.playingField(0, 0) == piskomate, "Playing field should record piskomate new position");
        require(hp_dhof == 1000, "piskomate should have recovered 2 hp from rest()");
        require(hp_piskomate == 1002, "Dhof should have same hp remaining as before from move()");
        require(pendingMoveCommitment_dhof == "" && pendingMoveCommitment_piskomate == "", "Pending move commitment for both should be cleared after resolution.");
    }

    function testNoRevealOrNoSubmitPenalty() public {
        connect2();

        game.start();

        // bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";
        uint256 turn = 1;

        // Piskomate straight up doesn't submit
        // ...

        // Let's say dhof submits then doesn't reveal        
        vm.prank(dhof);
        bytes memory call2 = abi.encodeWithSelector(
            DomStrategyGame.move.selector,
            dhof,
            int8(4)
        );
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, call2)));

        vm.warp(block.timestamp + 19 hours);

        // Dhof doesn't reveal....

        game.rollDice(turn);
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );
        
        game.resolve(turn);
        address inmate0 = game.inmates(0);
        address inmate1 = game.inmates(1);
        (uint256  jailX, uint256 jailY) = game.jailCell();
        
        (,address pisko_nft,uint256 pisko_tokenId,,,,,, uint256 pisko_x, uint256 pisko_y,,,bool pisko_inJail) = game.players(piskomate);

        // Piskomate didn't submit at all so check confiscation
        require(inmate0 == piskomate, "Piskomate should be sent to jail since he didn't submit or reveal");
        require(jailX == pisko_x && jailY == pisko_y && pisko_inJail == true, "Pisko position should be jail cell.");
        require(IERC721(pisko_nft).balanceOf(piskomate) == 0, "Piskomate should no longer have his Loot");
        require(IERC721(pisko_nft).ownerOf(pisko_tokenId) == address(game), "The Game should now have Piskomate's Loot");

        (,address dhof_nft, uint256 dhof_tokenId,,,,uint256 dhof_hp,, uint256 x, uint256 y,,,bool inJail) = game.players(dhof);
        
        // Dhof submitted but didn't reveal so just check he's in jail
        require(jailX == x && jailY == y && inJail == true, "Dhof position should be jail cell.");
        require(dhof_hp == 0, "Dhof hp should be 0 in jail.");
        require(inmate1 == dhof, "Dhof should be sent to jail since he didn't reveal");
        require(IERC721(dhof_nft).balanceOf(dhof) == 1 && IERC721(dhof_nft).ownerOf(dhof_tokenId) == dhof, "Dhof should still have his NFT.");
    }

    function testBattle() public {
        connect2();

        uint256 turn = game.currentTurn() + 1;
        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";

        game.start();

        /********* Turn 1 *********/

        // piskomate
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(piskomate)
            .depth(8)
            .checked_write(4);

        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(piskomate)
            .depth(9)
            .checked_write(5);

        game.setPlayingField(4, 5, piskomate);
        
        vm.startPrank(piskomate);
        bytes memory piskomateMoveUp = abi.encodeWithSelector(DomStrategyGame.move.selector, piskomate, int8(1));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, piskomateMoveUp)));
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

        vm.startPrank(dhof);
        bytes memory dhofRest = abi.encodeWithSelector(DomStrategyGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, dhofRest)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);

        revealAndResolve2P(turn, nonce1, nonce2, piskomateMoveUp, dhofRest);

        // Usual
        // On first contact nobody will die, just damage dealt.
        // check hp
        (,,,,,,uint dhof_hp,uint dhof_attack,,,,,) = game.players(dhof);
        (,,,,,,uint piskomate_hp,uint piskomate_attack,,,,,) = game.players(piskomate);

        // dhof gets +2 for rest
        require(dhof_hp < 1002 && dhof_hp >= dhof_hp - piskomate_attack, "Some damage should have been dealt between 1 - player.attack.");
        require(piskomate_hp < 1000 && piskomate_hp >= piskomate_hp - dhof_attack, "Some damage should have been dealt between 1 - player.attack.");

        /********* Turn 2 *********/
        // Assume piskomate loses and dhof wins
        bytes32 nonce3 = hex"03";
        bytes32 nonce4 = hex"04";
        turn += 1;

        // give dhof insane attack
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(dhof)
            .depth(7) // player.attack
            .checked_write(9000);

        // give piskomate shit hp
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(piskomate)
            .depth(6) // player.hp
            .checked_write(1);

        // piskomate didn't manage to kill dhof last round, he moves again to where he thinks dhof again to finish the job.
        vm.startPrank(piskomate);
        bytes memory piskomateMoveUpAgain = abi.encodeWithSelector(DomStrategyGame.move.selector, piskomate, int8(1));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, piskomateMoveUpAgain)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofRestAgain = abi.encodeWithSelector(DomStrategyGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, dhofRest)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);

        revealAndResolve2P(turn, nonce3, nonce4, piskomateMoveUpAgain, dhofRestAgain);
        
        // piskomate made a mistake in poking the sleeping lion, he die, give all spoils to dhof
        uint256 loser_spoils = game.spoils(piskomate);
        uint256 winner_spoils = game.spoils(dhof);
        require(loser_spoils == 0, "Loser gets all their spoils taken.");
        require(winner_spoils == 7.9 ether, "Winner gets all the spoils of the defeated.");
        
        // Check new positions
        (,,,,,,,,uint256 x_piskomate_after,uint256 y_piskomate_after,,,bool isPiskomateInJail) = game.players(piskomate);
        (,,,,,,,,uint256 x_dhof_after,uint256 y_dhof_after,,,bool isDhofInJail) = game.players(dhof);

        // FIXME: this shit will be a private var in prod so... figure it out
        (uint jailCellX, uint jailCellY) = game.jailCell();

        // bytes32 jailCellBytes = stdstore
        //     .target(address(game))
        //     .sig("jailCell()")
        //     .read_bytes32();

        // console.logBytes32(jailCellBytes);

        require(x_piskomate_after == jailCellX && y_piskomate_after == jailCellY && isPiskomateInJail, "piskomate should be in jail");
        require(game.playingField(4, 4) == dhof, "Dhof (the victor) should be the only one in the previous disputed cell.");
        require(game.playingField(4, 5) == address(0), "piskomate's old position should be empty.");
        require(x_dhof_after == 4 && y_dhof_after == 4 && isDhofInJail == false, "dhof should be in piskomate's old position");
        // check player count reduced
        require(game.activePlayersCount() == 1, "Active player count should be zero.");

        // Check that game ends when only 1 active player remaining, and withdraw becomes available.
        require(game.winnerPlayer() == dhof, "Dhof should be declared the winner");

        // Withdraw should become available to Winner only
        vm.startPrank(piskomate);
        vm.expectRevert(
            abi.encodeWithSelector(
                DomStrategyGame.LoserTriedWithdraw.selector
            )
        );
        game.withdrawWinnerPlayer();
        vm.stopPrank();
        console.log("game.balance", address(game).balance);
        vm.startPrank(dhof);
        uint dhofSpoils = game.spoils(dhof);
        uint dhofCurrBal = address(dhof).balance;
        game.withdrawWinnerPlayer();
        require(dhof.balance == dhofCurrBal + dhofSpoils, "Dhof should get all the spoils.");
        require(game.spoils(dhof) == 0, "Winner spoils should be zero after withdraw.");
    }

    function testAllianceWinCondition() public {
        connect4();

        uint256 turn = game.currentTurn() + 1;
        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";
        bytes32 nonce3 = hex"03";
        bytes32 nonce4 = hex"04";

        game.start();

        /****** Turn 1 ******/

        /**
            |P| |D| |A| |W| | | |
            | | | | | | | | | | |
            | | | | | | | | | | |
            | | | | | | | | | | |
         */
        
        vm.startPrank(piskomate);
        bytes memory piskomateRest = abi.encodeWithSelector(DomStrategyGame.rest.selector, piskomate);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, piskomateRest)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofRest = abi.encodeWithSelector(DomStrategyGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, dhofRest)));
        vm.stopPrank();

        // create alliance
        vm.startPrank(arthur);
        bytes memory arthurCreateAlliance = abi.encodeWithSelector(DomStrategyGame.createAlliance.selector, arthur, 5, "Arthur's Eleven");
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, arthurCreateAlliance)));
        vm.stopPrank();
        
        vm.startPrank(w1nt3r);
        bytes memory w1nt3rRest = abi.encodeWithSelector(DomStrategyGame.rest.selector, w1nt3r);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, w1nt3rRest)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);
        
        revealAndResolve4P(turn, nonce1, nonce2, nonce3, nonce4, piskomateRest, dhofRest, arthurCreateAlliance, w1nt3rRest);

        /****** Turn 2 ******/
        uint256 allianceId = 1;
        turn = turn + 1;
        bytes32 nonce5 = hex"05";
        bytes32 nonce6 = hex"06";
        bytes32 nonce7 = hex"07";
        bytes32 nonce8 = hex"08";

        (address admin,,,,) = game.alliances(allianceId);
        console.log("Alliance Admin: ", admin);

        // Piskomate, Dhof join the alliance
        vm.startPrank(piskomate);
        bytes memory piskomateApplication = abi.encodePacked(turn, allianceId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(arthur_pk, keccak256(piskomateApplication));
        bytes memory piskomateJoin = abi.encodeWithSelector(DomStrategyGame.joinAlliance.selector, piskomate, allianceId, v, r, s);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce5, piskomateJoin)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofApplication = abi.encodePacked(turn, allianceId);
        (uint8 dhof_v, bytes32 dhof_r, bytes32 dhof_s) = vm.sign(arthur_pk, keccak256(dhofApplication));
        bytes memory dhofJoin = abi.encodeWithSelector(DomStrategyGame.joinAlliance.selector, dhof, allianceId, dhof_v, dhof_r, dhof_s);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce6, dhofJoin)));
        vm.stopPrank();

        // Arthur is the creator so he can just rest()
        vm.startPrank(arthur);
        bytes memory arthurRest = abi.encodeWithSelector(DomStrategyGame.rest.selector, arthur);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce7, arthurRest)));
        vm.stopPrank();
        
        // 1 stay out
        // W1nt3r doens't join but instead moves in position to attack Arthur
        vm.startPrank(w1nt3r);
        bytes memory w1nt3rMove = abi.encodeWithSelector(DomStrategyGame.move.selector, w1nt3r, int8(3));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce8, w1nt3rMove)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);

        revealAndResolve4P(turn, nonce5, nonce6, nonce7, nonce8, piskomateJoin, dhofJoin, arthurRest, w1nt3rMove);

        (address allianceAdmin, uint256 arthurAllianceId, uint256 membersCount, uint256 maxMembersCount,) = game.alliances(1);

        require(game.allianceAdmins(allianceId) == arthur && allianceAdmin == arthur, "Arthur should be the alliance admin.");
        require(membersCount == 3, "There should be 3 members after Pisko, Dhof join Arthur's Alliance.");
        require(maxMembersCount == 5, "Max members count should be as specified by creator");
        require(allianceId == arthurAllianceId, "Alliance Id should match in Player and Alliance structs (Foreign Key)");

        (,,,,,uint256 allianceId_w1nt3r,,,,,,,) = game.players(w1nt3r);
        (,,,,,uint256 allianceId_arthur,,,,,,,) = game.players(arthur);
        (,,,,,uint256 allianceId_piskomate,,,,,,,) = game.players(piskomate);
        (,,,,,uint256 allianceId_dhof,,,,,,,) = game.players(dhof);

        require(membersCount == 3, "Alliance should have 3 members after Pisko and Dhof join Arthur's Alliance.");
        require(allianceId_w1nt3r == 0, "w1nt3r should not be in an alliance");
        require(allianceId_dhof == 1, "Dhof should be in Alliance#1");
        require(allianceId_arthur == 1, "Arthur should be in Alliance#1");
        require(allianceId_piskomate == 1, "Piskomate should be in Alliance#1");

        /****** Turn 3 ******/
        turn = turn + 1;
        bytes32 nonce9 = hex"09";
        bytes32 nonce10 = hex"10";
        bytes32 nonce11 = hex"11";
        bytes32 nonce12 = hex"12";

        vm.startPrank(piskomate);
        bytes memory piskomateRestAgain = abi.encodeWithSelector(DomStrategyGame.rest.selector, piskomate);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce9, piskomateRestAgain)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofRestAgain = abi.encodeWithSelector(DomStrategyGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce10, dhofRestAgain)));
        vm.stopPrank();

        // give Arthur insane attack
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(arthur)
            .depth(7) // player.attack
            .checked_write(9000);

        // give w1nt3r shit hp
        stdstore
            .target(address(game))
            .sig("players(address)")
            .with_key(w1nt3r)
            .depth(6) // player.hp
            .checked_write(1);
        
        // let Arthur win the battle against W1nt3r, so his Alliance wins the game
        vm.startPrank(arthur);
        bytes memory arthurMoveAgain = abi.encodeWithSelector(DomStrategyGame.move.selector, arthur, int8(4));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce11, arthurMoveAgain)));
        vm.stopPrank();
        
        vm.startPrank(w1nt3r);
        bytes memory w1nt3rRestAgain = abi.encodeWithSelector(DomStrategyGame.rest.selector, w1nt3r);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce12, w1nt3rRestAgain)));
        vm.stopPrank();

        vm.warp(block.timestamp + 19 hours);
        revealAndResolve4P(turn, nonce9, nonce10, nonce11, nonce12, piskomateRestAgain, dhofRestAgain, arthurMoveAgain, w1nt3rRestAgain);

        // make sure alliance splits the spoils evenly.
        // TODO: maybe the incentive to put more at stake is that if you win in an alliance you get proportionately more of the total spoils.
        require(game.winningTeamSpoils() == 9.9 ether, "The total spoils to share should be the sum of all Ether the players put up at stake to connect.");

        vm.startPrank(arthur);
        game.withdrawWinnerAlliance();
        vm.stopPrank();

        vm.startPrank(piskomate);
        game.withdrawWinnerAlliance();
        vm.stopPrank();

        vm.startPrank(dhof);
        game.withdrawWinnerAlliance();
        vm.stopPrank();

        // each should get 3.3 ether at the end
        // FIXME: dhof fucking loses ether even though he won. therefore, should make rewards proportional
        require(arthur.balance == 3.3 ether);
        require(piskomate.balance == 3.3 ether);
        require(dhof.balance == 3.3 ether);

        // let each member withdraw their share
        vm.startPrank(w1nt3r);
        vm.expectRevert(abi.encodeWithSelector(
                DomStrategyGame.OnlyWinningAllianceMember.selector
            ));
        game.withdrawWinnerAlliance();
        vm.stopPrank();

        require(w1nt3r.balance == 0 ether);
    }
}
