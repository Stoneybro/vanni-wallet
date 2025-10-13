// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AidraIntentRegistry, IAidraSmartWallet} from "../src/AidraIntentRegistry.sol";

contract AidraIntentRegistryTest is Test {
    AidraIntentRegistry internal registry;
    MockSmartWallet internal wallet;

    address internal walletOwner = makeAddr("walletOwner");
    address internal keeper = makeAddr("keeper");
    address internal other = makeAddr("other");

    address internal recipient1 = makeAddr("recipient1");
    address internal recipient2 = makeAddr("recipient2");

    uint256 internal constant DURATION = 3 days;
    uint256 internal constant INTERVAL = 1 days;

    function setUp() public {
        registry = new AidraIntentRegistry();
        wallet = new MockSmartWallet(walletOwner);

        vm.deal(address(wallet), 100 ether);

        vm.prank(walletOwner);
        wallet.setRegistry(address(registry));
    }

    function test_CreateIntent_SetsStateAndRegistersWallet() public {
        bytes32 intentId = _createDefaultIntent(0);

        AidraIntentRegistry.Intent memory intent = registry.getIntent(address(wallet), intentId);

        assertEq(intent.wallet, address(wallet));
        assertEq(intent.totalTransactionCount, DURATION / INTERVAL);
        assertTrue(intent.active);

        bytes32[] memory activeIntents = registry.getActiveIntents(address(wallet));
        assertEq(activeIntents.length, 1);
        assertEq(activeIntents[0], intentId);

        uint256 totalAmountPerExecution = _totalAmount();
        uint256 expectedCommitment = totalAmountPerExecution * (DURATION / INTERVAL);
        assertEq(registry.walletCommittedFunds(address(wallet)), expectedCommitment);
    }

    function test_CreateIntent_RevertsWhenNoRecipients() public {
        address[] memory recipients;
        uint256[] memory amounts;

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__NoRecipients.selector);
        registry.createIntent("", recipients, amounts, DURATION, INTERVAL, 0);
    }

    function test_CreateIntent_RevertsWhenArrayLengthMismatch() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__ArrayLengthMismatch.selector);
        registry.createIntent("", recipients, amounts, DURATION, INTERVAL, 0);
    }

    function test_CreateIntent_RevertsWhenInvalidRecipient() public {
        address[] memory recipients = _recipients();
        recipients[1] = address(0);
        uint256[] memory amounts = _amounts();

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__InvalidRecipient.selector);
        registry.createIntent("", recipients, amounts, DURATION, INTERVAL, 0);
    }

    function test_CreateIntent_RevertsWhenInvalidAmount() public {
        address[] memory recipients = _recipients();
        uint256[] memory amounts = _amounts();
        amounts[1] = 0;

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__InvalidAmount.selector);
        registry.createIntent("", recipients, amounts, DURATION, INTERVAL, 0);
    }

    function test_CreateIntent_RevertsWhenDurationZero() public {
        address[] memory recipients = _recipients();
        uint256[] memory amounts = _amounts();

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__InvalidDuration.selector);
        registry.createIntent("", recipients, amounts, 0, INTERVAL, 0);
    }

    function test_CreateIntent_RevertsWhenIntervalZero() public {
        address[] memory recipients = _recipients();
        uint256[] memory amounts = _amounts();

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__InvalidInterval.selector);
        registry.createIntent("", recipients, amounts, DURATION, 0, 0);
    }

    function test_CreateIntent_RevertsWhenTotalTransactionCountZero() public {
        address[] memory recipients = _recipients();
        uint256[] memory amounts = _amounts();
        uint256 shortDuration = INTERVAL - 1;

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__InvalidTotalTransactionCount.selector);
        registry.createIntent("", recipients, amounts, shortDuration, INTERVAL, 0);
    }

    function test_CreateIntent_RevertsWhenInsufficientFunds() public {
        vm.deal(address(wallet), 0);
        address[] memory recipients = _recipients();
        uint256[] memory amounts = _amounts();

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__InsufficientFunds.selector);
        registry.createIntent("", recipients, amounts, DURATION, INTERVAL, 0);
    }

    function test_CreateIntent_DoesNotDuplicateWalletRegistration() public {
        _createDefaultIntent(0);
        _createDefaultIntent(0);

        assertEq(registry.getRegisteredWalletsCount(), 1);
    }

    function test_CancelIntent_UnlocksFundsAndRemovesIntent() public {
        bytes32 intentId = _createDefaultIntent(0);

        uint256 expectedCommitment = _totalAmount() * (DURATION / INTERVAL);
        assertEq(registry.walletCommittedFunds(address(wallet)), expectedCommitment);

        vm.prank(address(wallet));
        registry.cancelIntent(address(wallet), intentId);

        assertEq(registry.walletCommittedFunds(address(wallet)), 0);

        AidraIntentRegistry.Intent memory intent = registry.getIntent(address(wallet), intentId);
        assertFalse(intent.active);

        bytes32[] memory activeIntents = registry.getActiveIntents(address(wallet));
        assertEq(activeIntents.length, 0);
    }

    function test_CancelIntent_RevertsForUnauthorizedCaller() public {
        bytes32 intentId = _createDefaultIntent(0);

        vm.prank(other);
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__Unauthorized.selector);
        registry.cancelIntent(address(wallet), intentId);
    }

    function test_CancelIntent_RevertsWhenAlreadyInactive() public {
        bytes32 intentId = _createDefaultIntent(0);

        vm.prank(address(wallet));
        registry.cancelIntent(address(wallet), intentId);

        vm.prank(address(wallet));
        vm.expectRevert(AidraIntentRegistry.AidraIntentRegistry__IntentNotActive.selector);
        registry.cancelIntent(address(wallet), intentId);
    }

    function test_CheckUpkeep_ReturnsFalseWhenNoWallets() public {
        AidraIntentRegistry freshRegistry = new AidraIntentRegistry();
        (bool upkeepNeeded,) = freshRegistry.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeep_ReturnsFalseBeforeStart() public {
        _createDefaultIntent(2 days);

        (bool upkeepNeeded,) = registry.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeep_ReturnsFalseWhenIntentInactive() public {
        bytes32 intentId = _createDefaultIntent(0);

        vm.prank(address(wallet));
        registry.cancelIntent(address(wallet), intentId);

        (bool upkeepNeeded,) = registry.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeep_ReturnsFalseWhenIntervalNotElapsed() public {
        bytes32 intentId = _createDefaultIntent(0);

        vm.warp(block.timestamp + INTERVAL);
        _executeIntent(intentId);

        (bool upkeepNeeded,) = registry.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeep_ReturnsFalseWhenWalletBalanceLow() public {
        _createDefaultIntent(0);

        vm.deal(address(wallet), 0);
        vm.warp(block.timestamp + INTERVAL);

        (bool upkeepNeeded,) = registry.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeepAndPerformUpkeep_ExecutesIntentAndUpdatesState() public {
        bytes32 intentId = _createDefaultIntent(0);

        vm.warp(block.timestamp + INTERVAL);

        (bool upkeepNeeded, bytes memory performData) = registry.checkUpkeep("");
        assertTrue(upkeepNeeded);

        vm.prank(keeper);
        registry.performUpkeep(performData);

        // Funds transferred to recipients
        assertEq(recipient1.balance, _amounts()[0]);
        assertEq(recipient2.balance, _amounts()[1]);

        // Wallet committed funds reduced by one execution
        uint256 remainingCommitment = _totalAmount() * ((DURATION / INTERVAL) - 1);
        assertEq(registry.walletCommittedFunds(address(wallet)), remainingCommitment);

        AidraIntentRegistry.Intent memory intent = registry.getIntent(address(wallet), intentId);
        assertEq(intent.transactionCount, 1);
        assertTrue(intent.active);
        assertEq(wallet.batchCalls(), 1);
    }

    function test_PerformUpkeep_DeactivatesIntentAfterFinalExecution() public {
        bytes32 intentId = _createDefaultIntent(0);
        uint256 executions = DURATION / INTERVAL;

        for (uint256 i = 0; i < executions; i++) {
            vm.warp(block.timestamp + INTERVAL);
            (bool upkeepNeeded, bytes memory performData) = registry.checkUpkeep("");
            assertTrue(upkeepNeeded);
            registry.performUpkeep(performData);
        }

        AidraIntentRegistry.Intent memory intent = registry.getIntent(address(wallet), intentId);
        assertFalse(intent.active);
        assertEq(registry.walletCommittedFunds(address(wallet)), 0);

        bytes32[] memory activeIntents = registry.getActiveIntents(address(wallet));
        assertEq(activeIntents.length, 0);
        assertEq(wallet.batchCalls(), executions);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createDefaultIntent(uint256 startOffset) internal returns (bytes32 intentId) {
        address[] memory recipients = _recipients();
        uint256[] memory amounts = _amounts();

        uint256 start = startOffset == 0 ? block.timestamp : block.timestamp + startOffset;

        vm.prank(address(wallet));
        intentId = registry.createIntent("Payroll", recipients, amounts, DURATION, INTERVAL, start);
    }

    function _executeIntent(bytes32 intentId)
        internal
        returns (bool upkeepNeeded, bytes memory performData, AidraIntentRegistry.Intent memory intent)
    {
        (upkeepNeeded, performData) = registry.checkUpkeep("");
        if (upkeepNeeded) {
            registry.performUpkeep(performData);
        }
        intent = registry.getIntent(address(wallet), intentId);
    }

    function _totalAmount() internal pure returns (uint256) {
        uint256[] memory amounts = _amounts();
        return amounts[0] + amounts[1];
    }

    function _recipients() internal view returns (address[] memory recipients) {
        recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
    }

    function _amounts() internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
    }
}

contract MockSmartWallet is IAidraSmartWallet {
    address public immutable owner;
    address public registry;
    uint256 public batchCalls;

    error MockSmartWallet__NotOwner();
    error MockSmartWallet__RegistryNotSet();
    error MockSmartWallet__Unauthorized();
    error MockSmartWallet__InvalidBatchInput();
    error MockSmartWallet__TransferFailed(address recipient, uint256 amount);

    constructor(address owner_) {
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert MockSmartWallet__NotOwner();
        _;
    }

    function setRegistry(address registry_) external onlyOwner {
        registry = registry_;
    }

    function executeBatchIntentTransfer(address[] calldata recipients, uint256[] calldata amounts) external override {
        if (registry == address(0)) revert MockSmartWallet__RegistryNotSet();
        if (msg.sender != registry) revert MockSmartWallet__Unauthorized();
        if (recipients.length == 0 || recipients.length != amounts.length) revert MockSmartWallet__InvalidBatchInput();

        batchCalls++;

        for (uint256 i = 0; i < recipients.length; i++) {
            (bool success,) = payable(recipients[i]).call{value: amounts[i]}("");
            if (!success) revert MockSmartWallet__TransferFailed(recipients[i], amounts[i]);
        }
    }

    receive() external payable {}
}
