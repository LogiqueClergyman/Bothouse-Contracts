// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract BotTheHouseEscrow {

    address public owner;
    address public houseWallet;
    uint256 public rakeRateBps;        // e.g. 500 = 5%. Max enforced: 1000 (10%).
    address public settlerAddress;     // Only this address may call settle()

    enum GameStatus { NonExistent, Open, InProgress, Settled, Cancelled }

    struct Game {
        uint256 buyIn;
        uint256 totalPot;
        GameStatus status;
        bytes32 resultHash;
        address[] players;
    }

    mapping(bytes32 => Game) public games;
    mapping(bytes32 => mapping(address => bool)) public hasDeposited;

    event GameCreated(bytes32 indexed gameId, uint256 buyIn);
    event Deposited(bytes32 indexed gameId, address indexed player, uint256 amount);
    event GameStarted(bytes32 indexed gameId);
    event Settled(bytes32 indexed gameId, bytes32 resultHash, uint256 rake);
    event Cancelled(bytes32 indexed gameId);
    event RakeUpdated(uint256 oldRate, uint256 newRate);
    event SettlerUpdated(address oldSettler, address newSettler);

    error GameExists();
    error GameNotFound();
    error GameNotOpen();
    error GameNotInProgress();
    error AlreadySettled();
    error WrongBuyIn();
    error AlreadyDeposited();
    error RakeTooHigh();
    error ArrayMismatch();
    error Overdistribution();
    error NotOwner();
    error NotSettler();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlySettler() {
        if (msg.sender != settlerAddress) revert NotSettler();
        _;
    }

    constructor(
        address _houseWallet,
        address _settlerAddress,
        uint256 _rakeRateBps
    ) {
        if (_rakeRateBps > 1000) revert RakeTooHigh();
        owner = msg.sender;
        houseWallet = _houseWallet;
        settlerAddress = _settlerAddress;
        rakeRateBps = _rakeRateBps;
    }

    function createGame(bytes32 gameId, uint256 buyIn) external onlySettler {
        if (games[gameId].status != GameStatus.NonExistent) revert GameExists();
        games[gameId].buyIn = buyIn;
        games[gameId].status = GameStatus.Open;
        emit GameCreated(gameId, buyIn);
    }

    function deposit(bytes32 gameId) external payable {
        Game storage game = games[gameId];
        if (game.status != GameStatus.Open) revert GameNotOpen();
        if (msg.value != game.buyIn) revert WrongBuyIn();
        if (hasDeposited[gameId][msg.sender]) revert AlreadyDeposited();
        game.players.push(msg.sender);
        game.totalPot += msg.value;
        hasDeposited[gameId][msg.sender] = true;
        emit Deposited(gameId, msg.sender, msg.value);
    }

    function startGame(bytes32 gameId) external onlySettler {
        Game storage game = games[gameId];
        if (game.status != GameStatus.Open) revert GameNotOpen();
        game.status = GameStatus.InProgress;
        emit GameStarted(gameId);
    }

    function settle(
        bytes32 gameId,
        address[] calldata winners,
        uint256[] calldata amounts,
        bytes32 resultHash
    ) external onlySettler {
        Game storage game = games[gameId];
        if (game.status != GameStatus.InProgress) revert GameNotInProgress();
        if (winners.length != amounts.length) revert ArrayMismatch();

        uint256 rake = (game.totalPot * rakeRateBps) / 10000;
        uint256 distributed = 0;

        for (uint256 i = 0; i < winners.length; i++) {
            distributed += amounts[i];
            (bool success,) = payable(winners[i]).call{value: amounts[i]}("");
            if (!success) revert TransferFailed();
        }

        if (distributed + rake > game.totalPot) revert Overdistribution();

        (bool houseSuccess,) = payable(houseWallet).call{value: rake}("");
        if (!houseSuccess) revert TransferFailed();

        game.status = GameStatus.Settled;
        game.resultHash = resultHash;
        emit Settled(gameId, resultHash, rake);
    }

    function cancel(bytes32 gameId) external onlyOwner {
        Game storage game = games[gameId];
        if (game.status == GameStatus.Settled) revert AlreadySettled();
        if (game.status == GameStatus.NonExistent) revert GameNotFound();

        for (uint256 i = 0; i < game.players.length; i++) {
            (bool success,) = payable(game.players[i]).call{value: game.buyIn}("");
            if (!success) revert TransferFailed();
        }
        game.status = GameStatus.Cancelled;
        emit Cancelled(gameId);
    }

    function setRakeRate(uint256 newRateBps) external onlyOwner {
        if (newRateBps > 1000) revert RakeTooHigh();
        emit RakeUpdated(rakeRateBps, newRateBps);
        rakeRateBps = newRateBps;
    }

    function setSettlerAddress(address newSettler) external onlyOwner {
        emit SettlerUpdated(settlerAddress, newSettler);
        settlerAddress = newSettler;
    }

    function setHouseWallet(address newHouseWallet) external onlyOwner {
        houseWallet = newHouseWallet;
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function getGame(bytes32 gameId) external view returns (
        uint256 buyIn,
        uint256 totalPot,
        GameStatus status,
        bytes32 resultHash,
        address[] memory players
    ) {
        Game storage game = games[gameId];
        return (game.buyIn, game.totalPot, game.status, game.resultHash, game.players);
    }
}
