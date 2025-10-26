// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DualDrip
 * @author livingstone zion
 * @notice Drips both ETH and an ERC-20 token (e.g. PYUSD) to users simultaneously.
 */
contract AidraFaucet is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ HARDCODED CONFIGURATION ============
    // PYUSD Token on ETH Sepolia
    IERC20 public constant TOKEN = IERC20(0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9);
    uint256 public constant ETH_AMOUNT = 0.01 ether; // 0.01 ETH per claim
    uint256 public constant TOKEN_AMOUNT = 25 * 10**6; // $25 PYUSD 
    // =================================================

    mapping(address => bool) public hasClaimed;

    // Track all users who have ever claimed
    address[] private claimers;
    mapping(address => bool) private isInClaimersArray;

    // Custom errors for gas efficiency
    error AlreadyClaimed();
    error InsufficientETHBalance();
    error InsufficientTokenBalance();
    error ETHTransferFailed();
    error InvalidAmount();
    error FaucetEmpty();
    error TooManyClaimers();

    // Events
    event Dripped(address indexed user, uint256 ethAmount, uint256 tokenAmount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed to, uint256 amount);
    event ClaimReset(address indexed user);
    event BatchClaimReset(address[] users);
    event AllClaimsReset();
    event FaucetFunded(address indexed funder, uint256 ethAmount, uint256 tokenAmount);
    event FaucetDrained();

    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Receive function to accept ETH deposits
     */
    receive() external payable {}

    /**
     * @notice Claim both ETH and tokens (one-time per address)
     * @dev Protected against reentrancy attacks
     */
    function claim() external nonReentrant {
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        
        // Check balances first
        if (address(this).balance < ETH_AMOUNT) revert InsufficientETHBalance();
        if (TOKEN.balanceOf(address(this)) < TOKEN_AMOUNT) revert InsufficientTokenBalance();
        
        // Mark as claimed (Checks-Effects-Interactions pattern)
        hasClaimed[msg.sender] = true;

        // Track this claimer
        if (!isInClaimersArray[msg.sender]) {
            claimers.push(msg.sender);
            isInClaimersArray[msg.sender] = true;
        }

        // Transfer ETH
        (bool sent,) = payable(msg.sender).call{value: ETH_AMOUNT}("");
        if (!sent) revert ETHTransferFailed();

        // Transfer PYUSD
        TOKEN.safeTransfer(msg.sender, TOKEN_AMOUNT);

        emit Dripped(msg.sender, ETH_AMOUNT, TOKEN_AMOUNT);
    }

    /**
     * @notice Reset claim status for a single user
     * @param user Address to reset
     */
    function resetClaim(address user) external onlyOwner {
        hasClaimed[user] = false;
        emit ClaimReset(user);
    }

    /**
     * @notice Reset claim status for multiple users (batch operation)
     * @param users Array of addresses to reset
     */
    function batchResetClaim(address[] calldata users) external onlyOwner {
        uint256 length = users.length;
        for (uint256 i = 0; i < length;) {
            hasClaimed[users[i]] = false;
            unchecked { ++i; }
        }
        emit BatchClaimReset(users);
    }

    /**
     * @notice Reset all claims for everyone who has ever claimed
     * @dev Useful for reusing the contract in a new campaign/project
     */
    function resetAllClaims() external onlyOwner {
        uint256 length = claimers.length;
        for (uint256 i = 0; i < length;) {
            hasClaimed[claimers[i]] = false;
            unchecked { ++i; }
        }
        emit AllClaimsReset();
    }

    /**
     * @notice Withdraw ETH from the contract
     * @param amount Amount of ETH to withdraw
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();
        
        (bool sent,) = payable(owner()).call{value: amount}("");
        if (!sent) revert ETHTransferFailed();
        
        emit ETHWithdrawn(owner(), amount);
    }

    /**
     * @notice Withdraw tokens from the contract
     * @param amount Amount of tokens to withdraw
     */
    function withdrawToken(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();
        
        TOKEN.safeTransfer(owner(), amount);
        
        emit TokenWithdrawn(owner(), amount);
    }

    /**
     * @notice Emergency withdraw all ETH
     */
    function emergencyWithdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InvalidAmount();
        
        (bool sent,) = payable(owner()).call{value: balance}("");
        if (!sent) revert ETHTransferFailed();
        
        emit ETHWithdrawn(owner(), balance);
    }

    /**
     * @notice Emergency withdraw all tokens
     */
    function emergencyWithdrawToken() external onlyOwner {
        uint256 balance = TOKEN.balanceOf(address(this));
        if (balance == 0) revert InvalidAmount();
        
        TOKEN.safeTransfer(owner(), balance);
        
        emit TokenWithdrawn(owner(), balance);
    }

    /**
     * @notice View function to check contract's ETH balance
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice View function to check contract's token balance
     */
    function getTokenBalance() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }

    /**
     * @notice Check if an address has claimed
     * @param user Address to check
     */
    function hasUserClaimed(address user) external view returns (bool) {
        return hasClaimed[user];
    }

    /**
     * @notice Get the total number of unique claimers
     */
    function getTotalClaimers() external view returns (uint256) {
        return claimers.length;
    }

    /**
     * @notice Get all claimers (paginated)
     * @param offset Starting index
     * @param limit Number of addresses to return
     */
    function getClaimers(uint256 offset, uint256 limit) external view returns (address[] memory) {
        uint256 length = claimers.length;
        if (offset >= length) {
            return new address[](0);
        }
        
        uint256 end = offset + limit;
        if (end > length) {
            end = length;
        }
        
        uint256 resultLength = end - offset;
        address[] memory result = new address[](resultLength);
        
        for (uint256 i = 0; i < resultLength;) {
            result[i] = claimers[offset + i];
            unchecked { ++i; }
        }
        return result;
    }

    /**
     * @notice Get comprehensive faucet statistics
     * @return ethBalance Current ETH balance
     * @return tokenBalance Current PYUSD balance
     * @return totalClaimers Total unique claimers
     * @return remainingClaims Maximum claims still possible
     * @return active Whether faucet can serve more claims
     */
    function getFaucetStats() external view returns (
        uint256 ethBalance,
        uint256 tokenBalance,
        uint256 totalClaimers,
        uint256 remainingClaims,
        bool active
    ) {
        ethBalance = address(this).balance;
        tokenBalance = TOKEN.balanceOf(address(this));
        totalClaimers = claimers.length;
        
        uint256 ethClaims = ethBalance / ETH_AMOUNT;
        uint256 tokenClaims = tokenBalance / TOKEN_AMOUNT;
        remainingClaims = ethClaims < tokenClaims ? ethClaims : tokenClaims;
        
        active = ethBalance >= ETH_AMOUNT && tokenBalance >= TOKEN_AMOUNT;
    }

    /**
     * @notice Fund the faucet with ETH and tokens
     * @param tokenAmount Amount of PYUSD to deposit
     * @dev ETH should be sent with the transaction
     */
    function fundFaucet(uint256 tokenAmount) external payable {
        if (tokenAmount > 0) {
            TOKEN.safeTransferFrom(msg.sender, address(this), tokenAmount);
        }
        
        emit FaucetFunded(msg.sender, msg.value, tokenAmount);
    }

    /**
     * @notice Drain all funds from faucet (emergency)
     */
    function drainFaucet() external onlyOwner {
        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = TOKEN.balanceOf(address(this));
        
        if (ethBalance > 0) {
            (bool sent,) = payable(owner()).call{value: ethBalance}("");
            if (!sent) revert ETHTransferFailed();
        }
        
        if (tokenBalance > 0) {
            TOKEN.safeTransfer(owner(), tokenBalance);
        }
        
        emit FaucetDrained();
    }
}