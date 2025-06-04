// SPDX-License-Identifier: MIT
/*
______         _  _      _                    _____                   _              
| ___ \       (_)| |    | |                  |  __ \                 | |             
| |_/ / _   _  _ | |  __| |  ___  _ __  ___  | |  \/  __ _  _ __   __| |  ___  _ __  
| ___ \| | | || || | / _` | / _ \| '__|/ __| | | __  / _` || '__| / _` | / _ \| '_ \ 
| |_/ /| |_| || || || (_| ||  __/| |   \__ \ | |_\ \| (_| || |   | (_| ||  __/| | | |
\____/  \__,_||_||_| \__,_| \___||_|   |___/  \____/ \__,_||_|    \__,_| \___||_| |_|                                                                                                                                  
*/                     
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Squabble
/// @notice A smart contract for managing multiplayer games with USDC stakes. Users can pay with any token using a system like Daimo Pay.
/// @dev Implements game creation, joining, and winner determination with USDC token integration
contract Squabble is Ownable, Pausable, ReentrancyGuard {
    // Custom Errors
    error ZeroAddress();                    // Thrown when address(0) is used
    error InvalidBetAmount();               // Thrown when stake amount is invalid
    error GameNotPending();                 // Thrown when game is not in PENDING state
    error GameAlreadyHasPlayer();           // Thrown when player already in game
    error GameNotPlaying();                 // Thrown when game is not in PLAYING state
    error TransferFailed();                 // Thrown when USDC transfer fails
    error Unauthorized();                   // Thrown when caller is not authorized
    error GameFull(uint256 id);             // Thrown when game has reached max players
    error InvalidGameRange();               // Thrown when game range is invalid
    error GameAlreadyExists(uint256 id);   // Thrown when game already exists
    error GameNotEnoughPlayers();          // Thrown when game has less than 2 players

    // Events
    event GameCreated(uint256 id, uint256 stakeAmount);    // Emitted when new game is created
    event GameJoined(uint256 id, address player);          // Emitted when player joins game
    event GameStarted(uint256 id);                         // Emitted when game starts
    event GameEnded(bool isDraw, uint256 id, address playerWinner);     // Emitted when game ends
    event WithdrawFromGame(uint256 id, address player);    // Emitted when player withdraws from game

    /// @notice Game status enum
    enum GameStatus {
        NOT_EXIST,   // Game doesn't exist
        PENDING,     // Game is waiting for players
        PLAYING,     // Game is in progress
        ENDED        // Game has ended
    }

    /// @notice Game struct containing all game information
    struct Game {
        address playerWinner;   // Address of the winner
        uint256 stakeAmount;    // Amount each player needs to stake
        uint256 totalStakeGame; // Total amount staked in the game
        uint256 gameId;         // Unique identifier for the game
        GameStatus status;      // Current status of the game
        uint256 playerCount;    // Number of players in the game
    }

    // State Variables
    address public usdcAddress;
    uint256[] public gameIds;
    
    // Constants
    uint256 public constant MAX_STAKE = 1000e6;    // Maximum stake amount (1000 USDC)
    uint256 public constant MAX_PLAYERS = 6;        // Maximum players per game
    
    // Mapping of game ID to Game struct
    mapping(uint256 => Game) public games;     
    // Mapping of player to game participation
    mapping(address => mapping(uint256 => bool)) public playerGames; 

    /// @notice Constructor to initialize the contract
    /// @param _usdcAddress The address of the USDC token contract
    /// @param _owner The address of the contract owner
    constructor(address _usdcAddress, address _owner) Ownable(_owner) {
        if (_usdcAddress == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        usdcAddress = _usdcAddress;
    }

    /// @notice Get a specific game by its ID
    /// @param id The ID of the game to retrieve
    /// @return Game The game details
    function getGame(uint256 id) public view returns (Game memory) {
        return games[id];
    }

    /// @notice Get a range of games by array indices (not game IDs)
    /// @param startIndex The starting index in the gameIds array
    /// @param endIndex The ending index in the gameIds array
    /// @return Game[] Array of games within the specified range
    function getGames(uint256 startIndex, uint256 endIndex) public view returns (Game[] memory) {
        if (startIndex > endIndex) revert InvalidGameRange();
        if (endIndex >= gameIds.length) revert InvalidGameRange();
        
        Game[] memory gamesArray = new Game[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            uint256 gameId = gameIds[i];
            gamesArray[i - startIndex] = games[gameId];
        }
        return gamesArray;
    }

    /// @notice Get all game IDs
    /// @return uint256[] Array of all game IDs
    function getAllGameIds() public view returns (uint256[] memory) {
        return gameIds;
    }

    /// @notice Get the total number of games
    /// @return uint256 Total number of games created
    function getTotalGames() public view returns (uint256) {
        return gameIds.length;
    }

    /// @notice Check if a game exists
    /// @param id The game ID to check
    /// @return bool True if game exists, false otherwise
    function gameExists(uint256 id) public view returns (bool) {
        return games[id].gameId != 0;
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Create a new game
    /// @param gameId The ID of the game to create
    /// @param stakeAmount The amount of USDC to bet
    function createGame(uint256 gameId, uint256 stakeAmount) public onlyOwner whenNotPaused {
        if (stakeAmount > MAX_STAKE) revert InvalidBetAmount();
        if (gameExists(gameId)) revert GameAlreadyExists(gameId);

        games[gameId] = Game({
            playerWinner: address(0),
            stakeAmount: stakeAmount,
            totalStakeGame: 0,
            gameId: gameId,
            status: GameStatus.PENDING,
            playerCount: 0
        });
        gameIds.push(gameId);

        emit GameCreated(gameId, stakeAmount);
    }

    /// @notice Join an existing game
    /// @param id The ID of the game to join
    /// @param player The address of the player joining
    function joinGame(uint256 id, address player) public whenNotPaused {
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (playerGames[player][id]) revert GameAlreadyHasPlayer();
        if (games[id].playerCount >= MAX_PLAYERS) revert GameFull(id);

        playerGames[player][id] = true;
        games[id].playerCount++;
        games[id].totalStakeGame += games[id].stakeAmount;

        if (games[id].stakeAmount > 0) {
            if (!IERC20(usdcAddress).transferFrom(msg.sender, address(this), games[id].stakeAmount)) revert TransferFailed();
        }

        emit GameJoined(id, player);
    }

    /// @notice Withdraw from a game
    /// @param id The ID of the game to withdraw from
    function withdrawFromGame(uint256 id) public nonReentrant {
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (!playerGames[msg.sender][id]) revert Unauthorized();

        // Remove player from mapping
        playerGames[msg.sender][id] = false;
        
        // Update counts
        games[id].playerCount--;
        games[id].totalStakeGame -= games[id].stakeAmount;

        if (games[id].stakeAmount > 0) {
            if (!IERC20(usdcAddress).transfer(msg.sender, games[id].stakeAmount)) revert TransferFailed();
        }

        emit WithdrawFromGame(id, msg.sender);
    }

    /// @notice Start a game
    /// @param id The ID of the game to start
    function startGame(uint256 id) onlyOwner public whenNotPaused {
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (games[id].playerCount < 2) revert GameNotEnoughPlayers();

        games[id].status = GameStatus.PLAYING;
        emit GameStarted(id);
    }

    /// @notice Set the winner of a game and distribute the prize
    /// @param id The ID of the game
    /// @param playerWinner The address of the winning player (address(0) for draw)
    /// @param players The array of players in the game to refund. Only used for draws.
    function setGameWinner(uint256 id, address playerWinner, address[] memory players) onlyOwner public nonReentrant {
        if (games[id].status != GameStatus.PLAYING) revert GameNotPlaying();
        
        games[id].status = GameStatus.ENDED;
        games[id].playerWinner = playerWinner;
        
        // Handle draw case (playerWinner is address(0))
        if (playerWinner == address(0)) {
            // For draws, refund players
            if (games[id].totalStakeGame > 0) {
                for (uint256 i = 0; i < players.length; i++) {
                    if (players[i] != address(0)) {
                        if (!IERC20(usdcAddress).transfer(players[i], games[id].stakeAmount)) revert TransferFailed();
                    }
                }
            }
            emit GameEnded(true, id, address(0));
            return;
        }
        
        // Handle winner case - transfer all stakes to winner
        if (games[id].totalStakeGame > 0) {
            if (!IERC20(usdcAddress).transfer(playerWinner, games[id].totalStakeGame)) revert TransferFailed();
        }
        emit GameEnded(false, id, playerWinner);
    }
}