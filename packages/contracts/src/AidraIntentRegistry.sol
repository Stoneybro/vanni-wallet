// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {IAidraSmartWallet} from "./IAidraSmartWallet.sol";

/**
 * @title Aidra Intent Registry  
 * @author Zion Livingstone
 * @notice Central registry for managing automated payment intents across all Aidra wallets.
 * @dev Integrates with Chainlink Automation for decentralized intent execution.
 * @custom:security-contact stoneybrocrypto@gmail.com
 */
contract AidraIntentRegistry is AutomationCompatibleInterface, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    struct Intent {
        /// @notice The unique identifier for this intent
        bytes32 id;
        /// @notice The wallet that owns this intent
        address wallet;
        /// @notice The name of the intent
        string name;
        /// @notice The recipients of the intent
        address[] recipients;
        /// @notice The amounts per recipient per transaction
        uint256[] amounts;
        /// @notice The current transaction count
        uint256 transactionCount;
        /// @notice The final total transaction count
        uint256 totalTransactionCount;
        /// @notice The interval between transactions in seconds
        uint256 interval;
        /// @notice The start time of the transaction schedule
        uint256 transactionStartTime;
        /// @notice The end time of the transaction schedule
        uint256 transactionEndTime;
        /// @notice The latest transaction execution time
        uint256 latestTransactionTime;
        /// @notice Whether the intent is active
        bool active;
        /// @notice Whether to revert entire transaction on any failure (true) or skip failed transfers (false)
        bool revertOnFailure;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The list of registered wallets
    address[] public registeredWallets;
    /// @notice Whether the wallet is registered
    mapping(address => bool) public isWalletRegistered;

    /// @notice The intents per wallet
    mapping(address => mapping(bytes32 => Intent)) public walletIntents;
    /// @notice The active intent ids per wallet
    mapping(address => bytes32[]) public walletActiveIntentIds;
    /// @notice The amount of funds committed to intents per wallet
    mapping(address => uint256) public walletCommittedFunds;

    /// @notice A counter used to generate unique intent ids
    uint256 public intentCounter;

    /// @notice Maximum number of recipients allowed per intent
    uint256 public constant MAX_RECIPIENTS = 10;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The event emitted when an intent is created
    event IntentCreated(address indexed wallet, bytes32 indexed intentId);
    /// @notice The event emitted when an intent is executed
    event IntentExecuted(address indexed wallet, bytes32 indexed intentId);
    /// @notice The event emitted when an intent is cancelled
    event IntentCancelled(address indexed wallet, bytes32 indexed intentId, uint256 amountRefunded);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when no recipients are provided
    error AidraIntentRegistry__NoRecipients();
    /// @notice Thrown when a recipient address is zero
    error AidraIntentRegistry__InvalidRecipient();
    /// @notice Thrown when recipients and amounts arrays have different lengths
    error AidraIntentRegistry__ArrayLengthMismatch();
    /// @notice Thrown when number of recipients exceeds maximum allowed
    error AidraIntentRegistry__TooManyRecipients();
    /// @notice Thrown when duration is zero or negative
    error AidraIntentRegistry__InvalidDuration();
    /// @notice Thrown when interval is zero or negative
    error AidraIntentRegistry__InvalidInterval();
    /// @notice Thrown when an amount is zero or negative
    error AidraIntentRegistry__InvalidAmount();
    /// @notice Thrown when total transaction count is zero
    error AidraIntentRegistry__InvalidTotalTransactionCount();
    /// @notice Thrown when wallet has insufficient funds
    error AidraIntentRegistry__InsufficientFunds();
    /// @notice Thrown when trying to execute an inactive intent
    error AidraIntentRegistry__IntentNotActive();
    /// @notice Thrown when intent conditions are not met for execution
    error AidraIntentRegistry__IntentNotExecutable();
    /// @notice Thrown when the caller is not the wallet owner
    error AidraIntentRegistry__Unauthorized();

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new multi-recipient intent for the sender/wallet
     *
     * @param name The name of the intent
     * @param recipients The array of recipient addresses
     * @param amounts The array of amounts corresponding to each recipient
     * @param duration The total duration of the intent in seconds
     * @param interval The interval between transactions in seconds
     * @param transactionStartTime The start time of the transaction (0 for immediate start)
     * @param revertOnFailure Whether to revert entire transaction on any failure (true) or skip failed transfers (false)
     *
     * @return intentId The unique identifier for the created intent
     */
    function createIntent(
        string memory name,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 duration,
        uint256 interval,
        uint256 transactionStartTime,
        bool revertOnFailure
    ) external returns (bytes32) {
        address wallet = msg.sender;

        ///@notice When a wallet tries to create an intent for the first time, it is registered
        if (!isWalletRegistered[wallet]) {
            registeredWallets.push(wallet);
            isWalletRegistered[wallet] = true;
        }

        ///@notice Validate recipients and amounts arrays
        if (recipients.length == 0) revert AidraIntentRegistry__NoRecipients();
        if (recipients.length != amounts.length) revert AidraIntentRegistry__ArrayLengthMismatch();
        if (recipients.length > MAX_RECIPIENTS) revert AidraIntentRegistry__TooManyRecipients();

        ///@notice Validate timing parameters
        if (duration == 0) revert AidraIntentRegistry__InvalidDuration();
        if (interval == 0) revert AidraIntentRegistry__InvalidInterval();

        ///@notice Calculate total amount per execution and validate each recipient/amount
        uint256 totalAmountPerExecution = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert AidraIntentRegistry__InvalidRecipient();
            if (amounts[i] == 0) revert AidraIntentRegistry__InvalidAmount();
            totalAmountPerExecution += amounts[i];
        }

        ///@notice Calculate projected final transaction count
        uint256 totalTransactionCount = duration / interval;
        if (totalTransactionCount == 0) revert AidraIntentRegistry__InvalidTotalTransactionCount();

        ///@notice Calculate total commitment across all executions
        uint256 totalCommitment = totalAmountPerExecution * totalTransactionCount;

        ///@notice Check if the wallet has enough available funds to cover the intent
        uint256 availableBalance = IAidraSmartWallet(wallet).getAvailableBalance();
        if (availableBalance < totalCommitment) {
            revert AidraIntentRegistry__InsufficientFunds();
        }

        ///@notice Generate a unique intent id
        bytes32 intentId = keccak256(abi.encodePacked(wallet, recipients, amounts, block.timestamp, intentCounter++));

        ///@notice Store the intent
        walletIntents[wallet][intentId] = Intent({
            id: intentId,
            wallet: wallet,
            name: name,
            recipients: recipients,
            amounts: amounts,
            transactionCount: 0,
            totalTransactionCount: totalTransactionCount,
            interval: interval,
            ///@dev If transactionStartTime is 0, the current block timestamp is used
            transactionStartTime: transactionStartTime == 0 ? block.timestamp : transactionStartTime,
            transactionEndTime: transactionStartTime == 0 ? block.timestamp + duration : transactionStartTime + duration,
            latestTransactionTime: 0,
            active: true,
            revertOnFailure: revertOnFailure
        });

        ///@notice Update the wallet's committed funds
        walletCommittedFunds[wallet] += totalCommitment;
        IAidraSmartWallet(wallet).increaseCommitment(totalCommitment);
        
        ///@notice Add the intent id to the wallet's active intent ids
        walletActiveIntentIds[wallet].push(intentId);

        emit IntentCreated(wallet, intentId);
        return intentId;
    }

    /**
     * @notice Chainlink Automation calls this to check if any intents need execution
     *
     * @dev This is a view function, so it doesn't cost gas
     *
     * @return upkeepNeeded True if an intent needs execution
     * @return performData Encoded wallet address and intent id to execute
     */
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        ///@notice Check if there are any registered wallets
        if (registeredWallets.length == 0) return (false, bytes(""));

        ///@notice Iterate through registered wallets and their active intents
        for (uint256 i = 0; i < registeredWallets.length; i++) {
            address wallet = registeredWallets[i];
            bytes32[] memory activeIntents = walletActiveIntentIds[wallet];

            for (uint256 j = 0; j < activeIntents.length; j++) {
                bytes32 intentId = activeIntents[j];
                Intent storage intent = walletIntents[wallet][intentId];

                if (shouldExecuteIntent(intent)) {
                    return (true, abi.encode(wallet, intentId));
                }
            }
        }

        return (false, bytes(""));
    }

    /**
     * @notice Chainlink Automation calls this to execute an intent
     *
     * @param performData Encoded wallet address and intent id
     */
    function performUpkeep(bytes calldata performData) external override {
        (address wallet, bytes32 intentId) = abi.decode(performData, (address, bytes32));
        executeIntent(wallet, intentId);
    }

    /**
     * @notice Checks if an intent should be executed based on its conditions
     *
     * @param intent The intent to check
     *
     * @return bool True if the intent should be executed
     */
    function shouldExecuteIntent(Intent storage intent) internal view returns (bool) {
        ///@notice Check if the intent is active
        if (!intent.active) return false;

        ///@notice Check if the intent is within the start and end time
        if (block.timestamp < intent.transactionStartTime) return false;
        if (block.timestamp > intent.transactionEndTime) return false;

        ///@notice Check if the intent has reached the total transaction count
        if (intent.transactionCount >= intent.totalTransactionCount) return false;

        ///@notice Check if the interval has elapsed since last execution
        if (intent.latestTransactionTime != 0 && block.timestamp < intent.latestTransactionTime + intent.interval) {
            return false;
        }

        ///@notice Calculate total amount needed for this execution
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < intent.amounts.length; i++) {
            totalAmount += intent.amounts[i];
        }

        ///@notice Check if the wallet has enough funds to cover the execution
        if (totalAmount > intent.wallet.balance) return false;

        return true;
    }

    /**
     * @notice Executes an intent by transferring funds to all recipients
     *
     * @param wallet The wallet address that owns the intent
     * @param intentId The intent id to execute
     */
    function executeIntent(address wallet, bytes32 intentId) internal nonReentrant {
        Intent storage intent = walletIntents[wallet][intentId];

        ///@notice Verify the intent is active
        if (!intent.active) revert AidraIntentRegistry__IntentNotActive();

        ///@notice Verify the intent should be executed
        if (!shouldExecuteIntent(intent)) revert AidraIntentRegistry__IntentNotExecutable();

        ///@notice Store current transaction count before incrementing
        uint256 currentTransactionCount = intent.transactionCount;

        ///@notice Update intent state before external calls (checks-effects-interactions pattern)
        intent.transactionCount++;
        intent.latestTransactionTime = block.timestamp;

        ///@notice Deactivate the intent if it has reached the total transaction count
        if (intent.transactionCount >= intent.totalTransactionCount) {
            intent.active = false;
            _removeFromActiveIntents(wallet, intentId);
        }

        ///@notice Calculate total amount for this execution
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < intent.amounts.length; i++) {
            totalAmount += intent.amounts[i];
        }

        ///@notice Update the wallet's committed funds
        walletCommittedFunds[wallet] -= totalAmount;
        IAidraSmartWallet(wallet).decreaseCommitment(totalAmount);

        ///@notice Execute the batch intent transfer with intentId and transaction count
        IAidraSmartWallet(wallet).executeBatchIntentTransfer(
            intent.recipients,
            intent.amounts,
            intentId,
            currentTransactionCount,
            intent.revertOnFailure
        );

        emit IntentExecuted(wallet, intentId);
    }

    /**
     * @notice Removes an intent from the wallet's active intent ids array
     *
     * @param wallet The wallet address
     * @param intentId The intent id to remove
     */
    function _removeFromActiveIntents(address wallet, bytes32 intentId) internal {
        bytes32[] storage activeIntents = walletActiveIntentIds[wallet];
        for (uint256 i = 0; i < activeIntents.length; i++) {
            if (activeIntents[i] == intentId) {
                activeIntents[i] = activeIntents[activeIntents.length - 1];
                activeIntents.pop();
                break;
            }
        }
    }

    /**
     * @notice Allows wallet owner to cancel an active intent
     *
     * @param intentId The intent id to cancel
     */
    function cancelIntent(bytes32 intentId) external {
        address wallet = msg.sender;
        Intent storage intent = walletIntents[wallet][intentId];
        if (!intent.active) revert AidraIntentRegistry__IntentNotActive();

        ///@notice Calculate remaining amount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < intent.amounts.length; i++) {
            totalAmount += intent.amounts[i];
        }
        uint256 remainingTransactions = intent.totalTransactionCount - intent.transactionCount;
        uint256 amountRemaining = remainingTransactions * totalAmount;

        ///@notice Unlock funds when the intent is cancelled
        walletCommittedFunds[wallet] -= amountRemaining;
        IAidraSmartWallet(wallet).decreaseCommitment(amountRemaining);
        intent.active = false;
        _removeFromActiveIntents(wallet, intentId);

        ///@notice Emit event
        emit IntentCancelled(wallet, intentId, amountRemaining);
    }

    /**
     * @notice Gets an intent by wallet and intent id
     *
     * @param wallet The wallet address
     * @param intentId The intent id
     *
     * @return intent The intent struct
     */
    function getIntent(address wallet, bytes32 intentId) external view returns (Intent memory) {
        return walletIntents[wallet][intentId];
    }

    /**
     * @notice Gets all active intent ids for a wallet
     *
     * @param wallet The wallet address
     *
     * @return intentIds Array of active intent ids
     */
    function getActiveIntents(address wallet) external view returns (bytes32[] memory) {
        return walletActiveIntentIds[wallet];
    }

    /**
     * @notice Gets the number of registered wallets
     *
     * @return count The number of registered wallets
     */
    function getRegisteredWalletsCount() external view returns (uint256) {
        return registeredWallets.length;
    }
}
