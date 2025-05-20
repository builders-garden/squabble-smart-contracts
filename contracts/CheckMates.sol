// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CheckMates is Ownable {
    // Custom Errors
    error ZeroAddress();
    error InvalidBetAmount();
    error GameDoesNotExist();
    error GameNotPending();
    error GameAlreadyHasPlayer();
    error PlayerJoiningOwnGame();
    error GameNotPlaying();
    error InvalidPlayerWinner();
    error TransferFailed();

    // Events
    event GameCreated(uint256 id, address player1, uint256 betAmount);
    event GameDeleted(uint256 id, address player1, uint256 betAmount);
    event GameJoined(uint256 id, address player2);
    event GameEnded(uint256 id, uint256 playerWinner);

    enum GameStatus {
        NOT_EXIST,
        PENDING,
        PLAYING,
        ENDED
    }

    struct Game {
        address player1;
        address player2;
        uint256 betAmount;
        uint256 gameId;
        GameStatus status;
        uint256 playerWinner;
    }

    // Game mapping
    mapping(uint256 => Game) public games;
    // Game ID counter
    uint256 public gameId;
    // USDC token address
    address public usdcAddress;

    /// @notice Constructor to initialize the contract with USDC token address and owner
    /// @param _usdcAddress The address of the USDC token contract
    /// @param _owner The address of the contract owner
    constructor(address _usdcAddress, address _owner) Ownable(_owner) {
        usdcAddress = _usdcAddress;
    }

    /// @notice Get a specific game by its ID
    /// @param id The ID of the game to retrieve
    /// @return Game The game details
    function getGame(uint256 id) public view returns (Game memory) {
        return games[id];
    }

    /// @notice Get a range of games
    /// @param start The starting game ID
    /// @param end The ending game ID
    /// @return Game[] Array of games within the specified range
    function getGames(uint256 start, uint256 end) public view returns (Game[] memory) {
        Game[] memory gamesArray = new Game[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            gamesArray[i - start] = games[i];
        }
        return gamesArray;
    }

    /// @notice Create a new game with specified player and bet amount
    /// @param player1 The address of the first player
    /// @param betAmount The amount of USDC to bet
    function createGame(address player1, uint256 betAmount) public {
        if (player1 == address(0)) revert ZeroAddress();
        if (betAmount == 0) revert InvalidBetAmount();

        gameId++;

        games[gameId] = Game({
            player1: player1,
            player2: address(0),
            betAmount: betAmount,
            gameId: gameId,
            status: GameStatus.PENDING,
            playerWinner: 0
        });
        if (!IERC20(usdcAddress).transferFrom(player1, address(this), betAmount)) revert TransferFailed();
        emit GameCreated(gameId, player1, betAmount);
    }

    /// @notice Delete a pending game and refund the bet amount
    /// @param id The ID of the game to delete
    function deleteGame(uint256 id) public {
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (msg.sender != games[id].player1) revert Unauthorized();

        games[id].status = GameStatus.ENDED;
        if (!IERC20(usdcAddress).transfer(games[id].player1, games[id].betAmount)) revert TransferFailed();
        emit GameDeleted(id, games[id].player1, games[id].betAmount);
    }

    /// @notice Join an existing game as the second player
    /// @param id The ID of the game to join
    /// @param player2 The address of the second player
    function joinGame(uint256 id, address player2) public {
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (games[id].player2 != address(0)) revert GameAlreadyHasPlayer();
        if (games[id].player1 == player2) revert PlayerJoiningOwnGame();

        games[id].player2 = player2;
        games[id].status = GameStatus.PLAYING;

        if (!IERC20(usdcAddress).transferFrom(player2, address(this), games[id].betAmount)) revert TransferFailed();

        emit GameJoined(id, player2);
    }

    /// @notice Set the winner of a game and distribute the prize
    /// @param id The ID of the game
    /// @param playerWinner The winner (1 for player1, 2 for player2, 0 for draw)
    function setGameWinner(uint256 id, uint256 playerWinner) onlyOwner public {
        if (games[id].status != GameStatus.PLAYING) revert GameNotPlaying();
        if (playerWinner > 2) revert InvalidPlayerWinner();

        games[id].status = GameStatus.ENDED;
        games[id].playerWinner = playerWinner;

        if (playerWinner == 1) {
            if (!IERC20(usdcAddress).transfer(games[id].player1, games[id].betAmount * 2)) revert TransferFailed();
        } else if (playerWinner == 2) {
            if (!IERC20(usdcAddress).transfer(games[id].player2, games[id].betAmount * 2)) revert TransferFailed();
        } else {
            if (!IERC20(usdcAddress).transfer(games[id].player1, games[id].betAmount)) revert TransferFailed();
            if (!IERC20(usdcAddress).transfer(games[id].player2, games[id].betAmount)) revert TransferFailed();
        }
        emit GameEnded(id, playerWinner);
    }
}