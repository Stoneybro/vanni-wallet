/**
 * @title Transaction Aggregator
 * @notice Aggregates and categorizes blockchain transactions using event logs
 * @dev This module exists because I needed a unified interface for querying
 * both standard transactions and ERC-4337 user operations together. Rather than querying UserOps
 * separately (which requires different endpoints and data structures), this aggregator uses an
 * event-driven approach to reconstruct all transaction activity from event logs emitted by the
 * wallet and registry contracts. This provides a consistent, comprehensive view of all wallet
 * activity regardless of whether transactions originated from EOAs, UserOps, or automated intents.
 * 
 * The aggregator processes three data sources:
 * 1. Normal transactions (external calls and deposits)
 * 2. Internal transactions (contract-to-contract value transfers)
 * 3. Event logs (wallet execution events, intent lifecycle events)
 * 
 * By correlating these sources, it categorizes transactions into meaningful types like deposits,
 * single/batch executions, automated payments, and intent management actions.
 */

import type { Address } from "viem";
import { keccak256, toHex } from "viem";
import { AidraRegistryAddress } from "../CA";
import type {
  BlockscoutTransaction,
  BlockscoutInternalTransaction,
  BlockscoutLog,
} from "./blockscoutClient";
import { formatEth } from "@/utils/format";

/**
 * @notice Categories for different transaction types in the Aidra wallet system
 */
export type TransactionCategory =
  | "deposit"
  | "execute_single"
  | "execute_batch"
  | "intent_recurring_batch"
  | "intent_recurring_single"
  | "intent_created"
  | "intent_cancelled"
  | "wallet_deployed"
  | "unknown";

/**
 * @notice Unified transaction representation combining multiple data sources
 */
export interface AggregatedTransaction {
  id: string;
  hash: string;
  timestamp: number;
  blockNumber: number;
  category: TransactionCategory;
  from: Address;
  to: Address;
  value: bigint;
  isBatch: boolean;
  recipients?: Array<{ address: Address; amount: bigint }>;
  batchCount?: number;
  intentId?: string;
  transactionCount?: number;
  isError: boolean;
  gasUsed?: bigint;
  description: string;
}

/**
 * @notice Keccak256 hashes of event signatures for transaction identification
 */
export const EVENT_SIGNATURES = {
  IntentExecuted:
    "0x3f85d0bd46ef72eb453028719ddfd06c553d29dd8e2c95646f6462c6651f6cde",
  IntentCreated:
    "0x4030e778e64a5396d5fece0a4b657fce4e6d203cca6bd210cd77c8c5b2a93192",
  IntentCancelled: keccak256(toHex("IntentCancelled(address,bytes32,uint256)")),
  Executed:
    "0xcaf938de11c367272220bfd1d2baa99ca46665e7bc4d85f00adb51b90fe1fa9f",
  ExecuteBatch:
    "0x89c83075daaddb676ea9b4a93d0b830549455558651dffb1d4e16ea182fb03ec",
  IntentBatchTransferExecuted:
    "0xe05a2ff729ca353aa0430e5da5bf97ee235afb11a6055abb3a3311c0daf6823f",
};

/**
 * @notice Groups internal transactions by their parent transaction hash
 * @param internalTxs Array of internal transactions to group
 * @returns Map of transaction hash to internal transactions array
 */
function groupInternalTxsByHash(
  internalTxs: BlockscoutInternalTransaction[]
): Map<string, BlockscoutInternalTransaction[]> {
  const grouped = new Map<string, BlockscoutInternalTransaction[]>();
  for (const tx of internalTxs) {
    const hash = tx.transactionHash.toLowerCase();
    if (!grouped.has(hash)) {
      grouped.set(hash, []);
    }
    grouped.get(hash)!.push(tx);
  }
  return grouped;
}

/**
 * @notice Groups event logs by their parent transaction hash
 * @param logs Array of event logs to group
 * @returns Map of transaction hash to logs array
 */
function groupLogsByHash(logs: BlockscoutLog[]): Map<string, BlockscoutLog[]> {
  const grouped = new Map<string, BlockscoutLog[]>();
  for (const log of logs) {
    const hash = log.transactionHash.toLowerCase();
    if (!grouped.has(hash)) {
      grouped.set(hash, []);
    }
    grouped.get(hash)!.push(log);
  }
  return grouped;
}



/**
 * @notice Builds transaction object for direct ETH deposits
 * @param tx Normal transaction data from Blockscout
 * @returns Aggregated transaction with deposit category
 */
function buildDepositTransaction(
  tx: BlockscoutTransaction
): AggregatedTransaction {
  const value = BigInt(tx.value);
  return {
    id: `deposit-${tx.hash}`,
    hash: tx.hash,
    timestamp: Number(tx.timeStamp),
    blockNumber: Number(tx.blockNumber),
    category: "deposit",
    from: tx.from as Address,
    to: tx.to as Address,
    value,
    isBatch: false,
    isError: tx.isError === "1",
    gasUsed: tx.gasUsed ? BigInt(tx.gasUsed) : undefined,
    description: `Received ${formatEth(value)} ETH`,
  };
}

/**
 * @notice Builds transaction object for wallet deployment
 * @param tx Normal transaction data from Blockscout
 * @returns Aggregated transaction with wallet_deployed category
 */
function buildWalletDeploymentTransaction(
  tx: BlockscoutTransaction
): AggregatedTransaction {
  return {
    id: `deployment-${tx.hash}`,
    hash: tx.hash,
    timestamp: Number(tx.timeStamp),
    blockNumber: Number(tx.blockNumber),
    category: "wallet_deployed",
    from: tx.from as Address,
    to: tx.contractAddress as Address,
    value: BigInt(tx.value || "0"),
    isBatch: false,
    isError: tx.isError === "1",
    gasUsed: tx.gasUsed ? BigInt(tx.gasUsed) : undefined,
    description: "Wallet deployed",
  };
}

/**
 * @notice Builds transaction object from Executed event (single execution)
 * @param wallet Wallet address as lowercase string
 * @param internals Internal transactions for this tx hash
 * @param logs Event logs for this tx hash
 * @returns Aggregated transaction or null if event not found
 */
function buildExecuteTransaction(
  wallet: string,
  internals: BlockscoutInternalTransaction[],
  logs: BlockscoutLog[]
): AggregatedTransaction | null {
  const executedEvent = logs.find(
    (log) => log.topics[0] === EVENT_SIGNATURES.Executed
  );

  if (!executedEvent) return null;

  const target = `0x${executedEvent.topics[1]?.slice(-40)}` as Address;

  const transfer = internals.find(
    (itx) =>
      itx.from?.toLowerCase() === wallet.toLowerCase() &&
      itx.to?.toLowerCase() === target.toLowerCase() &&
      itx.callType === "call" &&
      BigInt(itx.value || "0") > 0n
  );

  const value = transfer ? BigInt(transfer.value || "0") : 0n;

  return {
    id: `execute-${executedEvent.transactionHash}`,
    hash: executedEvent.transactionHash,
    timestamp: Number(executedEvent.timeStamp),
    blockNumber: Number(executedEvent.blockNumber),
    category: "execute_single",
    from: wallet as Address,
    to: target,
    value,
    isBatch: false,
    isError: false,
    description: `Sent ${formatEth(value)} ETH to ${target.slice(0, 6)}...${target.slice(-4)}`,
  };
}

/**
 * @notice Builds transaction object from ExecutedBatch event
 * @param wallet Wallet address as lowercase string
 * @param internals Internal transactions for this tx hash
 * @param logs Event logs for this tx hash
 * @returns Aggregated transaction or null if event not found
 */
function buildExecuteBatchTransaction(
  wallet: string,
  internals: BlockscoutInternalTransaction[],
  logs: BlockscoutLog[]
): AggregatedTransaction | null {
  const batchEvent = logs.find(
    (log) => log.topics[0] === EVENT_SIGNATURES.ExecuteBatch
  );

  if (!batchEvent) return null;

  const transfers = internals.filter(
    (itx) =>
      itx.from?.toLowerCase() === wallet.toLowerCase() &&
      itx.callType === "call" &&
      BigInt(itx.value || "0") > 0n
  );

  const totalValue = transfers.reduce(
    (sum, itx) => sum + BigInt(itx.value || "0"),
    0n
  );

  const recipients = transfers.map((itx) => ({
    address: itx.to as Address,
    amount: BigInt(itx.value || "0"),
  }));

  return {
    id: `batch-${batchEvent.transactionHash}`,
    hash: batchEvent.transactionHash,
    timestamp: Number(batchEvent.timeStamp),
    blockNumber: Number(batchEvent.blockNumber),
    category: "execute_batch",
    from: wallet as Address,
    to: transfers[0]?.to as Address,
    value: totalValue,
    isBatch: true,
    recipients,
    batchCount: transfers.length,
    isError: false,
    description: `Batch payment to ${transfers.length} recipients (${formatEth(totalValue)} ETH)`,
  };
}

/**
 * @notice Builds transaction object for automated intent executions (Chainlink)
 * @param wallet Wallet address as lowercase string
 * @param internals Internal transactions for this tx hash
 * @param logs Event logs for this tx hash
 * @returns Aggregated transaction or null if event not found
 */
function buildIntentExecutionTransaction(
  wallet: string,
  internals: BlockscoutInternalTransaction[],
  logs: BlockscoutLog[]
): AggregatedTransaction | null {
  const intentEvent = logs.find(
    (log) => log.topics[0] === EVENT_SIGNATURES.IntentExecuted
  );

  const transferEvent = logs.find(
    (log) => log.topics[0] === EVENT_SIGNATURES.IntentBatchTransferExecuted
  );

  if (!intentEvent && !transferEvent) return null;

  const eventToUse = transferEvent || intentEvent;
  const intentId = intentEvent?.topics[2];

  const transfers = internals.filter(
    (itx) =>
      itx.from?.toLowerCase() === wallet.toLowerCase() &&
      itx.callType === "call" &&
      BigInt(itx.value || "0") > 0n
  );

  if (transfers.length === 0) return null;

  const totalValue = transfers.reduce(
    (sum, itx) => sum + BigInt(itx.value || "0"),
    0n
  );

  const recipients = transfers.map((itx) => ({
    address: itx.to as Address,
    amount: BigInt(itx.value || "0"),
  }));

  const isBatch = transfers.length > 1;
  const category: TransactionCategory = isBatch
    ? "intent_recurring_batch"
    : "intent_recurring_single";

  const description = isBatch
    ? `Automated payment to ${transfers.length} recipient(s) (${formatEth(totalValue)} ETH)`
    : `Automated payment of ${formatEth(totalValue)} ETH`;

  return {
    id: `intent-exec-${eventToUse!.transactionHash}`,
    hash: eventToUse!.transactionHash,
    timestamp: Number(eventToUse!.timeStamp),
    blockNumber: Number(eventToUse!.blockNumber),
    category,
    from: wallet as Address,
    to: recipients[0]?.address,
    value: totalValue,
    intentId,
    isBatch,
    recipients,
    batchCount: transfers.length,
    isError: false,
    description,
  };
}

/**
 * @notice Builds transaction object for intent creation or cancellation
 * @param wallet Wallet address as lowercase string
 * @param logs Event logs for this tx hash
 * @returns Aggregated transaction or null if event not found
 */
function buildIntentSetupTransaction(
  wallet: string,
  logs: BlockscoutLog[]
): AggregatedTransaction | null {
  const createdEvent = logs.find(
    (log) => log.topics[0] === EVENT_SIGNATURES.IntentCreated
  );

  const cancelledEvent = logs.find(
    (log) => log.topics[0] === EVENT_SIGNATURES.IntentCancelled
  );

  const event = createdEvent || cancelledEvent;
  if (!event) return null;

  const isCreated = !!createdEvent;
  const intentId = event.topics[2];

  return {
    id: `intent-${isCreated ? "create" : "cancel"}-${event.transactionHash}`,
    hash: event.transactionHash,
    timestamp: Number(event.timeStamp),
    blockNumber: Number(event.blockNumber),
    category: isCreated ? "intent_created" : "intent_cancelled",
    from: wallet as Address,
    to: AidraRegistryAddress as Address,
    value: 0n,
    intentId,
    isBatch: false,
    isError: false,
    description: isCreated ? "Created new intent" : "Cancelled intent",
  };
}

/**
 * @notice Main aggregation function that processes all transaction types
 * @dev Processes transactions in order: deposits, deployments, then event-based transactions
 * @param walletAddress The wallet address to aggregate transactions for
 * @param normalTxs Normal transactions from Blockscout
 * @param internalTxs Internal transactions (contract calls)
 * @param logs Event logs from wallet and registry contracts
 * @returns Array of aggregated transactions sorted by timestamp (newest first)
 */
export function aggregateTransactions(
  walletAddress: Address,
  normalTxs: BlockscoutTransaction[],
  internalTxs: BlockscoutInternalTransaction[],
  logs: BlockscoutLog[]
): AggregatedTransaction[] {
  const wallet = walletAddress.toLowerCase();
  const results: AggregatedTransaction[] = [];
  const processedHashes = new Set<string>();

  const internalsByHash = groupInternalTxsByHash(internalTxs);
  const logsByHash = groupLogsByHash(logs);
    //console.log(logsByHash);
  for (const tx of normalTxs) {
    const to = tx.to?.toLowerCase();
    const hash = tx.hash.toLowerCase();

    if (to === wallet && !tx.contractAddress) {
      const agg = buildDepositTransaction(tx);
      results.push(agg);
      processedHashes.add(hash);
    }
  }

  for (const tx of normalTxs) {
    const hash = tx.hash.toLowerCase();
    if (processedHashes.has(hash)) continue;
    if (tx.contractAddress?.toLowerCase() === wallet && tx.to === "") {
      const agg = buildWalletDeploymentTransaction(tx);
      results.push(agg);
      processedHashes.add(hash);
    }
  }

  for (const log of logs) {
    const hash = log.transactionHash.toLowerCase();

    if (processedHashes.has(hash)) continue;

    const topic0 = log.topics[0];
    const internals = internalsByHash.get(hash) || [];
    const txLogs = logsByHash.get(hash) || [];

    let agg: AggregatedTransaction | null = null;

    if (topic0 === EVENT_SIGNATURES.Executed) {
      agg = buildExecuteTransaction(wallet, internals, txLogs);
    } else if (topic0 === EVENT_SIGNATURES.ExecuteBatch) {
      agg = buildExecuteBatchTransaction(wallet, internals, txLogs);
    } else if (
      topic0 === EVENT_SIGNATURES.IntentBatchTransferExecuted ||
      topic0 === EVENT_SIGNATURES.IntentExecuted
    ) {
      agg = buildIntentExecutionTransaction(wallet, internals, txLogs);
    } else if (
      topic0 === EVENT_SIGNATURES.IntentCreated ||
      topic0 === EVENT_SIGNATURES.IntentCancelled
    ) {
      agg = buildIntentSetupTransaction(wallet, txLogs);
    }

    if (agg) {
      results.push(agg);
      console.log(results);
      
      processedHashes.add(hash);
    }
  }

  return results.sort((a, b) => b.timestamp - a.timestamp);
}