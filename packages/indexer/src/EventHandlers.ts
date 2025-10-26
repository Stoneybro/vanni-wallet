import { AidraSmartWalletFactory, AidraSmartWallet, AidraIntentRegistry } from "../generated";

// Helper type for transaction with hash field
type TransactionWithHash = { hash: string };

// ============================================
// FACTORY EVENTS - Wallet Deployment
// ============================================

AidraSmartWalletFactory.AccountCreated.contractRegister(({ event, context }) => {
  // Register new wallet for dynamic contract tracking
  context.addAidraSmartWallet(event.params.account);
});

AidraSmartWalletFactory.AccountCreated.handler(async ({ event, context }) => {
  const walletId = event.params.account.toLowerCase();
  const ownerId = event.params.owner.toLowerCase();
  const txHash = (event.transaction as TransactionWithHash).hash;
  
  context.Wallet.set({
    id: walletId,
    owner: ownerId,
    createdAt: BigInt(event.block.timestamp),
    createdAtBlock: BigInt(event.block.number),
    createdTxHash: txHash,
    totalTransactions: 0n,
    totalExecutions: 0n,
    totalIntentExecutions: 0n,
  });
  
  context.log.info(`✅ New wallet created: ${walletId}`);
});

// ============================================
// WALLET ACTION EVENTS
// ============================================

AidraSmartWallet.WalletAction.handler(async ({ event, context }) => {
  const walletId = event.srcAddress.toLowerCase();
  const txHash = (event.transaction as TransactionWithHash).hash;
  const transactionId = `${txHash}-${event.logIndex}`;
  
  context.Transaction.set({
    id: transactionId,
    wallet_id: walletId,
    initiator: event.params.initiator.toLowerCase(),
    target: event.params.target.toLowerCase(),
    value: event.params.value,
    selector: event.params.selector,
    actionType: event.params.actionType,
    success: event.params.success,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
    batchExecution_id: event.params.actionType === "BATCH" ? `${txHash}-batch` : undefined,
    token: undefined,
    recipient: undefined,
    amount: undefined,
    intent_id: undefined,
    transactionCount: undefined,
    data: undefined,
  });
  
  // Only update wallet stats for non-batch actions (ExecutedBatch will handle batch stats)
  if (event.params.actionType !== "BATCH") {
    const wallet = await context.Wallet.get(walletId);
    if (wallet) {
      context.Wallet.set({
        ...wallet,
        totalTransactions: wallet.totalTransactions + 1n,
        totalExecutions: wallet.totalExecutions + 1n,
      });
    }
  }
});

// ============================================
// EXECUTE EVENTS
// ============================================

AidraSmartWallet.Executed.handler(async ({ event, context }) => {
  const walletId = event.srcAddress.toLowerCase();
  const txHash = (event.transaction as TransactionWithHash).hash;
  const transactionId = `${txHash}-${event.logIndex}-executed`;
  
  const selector = event.params.data.length >= 10 
    ? event.params.data.slice(0, 10)
    : "0x00000000";
  
  context.Transaction.set({
    id: transactionId,
    wallet_id: walletId,
    initiator: walletId,
    target: event.params.target.toLowerCase(),
    value: event.params.value,
    selector: selector,
    actionType: "EXECUTE",
    success: true,
    data: event.params.data.length > 1000 ? event.params.data.slice(0, 1000) : event.params.data,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
    batchExecution_id: undefined,
    token: undefined,
    recipient: undefined,
    amount: undefined,
    intent_id: undefined,
    transactionCount: undefined,
  });
});

AidraSmartWallet.ExecutedBatch.handler(async ({ event, context }) => {
  const walletId = event.srcAddress.toLowerCase();
  const txHash = (event.transaction as TransactionWithHash).hash;
  const batchExecutionId = `${txHash}-batch`;
  
  // Create BatchExecution summary record
  context.BatchExecution.set({
    id: batchExecutionId,
    wallet_id: walletId,
    batchSize: event.params.batchSize,
    totalValue: event.params.totalValue,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
  });
  
  // Create main transaction record for the batch
  const transactionId = `${txHash}-${event.logIndex}-executed-batch`;
  context.Transaction.set({
    id: transactionId,
    wallet_id: walletId,
    initiator: walletId,
    target: walletId,
    value: event.params.totalValue,
    selector: "0x00000000",
    actionType: "EXECUTE_BATCH",
    success: true,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
    data: `Batch of ${event.params.batchSize} calls`,
    batchExecution_id: batchExecutionId,
    token: undefined,
    recipient: undefined,
    amount: event.params.totalValue,
    intent_id: undefined,
    transactionCount: undefined,
  });
  
  // Update wallet stats
  const wallet = await context.Wallet.get(walletId);
  if (wallet) {
    context.Wallet.set({
      ...wallet,
      totalTransactions: wallet.totalTransactions + 1n,
      totalExecutions: wallet.totalExecutions + 1n,
    });
  }
  
  context.log.info(`📦 Batch executed: ${event.params.batchSize} calls, total value: ${event.params.totalValue}`);
});

// ============================================
// COMMITMENT EVENTS
// ============================================

AidraSmartWallet.CommitmentIncreased.handler(async ({ event, context }) => {
  const walletId = event.srcAddress.toLowerCase();
  const tokenId = event.params.token.toLowerCase();
  const commitmentId = `${walletId}-${tokenId}`;
  const txHash = (event.transaction as TransactionWithHash).hash;
  
  context.Commitment.set({
    id: commitmentId,
    wallet_id: walletId,
    token: tokenId,
    amount: event.params.newTotal,
    lastUpdated: BigInt(event.block.timestamp),
    lastUpdatedBlock: BigInt(event.block.number),
  });
  
  const transactionId = `${txHash}-${event.logIndex}-commit-inc`;
  context.Transaction.set({
    id: transactionId,
    wallet_id: walletId,
    initiator: walletId,
    target: walletId,
    value: 0n,
    selector: "0x00000000",
    actionType: "COMMITMENT_INCREASE",
    success: true,
    token: tokenId,
    amount: event.params.amount,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
    recipient: undefined,
    intent_id: undefined,
    transactionCount: undefined,
    data: undefined,
    batchExecution_id: undefined,
  });
});

AidraSmartWallet.CommitmentDecreased.handler(async ({ event, context }) => {
  const walletId = event.srcAddress.toLowerCase();
  const tokenId = event.params.token.toLowerCase();
  const commitmentId = `${walletId}-${tokenId}`;
  const txHash = (event.transaction as TransactionWithHash).hash;
  
  context.Commitment.set({
    id: commitmentId,
    wallet_id: walletId,
    token: tokenId,
    amount: event.params.newTotal,
    lastUpdated: BigInt(event.block.timestamp),
    lastUpdatedBlock: BigInt(event.block.number),
  });
  
  const transactionId = `${txHash}-${event.logIndex}-commit-dec`;
  context.Transaction.set({
    id: transactionId,
    wallet_id: walletId,
    initiator: walletId,
    target: walletId,
    value: 0n,
    selector: "0x00000000",
    actionType: "COMMITMENT_DECREASE",
    success: true,
    token: tokenId,
    amount: event.params.amount,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
    recipient: undefined,
    intent_id: undefined,
    transactionCount: undefined,
    data: undefined,
    batchExecution_id: undefined,
  });
});

// ============================================
// INTENT EXECUTION EVENTS (from Wallet)
// ============================================

AidraSmartWallet.IntentBatchTransferExecuted.handler(async ({ event, context }) => {
  const walletId = event.srcAddress.toLowerCase();
  const intentId = event.params.intentId;
  const txHash = (event.transaction as TransactionWithHash).hash;
  const executionId = `${intentId}-${event.params.transactionCount}`;
  
  // Count successful vs failed transfers
  const totalTransfers = Number(event.params.recipientCount);
  const failedAmount = event.params.failedAmount;
  const successfulTransfers = failedAmount === 0n ? totalTransfers : 0; // Approximation - actual count from individual events
  const failedTransfers = totalTransfers - successfulTransfers;
  
  // Create IntentExecution record
  context.IntentExecution.set({
    id: executionId,
    intent_id: intentId,
    transactionCount: event.params.transactionCount,
    totalValue: event.params.totalValue,
    failedAmount: event.params.failedAmount,
    successfulTransfers: successfulTransfers,
    failedTransfers: failedTransfers,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
  });
  
  // Update Intent if it exists
  let intent = await context.Intent.get(intentId);
  if (intent) {
    context.Intent.set({
      ...intent,
      executionCount: intent.executionCount + 1n,
      totalValueTransferred: intent.totalValueTransferred + (event.params.totalValue - event.params.failedAmount),
      totalFailedAmount: intent.totalFailedAmount + event.params.failedAmount,
      lastExecutedAt: BigInt(event.block.timestamp),
      // Mark as completed if this was the last execution
      status: intent.executionCount + 1n >= intent.totalTransactionCount ? "COMPLETED" : intent.status,
    });
  }
  
  // Create Transaction record
  const transactionId = `${txHash}-${event.logIndex}-intent`;
  context.Transaction.set({
    id: transactionId,
    wallet_id: walletId,
    initiator: walletId,
    target: walletId,
    value: event.params.totalValue,
    selector: "0x00000000",
    actionType: "INTENT_TRANSFER",
    success: event.params.failedAmount === 0n,
    token: event.params.token.toLowerCase(),
    amount: event.params.totalValue,
    intent_id: intentId,
    transactionCount: event.params.transactionCount,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
    recipient: undefined,
    data: `Intent batch: ${event.params.recipientCount} recipients`,
    batchExecution_id: undefined,
  });
  
  // Update wallet stats
  const wallet = await context.Wallet.get(walletId);
  if (wallet) {
    context.Wallet.set({
      ...wallet,
      totalIntentExecutions: wallet.totalIntentExecutions + 1n,
    });
  }
});

AidraSmartWallet.IntentTransferSuccess.handler(async ({ event, context }) => {
  const transferId = `${event.params.intentId}-${event.params.transactionCount}-${event.params.recipient.toLowerCase()}`;
  const txHash = (event.transaction as TransactionWithHash).hash;
  const executionId = `${event.params.intentId}-${event.params.transactionCount}`;
  
  context.IntentTransfer.set({
    id: transferId,
    intent_id: event.params.intentId,
    execution_id: executionId,
    recipient: event.params.recipient.toLowerCase(),
    token: event.params.token.toLowerCase(),
    amount: event.params.amount,
    success: true,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
  });
});

AidraSmartWallet.TransferFailed.handler(async ({ event, context }) => {
  const transferId = `${event.params.intentId}-${event.params.transactionCount}-${event.params.recipient.toLowerCase()}-failed`;
  const txHash = (event.transaction as TransactionWithHash).hash;
  const executionId = `${event.params.intentId}-${event.params.transactionCount}`;
  
  context.IntentTransfer.set({
    id: transferId,
    intent_id: event.params.intentId,
    execution_id: executionId,
    recipient: event.params.recipient.toLowerCase(),
    token: event.params.token.toLowerCase(),
    amount: event.params.amount,
    success: false,
    timestamp: BigInt(event.block.timestamp),
    blockNumber: BigInt(event.block.number),
    transactionHash: txHash,
    logIndex: event.logIndex,
  });
});

// ============================================
// INTENT REGISTRY EVENTS
// ============================================

AidraIntentRegistry.IntentCreated.handler(async ({ event, context }) => {
  const walletId = event.params.wallet.toLowerCase();
  const intentId = event.params.intentId;
  const txHash = (event.transaction as TransactionWithHash).hash;
  
  // Now we get EVERYTHING from the event - no contract reads needed!
  context.Intent.set({
    id: intentId,
    wallet_id: walletId,
    token: event.params.token.toLowerCase(),
    name: event.params.name, // ✅ Now available!
    status: "ACTIVE",
    createdAt: BigInt(event.block.timestamp),
    createdTxHash: txHash,
    totalCommitment: event.params.totalCommitment,
    transactionStartTime: event.params.transactionStartTime,
    transactionEndTime: event.params.transactionEndTime,
    interval: event.params.interval, // ✅ Now available!
    duration: event.params.duration, // ✅ Now available!
    totalTransactionCount: event.params.totalTransactionCount, // ✅ Now available!
    executionCount: 0n,
    totalValueTransferred: 0n,
    totalFailedAmount: 0n,
    lastExecutedAt: undefined,
    cancelledAt: undefined,
    cancelledTxHash: undefined,
    amountRefunded: undefined,
    failedAmountRecovered: undefined,
    recipientCount: 0, // Still need contract read for this, but have all other data
  });
  
  context.log.info(`🎯 Intent created: ${event.params.name} (${intentId}) for wallet ${walletId}`);
});

AidraIntentRegistry.IntentExecuted.handler(async ({ event, context }) => {
  const intentId = event.params.intentId;
  
  // The wallet IntentBatchTransferExecuted event does most of the work
  // This is just for registry-level tracking and name logging
  context.log.info(`⚡ Intent executed: ${event.params.name} - transaction #${event.params.transactionCount}`);
});

AidraIntentRegistry.IntentCancelled.handler(async ({ event, context }) => {
  const intentId = event.params.intentId;
  const txHash = (event.transaction as TransactionWithHash).hash;
  
  let intent = await context.Intent.get(intentId);
  if (intent) {
    context.Intent.set({
      ...intent,
      status: "CANCELLED",
      cancelledAt: BigInt(event.block.timestamp),
      cancelledTxHash: txHash,
      amountRefunded: event.params.amountRefunded,
      failedAmountRecovered: event.params.failedAmountRecovered,
    });
    
    context.log.info(`🚫 Intent cancelled: ${event.params.name} (${intentId})`);
  }
});

AidraIntentRegistry.WalletRegistered.handler(async ({ event, context }) => {
  // Just logging - wallet should already exist from factory event
  context.log.info(`📝 Wallet registered with registry: ${event.params.wallet}`);
});