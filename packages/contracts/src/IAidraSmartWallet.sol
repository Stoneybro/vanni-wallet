// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @notice Interface for AidraSmartWallet to execute batch transfers
 * @dev Used by AidraIntentRegistry to interact with AidraSmartWallet contracts
 */
interface IAidraSmartWallet {
    /**
     * @notice Executes a batch transfer to multiple recipients
     *
     * @param recipients The array of recipient addresses
     * @param amounts The array of amounts to send to each recipient
     * @param intentId The unique identifier for the intent being executed
     * @param transactionCount The current transaction number within the intent
     * @param revertOnFailure Whether to revert entire transaction on any failure (true) or skip failed transfers (false)
     */
    function executeBatchIntentTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes32 intentId,
        uint256 transactionCount,
        bool revertOnFailure
    ) external;

    /**
     * @notice Decreases the committed funds after intent execution/cancellation
     *
     * @param amount The amount to subtract from committed funds
     */
    function decreaseCommitment(uint256 amount) external;

    /**
     * @notice Increases the committed funds for intents
     *
     * @param amount The amount to add to committed funds
     */
    function increaseCommitment(uint256 amount) external;

    /**
     * @notice Returns the available (uncommitted) balance
     *
     * @return The available balance in wei
     */
    function getAvailableBalance() external view returns (uint256);
}
