// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BotTheHouseEscrow.sol";

contract BotTheHouseEscrowTest is Test {
    BotTheHouseEscrow public escrow;

    address public owner   = address(this);
    address public settler = makeAddr("settler");
    address public house   = makeAddr("house");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");

    uint256 public constant BUY_IN   = 1 ether;
    uint256 public constant RAKE_BPS = 500;

    bytes32 public gameId = keccak256("game_1");

    function setUp() public {
        escrow = new BotTheHouseEscrow(house, settler, RAKE_BPS);
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
    }

    // --- helpers ---
    function _createAndDeposit(bytes32 gId, address[] memory players) internal {
        vm.prank(settler);
        escrow.createGame(gId, BUY_IN);
        for (uint i = 0; i < players.length; i++) {
            vm.prank(players[i]);
            escrow.deposit{value: BUY_IN}(gId);
        }
    }

    function _twoPlayerGame() internal returns (bytes32 gId) {
        gId = gameId;
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        _createAndDeposit(gId, players);
    }

    // --- createGame ---
    function test_CreateGame() public {
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);
        (uint256 buyIn,, BotTheHouseEscrow.GameStatus status,,) = escrow.getGame(gameId);
        assertEq(buyIn, BUY_IN);
        assertEq(uint256(status), uint256(BotTheHouseEscrow.GameStatus.Open));
    }

    function test_CreateGame_RevertIfDuplicate() public {
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);
        vm.prank(settler);
        vm.expectRevert(BotTheHouseEscrow.GameExists.selector);
        escrow.createGame(gameId, BUY_IN);
    }

    function test_CreateGame_RevertIfNotSettler() public {
        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.NotSettler.selector);
        escrow.createGame(gameId, BUY_IN);
    }

    // --- deposit ---
    function test_Deposit() public {
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);

        vm.prank(player1);
        escrow.deposit{value: BUY_IN}(gameId);

        assertTrue(escrow.hasDeposited(gameId, player1));
        (,uint256 totalPot,,,) = escrow.getGame(gameId);
        assertEq(totalPot, BUY_IN);
    }

    function test_Deposit_RevertIfWrongAmount() public {
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);

        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.WrongBuyIn.selector);
        escrow.deposit{value: 0.5 ether}(gameId);
    }

    function test_Deposit_RevertIfDuplicate() public {
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);

        vm.prank(player1);
        escrow.deposit{value: BUY_IN}(gameId);

        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.AlreadyDeposited.selector);
        escrow.deposit{value: BUY_IN}(gameId);
    }

    function test_Deposit_RevertIfGameNotOpen() public {
        _twoPlayerGame();

        vm.prank(settler);
        escrow.startGame(gameId);

        vm.prank(player3);
        vm.expectRevert(BotTheHouseEscrow.GameNotOpen.selector);
        escrow.deposit{value: BUY_IN}(gameId);
    }

    // --- startGame ---
    function test_StartGame() public {
        _twoPlayerGame();

        vm.prank(settler);
        escrow.startGame(gameId);

        (,,BotTheHouseEscrow.GameStatus status,,) = escrow.getGame(gameId);
        assertEq(uint256(status), uint256(BotTheHouseEscrow.GameStatus.InProgress));
    }

    function test_StartGame_RevertIfNotOpen() public {
        _twoPlayerGame();

        vm.prank(settler);
        escrow.startGame(gameId);

        vm.prank(settler);
        vm.expectRevert(BotTheHouseEscrow.GameNotOpen.selector);
        escrow.startGame(gameId);
    }

    function test_StartGame_RevertIfNotSettler() public {
        _twoPlayerGame();

        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.NotSettler.selector);
        escrow.startGame(gameId);
    }

    // --- settle ---
    function test_Settle_SingleWinner() public {
        _twoPlayerGame();
        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 totalPot = BUY_IN * 2;
        uint256 rake = (totalPot * RAKE_BPS) / 10000;
        uint256 winnerAmount = totalPot - rake;

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = winnerAmount;

        uint256 player1Before = player1.balance;
        uint256 houseBefore = house.balance;

        vm.prank(settler);
        escrow.settle(gameId, winners, amounts, keccak256("result"));

        assertEq(player1.balance - player1Before, winnerAmount);
        assertEq(house.balance - houseBefore, rake);

        (,,BotTheHouseEscrow.GameStatus status,,) = escrow.getGame(gameId);
        assertEq(uint256(status), uint256(BotTheHouseEscrow.GameStatus.Settled));
    }

    function test_Settle_SplitPot() public {
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        _createAndDeposit(gameId, players);

        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 totalPot = BUY_IN * 2;
        uint256 rake = (totalPot * RAKE_BPS) / 10000;
        uint256 splitAmount = (totalPot - rake) / 2;

        address[] memory winners = new address[](2);
        winners[0] = player1;
        winners[1] = player2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = splitAmount;
        amounts[1] = splitAmount;

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;

        vm.prank(settler);
        escrow.settle(gameId, winners, amounts, keccak256("result"));

        assertEq(player1.balance - p1Before, splitAmount);
        assertEq(player2.balance - p2Before, splitAmount);
    }

    function test_Settle_RakeCalculation() public {
        _twoPlayerGame();
        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 totalPot = BUY_IN * 2;
        uint256 expectedRake = (totalPot * RAKE_BPS) / 10000;
        uint256 winnerAmount = totalPot - expectedRake;

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = winnerAmount;

        uint256 houseBefore = house.balance;
        vm.prank(settler);
        escrow.settle(gameId, winners, amounts, keccak256("result"));

        assertEq(house.balance - houseBefore, expectedRake);
    }

    function test_Settle_RevertIfOverdistribution() public {
        _twoPlayerGame();
        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 totalPot = BUY_IN * 2;

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = totalPot; // full pot without accounting for rake → overdistribution

        vm.prank(settler);
        vm.expectRevert(BotTheHouseEscrow.Overdistribution.selector);
        escrow.settle(gameId, winners, amounts, keccak256("result"));
    }

    function test_Settle_RevertIfNotInProgress() public {
        _twoPlayerGame();
        // game is Open, not InProgress

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = BUY_IN;

        vm.prank(settler);
        vm.expectRevert(BotTheHouseEscrow.GameNotInProgress.selector);
        escrow.settle(gameId, winners, amounts, keccak256("result"));
    }

    function test_Settle_RevertIfNotSettler() public {
        _twoPlayerGame();
        vm.prank(settler);
        escrow.startGame(gameId);

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = BUY_IN;

        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.NotSettler.selector);
        escrow.settle(gameId, winners, amounts, keccak256("result"));
    }

    // --- cancel ---
    function test_Cancel_FromOpenState() public {
        _twoPlayerGame();

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;

        escrow.cancel(gameId);

        assertEq(player1.balance - p1Before, BUY_IN);
        assertEq(player2.balance - p2Before, BUY_IN);

        (,,BotTheHouseEscrow.GameStatus status,,) = escrow.getGame(gameId);
        assertEq(uint256(status), uint256(BotTheHouseEscrow.GameStatus.Cancelled));
    }

    function test_Cancel_FromInProgressState() public {
        _twoPlayerGame();
        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;

        escrow.cancel(gameId);

        assertEq(player1.balance - p1Before, BUY_IN);
        assertEq(player2.balance - p2Before, BUY_IN);
    }

    function test_Cancel_RefundsAllPlayers() public {
        bytes32 gId = keccak256("game_refund");
        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;
        _createAndDeposit(gId, players);

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;
        uint256 p3Before = player3.balance;

        escrow.cancel(gId);

        assertEq(player1.balance - p1Before, BUY_IN);
        assertEq(player2.balance - p2Before, BUY_IN);
        assertEq(player3.balance - p3Before, BUY_IN);
    }

    function test_Cancel_RevertIfAlreadySettled() public {
        _twoPlayerGame();
        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 totalPot = BUY_IN * 2;
        uint256 rake = (totalPot * RAKE_BPS) / 10000;

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = totalPot - rake;

        vm.prank(settler);
        escrow.settle(gameId, winners, amounts, keccak256("result"));

        vm.expectRevert(BotTheHouseEscrow.AlreadySettled.selector);
        escrow.cancel(gameId);
    }

    function test_Cancel_RevertIfNotOwner() public {
        _twoPlayerGame();

        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.NotOwner.selector);
        escrow.cancel(gameId);
    }

    // --- admin ---
    function test_SetRakeRate() public {
        escrow.setRakeRate(300);
        assertEq(escrow.rakeRateBps(), 300);
    }

    function test_SetRakeRate_RevertIfAbove1000Bps() public {
        vm.expectRevert(BotTheHouseEscrow.RakeTooHigh.selector);
        escrow.setRakeRate(1001);
    }

    function test_SetRakeRate_RevertIfNotOwner() public {
        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.NotOwner.selector);
        escrow.setRakeRate(300);
    }

    function test_SetSettlerAddress() public {
        address newSettler = makeAddr("newSettler");
        escrow.setSettlerAddress(newSettler);
        assertEq(escrow.settlerAddress(), newSettler);
    }

    function test_SetOwner() public {
        address newOwner = makeAddr("newOwner");
        escrow.setOwner(newOwner);
        assertEq(escrow.owner(), newOwner);
    }

    // --- full flows ---
    function test_FullGameFlow_TwoPlayers() public {
        // create
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);

        // deposit x2
        vm.prank(player1);
        escrow.deposit{value: BUY_IN}(gameId);
        vm.prank(player2);
        escrow.deposit{value: BUY_IN}(gameId);

        // start
        vm.prank(settler);
        escrow.startGame(gameId);

        uint256 totalPot = BUY_IN * 2;
        uint256 rake = (totalPot * RAKE_BPS) / 10000;
        uint256 winnerAmount = totalPot - rake;

        // settle
        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = winnerAmount;

        uint256 p1Before = player1.balance;
        uint256 houseBefore = house.balance;

        vm.prank(settler);
        escrow.settle(gameId, winners, amounts, keccak256("result_hash"));

        // assert winner balance and rake
        assertEq(player1.balance - p1Before, winnerAmount);
        assertEq(house.balance - houseBefore, rake);

        (,,BotTheHouseEscrow.GameStatus status, bytes32 rHash,) = escrow.getGame(gameId);
        assertEq(uint256(status), uint256(BotTheHouseEscrow.GameStatus.Settled));
        assertEq(rHash, keccak256("result_hash"));
    }

    function test_FullGameFlow_ThreePlayers_SplitPot() public {
        bytes32 gId = keccak256("game_split");
        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;

        // create -> deposit x3
        _createAndDeposit(gId, players);

        // start
        vm.prank(settler);
        escrow.startGame(gId);

        uint256 totalPot = BUY_IN * 3;
        uint256 rake = (totalPot * RAKE_BPS) / 10000;
        uint256 remaining = totalPot - rake;
        uint256 splitAmount = remaining / 2;

        // settle with 2 equal winners
        address[] memory winners = new address[](2);
        winners[0] = player1;
        winners[1] = player2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = splitAmount;
        amounts[1] = splitAmount;

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;
        uint256 houseBefore = house.balance;

        vm.prank(settler);
        escrow.settle(gId, winners, amounts, keccak256("split_result"));

        // assert split
        assertEq(player1.balance - p1Before, splitAmount);
        assertEq(player2.balance - p2Before, splitAmount);
        assertEq(house.balance - houseBefore, rake);
    }

    // --- fuzz ---
    function testFuzz_Deposit_WrongAmount(uint256 wrongAmount) public {
        vm.assume(wrongAmount != BUY_IN);
        vm.prank(settler);
        escrow.createGame(gameId, BUY_IN);
        vm.deal(player1, wrongAmount);
        vm.prank(player1);
        vm.expectRevert(BotTheHouseEscrow.WrongBuyIn.selector);
        escrow.deposit{value: wrongAmount}(gameId);
    }

    function testFuzz_RakeCalculation(uint256 rakeBps) public {
        vm.assume(rakeBps <= 1000);
        BotTheHouseEscrow fuzzEscrow = new BotTheHouseEscrow(house, settler, rakeBps);

        bytes32 fuzzGameId = keccak256("fuzz_game");
        vm.prank(settler);
        fuzzEscrow.createGame(fuzzGameId, BUY_IN);

        vm.prank(player1);
        fuzzEscrow.deposit{value: BUY_IN}(fuzzGameId);
        vm.prank(player2);
        fuzzEscrow.deposit{value: BUY_IN}(fuzzGameId);

        vm.prank(settler);
        fuzzEscrow.startGame(fuzzGameId);

        uint256 totalPot = BUY_IN * 2;
        uint256 expectedRake = (totalPot * rakeBps) / 10000;
        uint256 winnerAmount = totalPot - expectedRake;

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = winnerAmount;

        uint256 houseBefore = house.balance;
        vm.prank(settler);
        fuzzEscrow.settle(fuzzGameId, winners, amounts, keccak256("fuzz_result"));

        // assert rake == totalPot * rakeBps / 10000
        assertEq(house.balance - houseBefore, expectedRake);
    }
}
