// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import "./mocks/MockVRFCoordinatorV2.sol";
import "../../script/HelperConfig.sol";
import "../DominationGame.sol";
import "../interfaces/IDominationGame.sol";
import "../BaseCharacter.sol";

contract DominationGameTest is Test {
    using stdStorage for StdStorage;

    DominationGame public game;
    BaseCharacter public basicCharacter;

    uint256 JOINING_SPOILS = 1 ether;
    uint256 MINTING_FEE = 0.1 ether;
    uint256 STARTING_BALANCE = 6.9 ether;

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
    uint256 public staticTime;
    uint256 public INTERVAL = 10 seconds;
    uint256 public intendedStartTime = 10 seconds;

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
            ,
            ,
            bytes32 keyHash
        ) = helper.activeNetworkConfig();

        w1nt3r_pk = vm.deriveKey(mnemonic1, 0);
        w1nt3r = vm.addr(w1nt3r_pk);
        vm.label(w1nt3r, "w1nt3r");

        dhof_pk = vm.deriveKey(mnemonic2, 0);
        dhof = vm.addr(dhof_pk);
        vm.label(dhof, "dhof");

        piskomate_pk = vm.deriveKey(mnemonic3, 0);
        piskomate = vm.addr(piskomate_pk);
        vm.label(piskomate, "piskomate");

        arthur_pk = vm.deriveKey(mnemonic4, 0);
        arthur = vm.addr(arthur_pk);
        vm.label(arthur, "arthur");

        vm.deal(w1nt3r, STARTING_BALANCE);
        vm.deal(dhof, STARTING_BALANCE);
        vm.deal(piskomate, STARTING_BALANCE);
        vm.deal(arthur, STARTING_BALANCE);

        // Keeper
        staticTime = block.timestamp;
        vm.warp(staticTime);

        vm.startPrank(piskomate);
        // VRF
        vrfCoordinator = new MockVRFCoordinatorV2();
        uint64 subscriptionId = vrfCoordinator.createSubscription();
        uint96 FUND_AMOUNT = 1000 ether;
        vrfCoordinator.fundSubscription(subscriptionId, FUND_AMOUNT);   
    
        basicCharacter = new BaseCharacter();
        // game = new DominationGame(address(vrfCoordinator), link, subscriptionId, keyHash, INTERVAL, intendedStartTime);
        game = new DominationGame(address(vrfCoordinator), link, keyHash, subscriptionId, INTERVAL);

        vrfCoordinator.addConsumer(subscriptionId, address(game));
        console.log("piskomate: ", piskomate);
        console.log("dhof: ", dhof);
        console.log("arthur: ", arthur);
        console.log("w1nt3r: ", w1nt3r);
        vm.stopPrank();
    }

    function connect2() public {
        // init();
        vm.startPrank(piskomate);
        basicCharacter.mint{value: MINTING_FEE}(piskomate);
        basicCharacter.setApprovalForAll(address(game), true);
        game.connect{value: JOINING_SPOILS}(1, address(basicCharacter));
        vm.stopPrank();

        vm.startPrank(dhof);
        basicCharacter.mint{value: MINTING_FEE}(dhof);
        basicCharacter.setApprovalForAll(address(game), true);
        game.connect{value: JOINING_SPOILS}(2, address(basicCharacter));
        vm.stopPrank();
    }

    function connect4() public {
        connect2();
        
        vm.startPrank(arthur);
        basicCharacter.mint{value: MINTING_FEE}(arthur);
        basicCharacter.setApprovalForAll(address(game), true);
        game.connect{value: JOINING_SPOILS}(3, address(basicCharacter));
        vm.stopPrank();
        
        vm.startPrank(w1nt3r);
        basicCharacter.mint{value: MINTING_FEE}(w1nt3r);
        basicCharacter.setApprovalForAll(address(game), true);
        game.connect{value: JOINING_SPOILS}(4, address(basicCharacter));
        vm.stopPrank();
    }

    function reveal2P(uint256 turn, bytes32 nonce1,bytes32 nonce2,bytes memory call1, bytes memory call2) public {
        vm.prank(piskomate);
        game.reveal(turn, nonce1, call1);

        vm.prank(dhof);
        game.reveal(turn, nonce2, call2);

        vm.stopPrank();
    }

    function reveal4P(uint256 turn, bytes32 nonce1,bytes32 nonce2,bytes32 nonce3,bytes32 nonce4, bytes memory call1, bytes memory call2, bytes memory call3, bytes memory call4) public {
        vm.prank(piskomate);
        game.reveal(turn, nonce1, call1);

        vm.prank(dhof);
        game.reveal(turn, nonce2, call2);

        vm.prank(arthur);
        game.reveal(turn, nonce3, call3);

        vm.prank(w1nt3r);
        game.reveal(turn, nonce4, call4);

        vm.stopPrank();
    }


    function testConnect() public {
        connect2();
        (,address pisko_nft,uint256 pisko_tokenId,,,,,,uint256 x_piskomate,uint256 y_piskomate,,,) = game.players(piskomate);
        (,address dhof_nft,uint256 dhof_tokenId,,,,,,uint256 x_dhof,uint256 y_dhof,,,) = game.players(dhof);

        // require(game.spoils(piskomate) > 0, "Cannot play with 0 spoils, pleb.");
        // require(game.spoils(dhof) > 0, "Cannot play with 0 spoils, pleb.");
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

        // To make a move, you submit a hash of the intended move with the current turn, a nonce, and a call to either move or rest. Everyone's move is collected and then revealed at once after INTERVAL
        vm.prank(piskomate);
        bytes memory call1 = abi.encodeWithSelector(DominationGame.rest.selector, piskomate);

        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, call1)));
        
        vm.prank(dhof);
        bytes memory call2 = abi.encodeWithSelector(
            DominationGame.move.selector,
            dhof,
            int8(2)
        );

        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, call2)));

        // every INTERVAL all players need to reveal their respective move for that turn.
        vm.warp(block.timestamp +  INTERVAL + (INTERVAL/4));

        reveal2P(turn, nonce1, nonce2, call1, call2);

        (,,,,,,uint256 hp_piskomate,,uint256 x_piskomate,uint256 y_piskomate,bytes32 pendingMoveCommitment_piskomate,,) = game.players(piskomate);
        (,,,,,,uint256 hp_dhof,,uint256 x_dhof,uint256 y_dhof,bytes32 pendingMoveCommitment_dhof,,) = game.players(dhof);

        require(x_piskomate == 0 && y_piskomate == 0, "piskomate should have remained in place from rest()");
        require(x_dhof == 3 && y_dhof == 0, "Dhof should have moved right one square from move(dhof, 2)");
        require(game.playingField(3, 0) == dhof, "Playing field should record dhof new position");
        require(game.playingField(0, 0) == piskomate, "Playing field should record piskomate new position");
        require(hp_dhof == 1000, "piskomate should have recovered 2 hp from rest()");
        require(hp_piskomate == 1002, "Dhof should have same hp remaining as before from move()");
        require(pendingMoveCommitment_dhof == "" && pendingMoveCommitment_piskomate == "", "Pending move commitment for both should be cleared after resolution.");
    }

    function testNoRevealOrNoSubmitPenalty() public {
        connect2();

        game.start();
        /******* Game Stage 0: Submit ********/
        // bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";
        uint256 turn = 1;

        // Piskomate straight up doesn't submit
        // ...

        // Let's say dhof submits then doesn't reveal        
        vm.prank(dhof);
        bytes memory call2 = abi.encodeWithSelector(
            DominationGame.move.selector,
            dhof,
            int8(2)
        );
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, call2)));
        /******* Game Stage 1: Reveal ********/
        vm.warp(block.timestamp +  INTERVAL + 1);
        game.performUpkeep("");

        // Nobody Reveals

        /******* Game Stage 2: Resolve ********/
        vm.warp(block.timestamp +  INTERVAL + 1);
        (,bytes memory performData) = game.checkUpkeep("");
        game.performUpkeep(performData);
        
        address inmate0 = game.inmates(0);
        address inmate1 = game.inmates(1);
        (uint256 jailX, uint256 jailY) = game.jailCell();
        
        
        (,address pisko_nft,uint256 pisko_tokenId,,,,,, uint256 pisko_x, uint256 pisko_y,,,bool pisko_inJail) = game.players(piskomate);

        // Piskomate didn't submit at all so check confiscation
        require(inmate0 == piskomate || inmate1 == piskomate, "Piskomate should be sent to jail since he didn't submit or reveal");
        require(jailX == pisko_x && jailY == pisko_y && pisko_inJail == true, "Pisko position should be jail cell.");
        require(IERC721(pisko_nft).balanceOf(piskomate) == 0, "Piskomate should no longer have his Loot");
        require(IERC721(pisko_nft).ownerOf(pisko_tokenId) == address(game), "The Game should now have Piskomate's Loot");

        (,address dhof_nft, uint256 dhof_tokenId,,,,uint256 dhof_hp,, uint256 x, uint256 y,,,bool inJail) = game.players(dhof);
        
        // Dhof submitted but didn't reveal so just check he's in jail
        require(jailX == x && jailY == y && inJail == true, "Dhof position should be jail cell.");
        require(dhof_hp == 0, "Dhof hp should be 0 in jail.");
        require(inmate0 == dhof || inmate1 == dhof, "Dhof should be sent to jail since he didn't reveal");
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

        // game.setPlayingField(4, 5, piskomate);
        
        vm.startPrank(piskomate);
        bytes memory piskomateMoveUp = abi.encodeWithSelector(DominationGame.move.selector, piskomate, int8(-1));
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
        
        // game.setPlayingField(4, 4, dhof);

        vm.startPrank(dhof);
        bytes memory dhofRest = abi.encodeWithSelector(DominationGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, dhofRest)));
        vm.stopPrank();

        vm.warp(block.timestamp +  INTERVAL + (INTERVAL/4));

        reveal2P(turn, nonce1, nonce2, piskomateMoveUp, dhofRest);

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
        bytes memory piskomateMoveUpAgain = abi.encodeWithSelector(DominationGame.move.selector, piskomate, int8(-1));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, piskomateMoveUpAgain)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofRestAgain = abi.encodeWithSelector(DominationGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, dhofRest)));
        vm.stopPrank();

        vm.warp(block.timestamp +  INTERVAL + (INTERVAL/4));

        reveal2P(turn, nonce3, nonce4, piskomateMoveUpAgain, dhofRestAgain);
        
        // piskomate made a mistake in poking the sleeping lion, he die, give all spoils to dhof
        // uint256 loser_spoils = game.spoils(piskomate);
        // uint256 winner_spoils = game.spoils(dhof);
        // require(loser_spoils == 0, "Loser gets all their spoils taken.");
        // require(winner_spoils == 7.9 ether, "Winner gets all the spoils of the defeated.");
        
        // Check new positions
        (,,,,,,,,uint256 x_piskomate_after,uint256 y_piskomate_after,,,bool isPiskomateInJail) = game.players(piskomate);
        (,,,,,,,,uint256 x_dhof_after,uint256 y_dhof_after,,,bool isDhofInJail) = game.players(dhof);

        // FIXME: this shit will be a private var in prod so... figure it out
        // (uint jailCellX, uint jailCellY) = game.jailCell();

        // bytes32 jailCellBytes = stdstore
        //     .target(address(game))
        //     .sig("jailCell()")
        //     .read_bytes32();

        // console.logBytes32(jailCellBytes);

        // require(x_piskomate_after == jailCellX && y_piskomate_after == jailCellY && isPiskomateInJail, "piskomate should be in jail");
        require(game.playingField(4, 4) == dhof, "Dhof (the victor) should be the only one in the previous disputed cell.");
        require(game.playingField(4, 5) == address(0), "piskomate's old position should be empty.");
        require(x_dhof_after == 4 && y_dhof_after == 4 && isDhofInJail == false, "dhof should be in piskomate's old position");
        // check player count reduced
        require(game.activePlayersCount() == 1, "Active player count should be zero.");

        // Check that game ends when only 1 active player remaining, and withdraw becomes available.
        require(game.winnerPlayer() == dhof, "Dhof should be declared the winner");

        // Withdraw should become available to Winner only
        vm.startPrank(piskomate);
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         DominationGame.LoserTriedWithdraw.selector
        //     )
        // );
        game.withdrawWinnerPlayer();
        vm.stopPrank();
        console.log("game.balance", address(game).balance);
        vm.startPrank(dhof);
        // uint dhofSpoils = game.spoils(dhof);
        uint dhofCurrBal = address(dhof).balance;
        game.withdrawWinnerPlayer();
        // require(dhof.balance == dhofCurrBal + dhofSpoils, "Dhof should get all the spoils.");
        // require(game.spoils(dhof) == 0, "Winner spoils should be zero after withdraw.");
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
        /******* Game Stage 0: Submit ********/
        vm.startPrank(piskomate);
        bytes memory piskomateRest = abi.encodeWithSelector(DominationGame.rest.selector, piskomate);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, piskomateRest)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofRest = abi.encodeWithSelector(DominationGame.rest.selector, dhof);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, dhofRest)));
        vm.stopPrank();

        // create alliance
        vm.startPrank(arthur);
        bytes memory arthurCreateAlliance = abi.encodeWithSelector(DominationGame.createAlliance.selector, arthur, 5, "Arthur's Eleven");
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, arthurCreateAlliance)));
        vm.stopPrank();
        
        vm.startPrank(w1nt3r);
        bytes memory w1nt3rRest = abi.encodeWithSelector(DominationGame.rest.selector, w1nt3r);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, w1nt3rRest)));
        vm.stopPrank();

        vm.warp(block.timestamp + INTERVAL + 1);
        game.performUpkeep("");
        /******* Game Stage 1: Reveal ********/
        reveal4P(turn, nonce1, nonce2, nonce3, nonce4, piskomateRest, dhofRest, arthurCreateAlliance, w1nt3rRest);
        
        /******* Game Stage 2: Resolve ********/
        vm.warp(block.timestamp + INTERVAL + 1);
        (,bytes memory performData) = game.checkUpkeep("");
        game.performUpkeep(performData);
        /****** Turn 2 ******/
        vm.warp(block.timestamp + INTERVAL + 1);
        game.performUpkeep("");
        /******* Game Stage 0: Submit ********/
        uint256 allianceId = 1;
        turn = turn + 1;
        bytes32 nonce5 = hex"05";
        bytes32 nonce6 = hex"06";
        bytes32 nonce7 = hex"07";
        bytes32 nonce8 = hex"08";

        (address admin,,,,,,) = game.alliances(allianceId);
        console.log("Alliance Admin: ", admin);

        // Piskomate, Dhof join the alliance
        vm.startPrank(piskomate);
        bytes memory piskomateApplication = abi.encodePacked(turn, allianceId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(arthur_pk, keccak256(piskomateApplication));
        bytes memory piskomateJoin = abi.encodeWithSelector(DominationGame.joinAlliance.selector, piskomate, allianceId, v, r, s);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce5, piskomateJoin)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofApplication = abi.encodePacked(turn, allianceId);
        (uint8 dhof_v, bytes32 dhof_r, bytes32 dhof_s) = vm.sign(arthur_pk, keccak256(dhofApplication));
        bytes memory dhofJoin = abi.encodeWithSelector(DominationGame.joinAlliance.selector, dhof, allianceId, dhof_v, dhof_r, dhof_s);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce6, dhofJoin)));
        vm.stopPrank();

        // Arthur is the creator so he can just rest()
        vm.startPrank(arthur);
        bytes memory arthurRest = abi.encodeWithSelector(DominationGame.rest.selector, arthur);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce7, arthurRest)));
        vm.stopPrank();
        
        // 1 stay out
        // W1nt3r doens't join but instead moves in position to attack Arthur
        vm.startPrank(w1nt3r);
        bytes memory w1nt3rMove = abi.encodeWithSelector(DominationGame.move.selector, w1nt3r, int8(-2));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce8, w1nt3rMove)));
        vm.stopPrank();

        vm.warp(block.timestamp + INTERVAL + 1);
        game.performUpkeep("");
        /******* Game Stage 1: Reveal ********/
        reveal4P(turn, nonce5, nonce6, nonce7, nonce8, piskomateJoin, dhofJoin, arthurRest, w1nt3rMove);
        /******* Game Stage 2: Resolve ********/
        vm.warp(block.timestamp + INTERVAL + 1);
        (,performData) = game.checkUpkeep("");
        game.performUpkeep(performData);

        (address allianceAdmin, uint256 arthurAllianceId, uint256 activeMembersCount, uint256 membersCount, uint256 maxMembersCount,,) = game.alliances(1);

        require(maxMembersCount == 5, "Max members count should be as specified by creator");
        require(allianceId == arthurAllianceId, "Alliance Id should match in Player and Alliance structs (Foreign Key)");

        (,,,,,uint256 allianceId_w1nt3r,,,uint256 w1nt3r_x, uint256 w1nt3r_y,,,) = game.players(w1nt3r);
        (,,,,,uint256 allianceId_arthur,,,,,,,) = game.players(arthur);
        (,,,,,uint256 allianceId_piskomate,,,,,,,) = game.players(piskomate);
        (,,,,,uint256 allianceId_dhof,,,,,,,) = game.players(dhof);

        require(membersCount == 3, "Alliance should have 3 members after Pisko and Dhof join Arthur's Alliance.");
        require(allianceId_w1nt3r == 0, "w1nt3r should not be in an alliance");
        require(allianceId_dhof == 1, "Dhof should be in Alliance#1");
        require(allianceId_arthur == 1, "Arthur should be in Alliance#1");
        require(allianceId_piskomate == 1, "Piskomate should be in Alliance#1");
        require(w1nt3r_x == 5, "w1nt3r should be at x=5");
        require(w1nt3r_y == 0, "w1nt3r should be at y=0");

        /****** Turn 3 ******/
        vm.warp(block.timestamp + INTERVAL + 1);
        game.performUpkeep("");
        turn = turn + 1;
        bytes32 nonce9 = hex"09";
        bytes32 nonce10 = hex"10";
        bytes32 nonce11 = hex"11";
        bytes32 nonce12 = hex"12";

        /******* Game Stage 0: Submit ********/
        vm.startPrank(piskomate);
        bytes memory piskomateRestAgain = abi.encodeWithSelector(DominationGame.rest.selector, piskomate);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce9, piskomateRestAgain)));
        vm.stopPrank();

        vm.startPrank(dhof);
        bytes memory dhofRestAgain = abi.encodeWithSelector(DominationGame.rest.selector, dhof);
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
        bytes memory arthurMoveAgain = abi.encodeWithSelector(DominationGame.move.selector, arthur, int8(2));
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce11, arthurMoveAgain)));
        vm.stopPrank();
        
        vm.startPrank(w1nt3r);
        bytes memory w1nt3rRestAgain = abi.encodeWithSelector(DominationGame.rest.selector, w1nt3r);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce12, w1nt3rRestAgain)));
        vm.stopPrank();

        vm.warp(block.timestamp + INTERVAL + 1);
        game.performUpkeep("");
        /******* Game Stage 1: Reveal ********/
        reveal4P(turn, nonce9, nonce10, nonce11, nonce12, piskomateRestAgain, dhofRestAgain, arthurMoveAgain, w1nt3rRestAgain);
        /******* Game Stage 2: Resolve ********/
        vm.warp(block.timestamp + INTERVAL + 1);
        (,performData) = game.checkUpkeep("");
        game.performUpkeep(performData);

        /******* Game Stage 3: PendingWithdrawals ********/

        // make sure alliance splits the spoils proportionately to their staked balance
        require(game.winningTeamSpoils() == 4 ether, "The total spoils to share should be the sum of all Ether the players put up at stake to connect.");

        // let each member withdraw their share
        vm.startPrank(arthur);
        game.withdrawWinnerAlliance(); // 
        vm.stopPrank();

        vm.startPrank(piskomate);
        game.withdrawWinnerAlliance(); // 1 / 8.9 * 9.9
        vm.stopPrank();

        vm.startPrank(dhof);
        game.withdrawWinnerAlliance(); // 6.9 / 8.9 * 9.9
        vm.stopPrank();

        console.log("arthur.balance ", arthur.balance);
        console.log("piskomate.balance ", piskomate.balance);
        console.log("dhof.balance ", dhof.balance);
        console.log("w1nt3r.balance ", w1nt3r.balance);

        require(arthur.balance >= 7.13 ether, "Arthur should end with 7.133333333333333333 Ether");
        require(piskomate.balance >= 7.13 ether, "Pisko should end with 7.133333333333333333 Ether");
        require(dhof.balance >= 7.13 ether, "Dhof should end with 7.133333333333333333 Ether");

        // vm.startPrank(w1nt3r);
        // vm.expectRevert(abi.encodeWithSelector(
        //         DominationGame.OnlyWinningAllianceMember.selector
        //     ));
        // game.withdrawWinnerAlliance();
        // vm.stopPrank();

        // require(w1nt3r.balance == (STARTING_BALANCE - JOINING_SPOILS - MINTING_FEE) * 1 ether);
        require(w1nt3r.balance == 5.8 ether, "w1nt3r should end with 5.8 Ether");
    }

    // function testJailbreak() public {
    //     connect4();

    //     uint256 turn = game.currentTurn() + 1;
    //     bytes32 nonce1 = hex"01";
    //     bytes32 nonce2 = hex"02";
    //     bytes32 nonce3 = hex"03";
    //     bytes32 nonce4 = hex"04";

    //     game.start();

    //     (uint256 jailX, uint256 jailY) = game.jailCell();
    //     // assume Pisko & Dhof are in jail
    //     // TODO: this whould be an internal function
    //     game.sendToJail(dhof);
    //     game.sendToJail(piskomate);
        
    //     stdstore
    //         .target(address(game))
    //         .sig("players(address)")
    //         .with_key(arthur)
    //         .depth(8) // x
    //         .checked_write(jailX);
        
    //     stdstore
    //         .target(address(game))
    //         .sig("players(address)")
    //         .with_key(arthur)
    //         .depth(9) // y
    //         .checked_write(jailY - 1);

    //     vm.startPrank(piskomate);
    //     bytes memory piskomateCall = abi.encodeWithSelector(DominationGame.rest.selector, piskomate);
    //     game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, piskomateCall)));
    //     vm.stopPrank();

    //     vm.startPrank(dhof);
    //     bytes memory dhofCall = abi.encodeWithSelector(DominationGame.rest.selector, dhof);
    //     game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, dhofCall)));
    //     vm.stopPrank();

    //     // let Arthur land on jail cell
    //     vm.startPrank(arthur);
    //     bytes memory arthurCall = abi.encodeWithSelector(DominationGame.move.selector, arthur, int8(1));
    //     game.submit(turn, keccak256(abi.encodePacked(turn, nonce3, arthurCall)));
    //     vm.stopPrank();
            
    //     //  w1nt3r can do wtv idc
    //     vm.startPrank(w1nt3r);
    //     bytes memory w1nt3rCall = abi.encodeWithSelector(DominationGame.rest.selector, w1nt3r);
    //     game.submit(turn, keccak256(abi.encodePacked(turn, nonce4, w1nt3rCall)));
    //     vm.stopPrank();
        
    //     vm.warp(block.timestamp + INTERVAL + (INTERVAL/4));

    //     reveal4P(turn, nonce1, nonce2, nonce3, nonce4, piskomateCall, dhofCall, arthurCall, w1nt3rCall);
    //     // verify everyones gets out

    //     // next round if >=2 people stay on the jail cell they battle as normal
    // }

    function testCheckupReturnsFalseBeforeTime() public {
        (bool upkeepNeeded, ) = game.checkUpkeep("0x");
        assertTrue(!upkeepNeeded);
    }

    function testCheckupReturnsTrueAfterTime() public {
        vm.warp(staticTime + INTERVAL + 1); // Needs to be more than the interval
        (bool upkeepNeeded, ) = game.checkUpkeep("0x");
        assertTrue(upkeepNeeded);
    }

    // function testPerformUpkeepCallsResolve() public {
    //     vm.warp(staticTime + INTERVAL + 1);
    //     game.performUpkeep("0x");

    //     vm.warp(staticTime + INTERVAL + 1);
    //     game.performUpkeep("0x");
        
    // }

    function testPerformUpkeepUpdatesTimeAndStartsGame() public {
        game.requestRandomWords();
        vrfCoordinator.fulfillRandomWords(
            game.vrf_requestId(),
            address(game)
        );

        /** ===== Turn 0 ===== */
        connect2();
        vm.warp(game.gameStartTimestamp() + 2 seconds);
        (bool upkeepNeeded, bytes memory performData) = game.checkUpkeep("0x");
        assertTrue(upkeepNeeded);
        
        game.performUpkeep(performData);
        console.log("block.timestamp ", block.timestamp);

        // Assert Game is Started
        assert(game.gameStarted() == true);
        assert(game.gameStage() == GameStage.Submit);
        assert(game.currentTurnStartTimestamp() == block.timestamp);
        // (uint jailX, uint jailY) = game.jailCell();
        // assert(jailX != 0 && jailY != 0);
        assert(game.currentTurn() == 1);
        assert(game.lastUpkeepTimestamp() == block.timestamp);
        
        /** ===== Turn 1, Game Stage 0 (Submit) ===== */
        vm.warp(game.gameStartTimestamp() + 1 seconds);
        
        bytes memory call1 = abi.encodeWithSelector(DominationGame.rest.selector, piskomate);
        bytes memory call2 = abi.encodeWithSelector(DominationGame.rest.selector, w1nt3r);
        uint256 turn = game.currentTurn();
        bytes32 nonce1 = hex"01";
        bytes32 nonce2 = hex"02";
        
        vm.startPrank(piskomate);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce1, call1)));
        vm.stopPrank();

        vm.startPrank(w1nt3r);
        game.submit(turn, keccak256(abi.encodePacked(turn, nonce2, call2)));
        vm.stopPrank();

        game.performUpkeep(performData);
        console.log("block.timestamp ", block.timestamp);
        assert(game.gameStage() == GameStage.Reveal);
        
        /** ===== Turn 1, Game Stage 1 (Reveal) ===== */
        vm.warp(block.timestamp + INTERVAL + 1 seconds);

        vm.startPrank(piskomate);
        game.reveal(turn, nonce1, call1);
        vm.stopPrank();

        vm.startPrank(w1nt3r);
        game.reveal(turn, nonce2, call2);
        vm.stopPrank();

        (upkeepNeeded, performData) = game.checkUpkeep("0x");
        assertTrue(upkeepNeeded);
        
        // Assert Upkeep resolves from here on out
        game.performUpkeep(performData);
        console.log("block.timestamp ", block.timestamp);
        assert(game.gameStage() == GameStage.Resolve);
        assert(game.currentTurn() == 2);

    }

    // function testFuzzingExample(bytes memory variant) public {
    //     stdstore
    //         .target(address(game))
    //         .sig("gameStarted")
    //         .checked_write(true);

    //     // We expect this to fail, no matter how different the input is!
    //     vm.expectRevert(bytes("Time interval not met."));
    //     game.performUpkeep(variant);
    // }
}
