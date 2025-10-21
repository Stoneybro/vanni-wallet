import { type Address } from "viem";
import { AidraRegistryAddress } from "../CA";
import { EVENT_SIGNATURES } from "./transactionAggregator";
/**
 * @title Blockscout API Client
 * @notice This module provides functions to interact with the Blockscout API for querying
 * blockchain data including transactions, internal transactions, logs, and events.
 * @dev This client generates the data used by the transaction aggregator
 */
const BLOCKSCOUT_API = "https://base-sepolia.blockscout.com/api";

/**
 * @notice Represents a standard blockchain transaction from Blockscout
 */
export interface BlockscoutTransaction {
  blockNumber: string;
  timeStamp: string;
  hash: string;
  nonce: string;
  blockHash: string;
  transactionIndex: string;
  from: string;
  to: string;
  value: string;
  gas: string;
  gasPrice: string;
  gasUsed?: string;
  isError: string;
  txreceipt_status?: string;
  input: string;
  contractAddress: string;
  cumulativeGasUsed: string;
  confirmations: string;
  methodId: string;
  functionName: string;
  type?: string;
  transactionHash?: string;
}

/**
 * @notice Represents an event log emitted by a smart contract
 */
export interface BlockscoutLog {
  address: string;
  blockNumber: string;
  timeStamp: string;
  data: string;
  topics: string[];
  transactionHash: string;
  transactionIndex: string;
  blockHash: string;
  logIndex: string;
  gasPrice?: string;
  gasUsed?: string;
}

/**
 * @notice Represents an internal transaction (contract-to-contract call)
 */
export interface BlockscoutInternalTransaction {
  blockNumber: string;
  callType: string;
  contractAddress: string;
  errCode: string | null;
  timeStamp: string;
  from: string;
  gas: string;
  gasUsed: string;
  index: string;
  input: string;
  isError: string;
  transactionHash: string;
  hash?: string;
  type: string;
  to: string;
  value: string;
  traceId: string;
  methodId?: string;
}

/**
 * @notice Fetches all normal transactions for a given address
 * @dev Uses Blockscout's account module txlist endpoint
 * @param params Query parameters including address, pagination, and block range
 * @param params.address The blockchain address to query
 * @param params.page Page number for pagination (default: 1)
 * @param params.limit Number of results per page (default: 50)
 * @param params.startblock Starting block number (optional)
 * @param params.endblock Ending block number (optional)
 * @param params.sort Sort order: "asc" or "desc" (default: "desc")
 * @returns Array of BlockscoutTransaction objects
 */
export async function getAccountTransactions(params: {
  address: Address;
  page?: number;
  limit?: number;
  startblock?: number;
  endblock?: number;
  sort?: "asc" | "desc";
}): Promise<BlockscoutTransaction[]> {
  const url = new URL(BLOCKSCOUT_API);
  url.searchParams.set("module", "account");
  url.searchParams.set("action", "txlist");
  url.searchParams.set("address", params.address);
  url.searchParams.set("page", String(params.page ?? 1));
  url.searchParams.set("offset", String(params.limit ?? 50));
  url.searchParams.set("sort", params.sort ?? "desc");

  if (params.startblock) {
    url.searchParams.set("startblock", String(params.startblock));
  }
  if (params.endblock) {
    url.searchParams.set("endblock", String(params.endblock));
  }

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error("Failed to fetch transactions");
  }

  const data = await res.json();
  return data.result ?? [];
}

/**
 * @notice Fetches internal transactions (contract calls) for a given address
 * @dev Uses Blockscout's account module txlistinternal endpoint
 * @param params Query parameters including address, pagination, and block range
 * @param params.address The blockchain address to query
 * @param params.page Page number for pagination (default: 1)
 * @param params.limit Number of results per page (default: 50)
 * @param params.startblock Starting block number (optional)
 * @param params.endblock Ending block number (optional)
 * @returns Array of BlockscoutInternalTransaction objects
 */
export async function getInternalTransactions(params: {
  address: Address;
  page?: number;
  limit?: number;
  startblock?: number;
  endblock?: number;
}): Promise<BlockscoutInternalTransaction[]> {
  const url = new URL(BLOCKSCOUT_API);
  url.searchParams.set("module", "account");
  url.searchParams.set("action", "txlistinternal");
  url.searchParams.set("address", params.address);
  url.searchParams.set("page", String(params.page ?? 1));
  url.searchParams.set("offset", String(params.limit ?? 50));
  url.searchParams.set("sort", "desc");

  if (params.startblock) {
    url.searchParams.set("startblock", String(params.startblock));
  }
  if (params.endblock) {
    url.searchParams.set("endblock", String(params.endblock));
  }

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error("Failed to fetch internal transactions");
  }

  const data = await res.json();
  return data.result ?? [];
}

/**
 * @notice Fetches detailed information for a specific transaction
 * @dev Uses Blockscout's transaction module gettxinfo endpoint
 * @param txHash The transaction hash to query
 * @returns Transaction details including logs, or null if not found
 */
export async function getTransaction(txHash: string): Promise<any> {
  const url = new URL(BLOCKSCOUT_API);
  url.searchParams.set("module", "transaction");
  url.searchParams.set("action", "gettxinfo");
  url.searchParams.set("txhash", txHash);

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error("Failed to fetch transaction");
  }

  const data = await res.json();
  return data.result ?? null;
}

/**
 * @notice Fetches event logs filtered by address and topics
 * @dev Uses Blockscout's logs module getLogs endpoint
 * @param address Contract address to filter logs
 * @param topic0 Event signature (topic0) filter (optional)
 * @param topic1 First indexed parameter (topic1) filter (optional)
 * @param topic2 Second indexed parameter (topic2) filter (optional)
 * @returns Array of BlockscoutLog objects
 */
export async function getLogs(
  address: string,
  topic0?: string,
  topic1?: string,
  topic2?: string,
  topic3?: string,
  topic0_1_opr?: "and" | "or",
  topic2_3_opr?: "and" | "or"
): Promise<BlockscoutLog[]> {
  const url = new URL(BLOCKSCOUT_API);
  url.searchParams.set("module", "logs");
  url.searchParams.set("action", "getLogs");
  url.searchParams.set("address", address);
  url.searchParams.set("fromBlock", "0");
  url.searchParams.set("toBlock", "latest");

  if (topic0) url.searchParams.set("topic0", topic0);
  if (topic1) url.searchParams.set("topic1", topic1);
  if (topic2) url.searchParams.set("topic2", topic2);
  if (topic3) url.searchParams.set("topic3", topic3);

  // CRITICAL: Add operators
  if (topic0_1_opr) {
    url.searchParams.set("topic0_1_opr", topic0_1_opr);
  }
  if (topic2_3_opr) {
    url.searchParams.set("topic2_3_opr", topic2_3_opr);
  }

  console.log("Full URL:", url.toString());

  const res = await fetch(url.toString());
  if (!res.ok) throw new Error(`Blockscout request failed (${res.status})`);

  const data = await res.json();
  if (data.status !== "1" || !Array.isArray(data.result)) return [];

  return data.result as BlockscoutLog[];
}

/**
 * @notice Pads an Ethereum address to 32 bytes (64 hex characters) for topic filtering
 * @dev Converts address to lowercase and left-pads with zeros
 * @param address The Ethereum address to pad
 * @returns Padded address suitable for use as a log topic
 */
function padAddress(address: string): string {
  return `0x${address.slice(2).toLowerCase().padStart(64, "0")}`;
}

/**
 * @notice Fetches and aggregates all relevant logs for the Aidra smart wallet transaction history
 * @dev Queries multiple event types from both the registry and wallet contracts:
 * - IntentCreated: When a new intent is registered
 * - IntentExecuted: When an intent is successfully executed
 * - IntentCancelled: When an intent is cancelled with refund
 * - IntentBatchTransferExecuted: When batch transfers are executed by chainlink
 * - Executed: When a single transaction is executed
 * - ExecutedBatch: When a batch of transactions is executed
 * @param walletAddress The Aidra smart wallet address to query
 * @returns Deduplicated and sorted array of all relevant logs
 */
export async function getCompiledLogs(
  walletAddress: Address
): Promise<BlockscoutLog[]> {
  const paddedAddress = padAddress(walletAddress);

  try {
    const [

      intentCreatedLogs, intentExecutedLogs, intentCancelledLogs,


      intentBatchTransferLogs,
      executedLogs,
      executeBatchLogs,



    ] = await Promise.all([
      getAidraIntentLogs(
        AidraRegistryAddress,
        EVENT_SIGNATURES.IntentCreated,
        paddedAddress
      ),
      getAidraIntentLogs(
        walletAddress,
        EVENT_SIGNATURES.IntentExecuted,
        paddedAddress
      ),
      getAidraIntentLogs(
        walletAddress,
        EVENT_SIGNATURES.IntentCancelled,
        paddedAddress
      ),
      getLogs(
        walletAddress,
        EVENT_SIGNATURES.IntentBatchTransferExecuted
      ),
      getLogs(
        walletAddress,
        EVENT_SIGNATURES.Executed
      ),
      getLogs(
        walletAddress,
        EVENT_SIGNATURES.ExecuteBatch
      ),
    ]);
    const result = [
      ...intentCreatedLogs, ...intentExecutedLogs, ...intentCancelledLogs,
      ...intentBatchTransferLogs,
      ...executedLogs,
      ...executeBatchLogs,
    ];


    const uniqueLogs = result.flat().filter(
      (log, index, self) =>
        index ===
        self.findIndex(
          (l) =>
            l.transactionHash === log.transactionHash &&
            l.logIndex === log.logIndex
        )
    );

    const sortedLogs = uniqueLogs.sort((a, b) => {
      const blockDiff = Number(b.blockNumber) - Number(a.blockNumber);
      if (blockDiff !== 0) return blockDiff;
      return Number(b.logIndex) - Number(a.logIndex);
    });

    return sortedLogs;
  } catch (error) {
    console.error("Error fetching compiled logs:", error);
    throw error;
  }
}



export async function getAidraIntentLogs(address: string, topic0: string, topic1: string) {
  const params = new URLSearchParams({
    module: "logs",
    action: "getLogs",
    fromBlock: "0",               // you can set this to a specific block number if you want
    toBlock: "latest",
    address,
    topic0,
    topic1,
    topic0_1_opr: "and",
  });

  const url = `${BLOCKSCOUT_API}?${params.toString()}`;

  try {
    const res = await fetch(url);
    const data = await res.json();

    if (data.status !== "1" || !data.result) {
      console.warn("No logs found or API returned an error:", data.message);
      return [];
    }

    // Optionally format logs for easier consumption
    return data.result
  } catch (error) {
    console.error("Error fetching logs:", error);
    return [];
  }
}
