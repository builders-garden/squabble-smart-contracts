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

/// @title Squabble
/// @notice A smart contract for managing multiplayer games with USDC stakes
/// @dev Implements game creation, joining, and winner determination with USDC token integration
contract Squabble is Ownable, Pausable {
    // Custom Errors
    error ZeroAddress();                    // Thrown when address(0) is used
    error InvalidBetAmount();               // Thrown when stake amount is invalid
    error GameNotPending();                 // Thrown when game is not in PENDING state
    error GameAlreadyHasPlayer();           // Thrown when player already in game
    error GameNotPlaying();                 // Thrown when game is not in PLAYING state
    error TransferFailed();                 // Thrown when USDC transfer fails
    error Unauthorized();                   // Thrown when caller is not authorized
    error GameFull(uint256 id);             // Thrown when game has reached max players
    error InvalidPlayerIndex();             // Thrown when player index is invalid
    error InvalidGameRange();               // Thrown when game range is invalid
    error GameDoesNotExist(uint256 id);     // Thrown when game doesn't exist
    error GameAlreadyExists(uint256 id);   // Thrown when game already exists
    error GameNotEnoughPlayers();          // Thrown when game has less than 2 players

    // Events
    event GameCreated(uint256 id, address creator, uint256 stakeAmount);    // Emitted when new game is created
    event GameDeleted(uint256 id, address creator, uint256 stakeAmount);    // Emitted when game is deleted
    event GameJoined(uint256 id, address player2);                          // Emitted when player joins game
    event GameStarted(uint256 id);                                          // Emitted when game starts
    event GameEnded(uint256 id, address playerWinner);                      // Emitted when game ends
    event WithdrawFromGame(uint256 id, address player);                     // Emitted when player withdraws from game

    /// @notice Game status enum
    enum GameStatus {
        NOT_EXIST,   // Game doesn't exist
        PENDING,     // Game is waiting for players
        PLAYING,     // Game is in progress
        ENDED        // Game has ended
    }

    /// @notice Game struct containing all game information
    struct Game {
        address creator;        // Address of game creator
        address playerWinner;   // Address of the winner
        address[] players;      // Array of player addresses
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
    
    /// @notice Modifier to restrict access to game creator or admin
    /// @param id The game ID to check
    modifier onlyCreatorOrAdmin(uint256 id) {
        if (msg.sender != games[id].creator && msg.sender != owner()) revert Unauthorized();
        _;
    }

    /// @notice Constructor to initialize the contract
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
        if (start > end) revert InvalidGameRange();
        if (end > gameIds.length) revert InvalidGameRange();
        
        Game[] memory gamesArray = new Game[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            if (!gameExists(i)) revert GameDoesNotExist(i);
            gamesArray[i - start] = games[i];
        }
        return gamesArray;
    }

    /// @notice Check if a game exists
    /// @param id The game ID to check
    /// @return bool True if game exists, false otherwise
    function gameExists(uint256 id) public view returns (bool) {
        return games[id].creator != address(0);
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
    /// @param creator The address of the creator
    /// @param stakeAmount The amount of USDC to bet
    function createGame(uint256 gameId, address creator, uint256 stakeAmount) public onlyOwner whenNotPaused {
        if (creator == address(0)) revert ZeroAddress();
        if (stakeAmount > MAX_STAKE) revert InvalidBetAmount();
        if (gameExists(gameId)) revert GameAlreadyExists(gameId);

        games[gameId] = Game({
            creator: creator,
            playerWinner: address(0),
            players: new address[](MAX_PLAYERS),
            stakeAmount: stakeAmount,
            totalStakeGame: 0,
            gameId: gameId,
            status: GameStatus.PENDING,
            playerCount: 0
        });
        gameIds.push(gameId);

        emit GameCreated(gameId, creator, stakeAmount);
    }

    /// @notice Join an existing game
    /// @param id The ID of the game to join
    /// @param player The address of the player joining
    function joinGame(uint256 id, address player) public whenNotPaused {
        if (!gameExists(id)) revert GameDoesNotExist(id);
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (playerGames[player][id]) revert GameAlreadyHasPlayer();
        if (games[id].playerCount >= MAX_PLAYERS) revert GameFull(id);

        playerGames[player][id] = true;
        games[id].players[games[id].playerCount] = player;
        games[id].playerCount++;
        games[id].totalStakeGame += games[id].stakeAmount;

        if (!IERC20(usdcAddress).transferFrom(msg.sender, address(this), games[id].stakeAmount)) revert TransferFailed();

        emit GameJoined(id, player);
    }

    /// @notice Withdraw from a game
    /// @param id The ID of the game to withdraw from
    function withdrawFromGame(uint256 id) public {
        if (!gameExists(id)) revert GameDoesNotExist(id);
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (!playerGames[msg.sender][id]) revert Unauthorized();

        // Find player's index in the array
        uint256 playerIndex = 0;
        bool found = false;
        for (uint256 i = 0; i < games[id].playerCount; i++) {
            if (games[id].players[i] == msg.sender) {
                playerIndex = i;
                found = true;
                break;
            }
        }
        
        if (!found) revert Unauthorized();

        // Remove player from mapping
        playerGames[msg.sender][id] = false;
        
        // Remove player from array by shifting elements left
        for (uint256 i = playerIndex; i < games[id].playerCount - 1; i++) {
            games[id].players[i] = games[id].players[i + 1];
        }
        
        // Clear the last slot and update counts
        games[id].players[games[id].playerCount - 1] = address(0);
        games[id].playerCount--;
        games[id].totalStakeGame -= games[id].stakeAmount;

        if (!IERC20(usdcAddress).transfer(msg.sender, games[id].stakeAmount)) revert TransferFailed();

        emit WithdrawFromGame(id, msg.sender);
    }

    /// @notice Start a game
    /// @param id The ID of the game to start
    function startGame(uint256 id) onlyCreatorOrAdmin(id) public whenNotPaused {
        if (!gameExists(id)) revert GameDoesNotExist(id);
        if (games[id].status != GameStatus.PENDING) revert GameNotPending();
        if (games[id].playerCount < 2) revert GameNotEnoughPlayers();

        games[id].status = GameStatus.PLAYING;
        emit GameStarted(id);
    }

    /// @notice Set the winner of a game and distribute the prize
    /// @param id The ID of the game
    /// @param playerWinner The winner (0 for first player, 1 for second player, etc., 10 for draw)
    function setGameWinner(uint256 id, uint256 playerWinner) onlyOwner public {
        if (!gameExists(id)) revert GameDoesNotExist(id);
        if (games[id].status != GameStatus.PLAYING) revert GameNotPlaying();
        
        // Handle draw case
        if (playerWinner == 10) {
            games[id].status = GameStatus.ENDED;
            address playerDrawAddress = address(0);
            // Refund all players their stake
            for (uint256 i = 0; i < games[id].playerCount; i++) {
                if (!IERC20(usdcAddress).transfer(games[id].players[i], games[id].stakeAmount)) revert TransferFailed();
            }
            emit GameEnded(id, playerDrawAddress);
            return;
        }
        
        // Handle winner case
        if (playerWinner >= games[id].playerCount) revert InvalidPlayerIndex();
        
        games[id].status = GameStatus.ENDED;
        address playerWinnerAddress = games[id].players[playerWinner];
        games[id].playerWinner = playerWinnerAddress;
        
        if (!IERC20(usdcAddress).transfer(playerWinnerAddress, games[id].totalStakeGame)) revert TransferFailed();
        emit GameEnded(id, playerWinnerAddress);
    }
}