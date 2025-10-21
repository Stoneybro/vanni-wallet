import { useQuery, useInfiniteQuery } from "@tanstack/react-query";
import { type Address } from "viem";
import {
  getAccountTransactions,
  getAidraIntentLogs,
  getCompiledLogs,
  getInternalTransactions,
  getLogs,
  getTransaction,
} from "@/lib/blockscout/blockscoutClient";
import {
  aggregateTransactions,
  EVENT_SIGNATURES,
  type AggregatedTransaction,
} from "./transactionAggregator";
import { useMemo } from "react";
import { AidraRegistryAddress } from "../CA";
/**
 * @title Blockscout React Query Hooks
 * @notice Custom hooks for fetching and managing blockscout data using React Query
 * @dev Provides hooks for transactions, internal transactions, logs, and aggregated data
 */


/**
 * @notice Fetches paginated transaction history for an address
 * @param params Query parameters
 * @param params.address The address to fetch transactions for
 * @param params.enabled Whether the query should run (default: true)
 * @returns Infinite query result with transaction pages
 */
export function useTransactionHistory(params: {
  address?: Address;
  enabled?: boolean;
}) {
  return useInfiniteQuery({
    queryKey: ["transactions", params.address],
    queryFn: ({ pageParam = 1 }) =>
      getAccountTransactions({
        address: params.address!,
        page: pageParam,
        limit: 20,
      }),
    enabled: (params.enabled ?? true) && !!params.address,
    getNextPageParam: (lastPage) =>
      lastPage.length === 20 ? lastPage.length / 20 + 1 : undefined,
    initialPageParam: 1,
    staleTime: 30_000,
  });
}

/**
 * @notice Fetches paginated internal transactions (contract calls) for an address
 * @param params Query parameters
 * @param params.address The address to fetch internal transactions for
 * @param params.enabled Whether the query should run (default: true)
 * @returns Infinite query result with internal transaction pages
 */
export function useInternalTransactions(params: {
  address?: Address;
  enabled?: boolean;
}) {
  return useInfiniteQuery({
    queryKey: ["internal-transactions", params.address],
    queryFn: ({ pageParam = 1 }) =>
      getInternalTransactions({
        address: params.address!,
        page: pageParam,
        limit: 20,
      }),
    enabled: (params.enabled ?? true) && !!params.address,
    getNextPageParam: (lastPage, allPages) =>
      lastPage.length === 20 ? allPages.length + 1 : undefined,
    initialPageParam: 1,
    staleTime: 30_000,
  });
}

/**
 * @notice Fetches details for a single transaction by hash
 * @param params Query parameters
 * @param params.hash The transaction hash to fetch
 * @param params.enabled Whether the query should run (default: true)
 * @returns Query result with transaction details
 */
export function useTransaction(params: {
  hash?: string;
  enabled?: boolean;
}) {
  return useQuery({
    queryKey: ["tx", params.hash],
    queryFn: () => getTransaction(params.hash!),
    enabled: (params.enabled ?? true) && !!params.hash,
    staleTime: Infinity,
  });
}

/**
 * @notice Fetches and compiles all relevant event logs for an Aidra wallet
 * @dev Auto-refetches every 30 seconds to keep data fresh
 * @param params Query parameters
 * @param params.accountAddress The wallet address to fetch logs for
 * @param params.enabled Whether the query should run (default: true)
 * @returns Query result with compiled logs array
 */
export function useCompiledLogs(params: {
  accountAddress?: Address;
  enabled?: boolean;
}) {
  return useQuery({
    queryKey: ["compiled-logs", params.accountAddress],
    queryFn: async () => {
      if (!params.accountAddress) return [];
      return getCompiledLogs(params.accountAddress);
    },
    enabled: (params.enabled ?? true) && !!params.accountAddress,
    staleTime: 30_000,
    refetchInterval: 30_000,
  });
}
function padAddress(address: string): string {
  return `0x${address.slice(2).toLowerCase().padStart(64, "0")}`;
}
function getIntentLogs(params: {
  accountAddress?: Address;
  enabled?: boolean
}) {
  return useQuery({
    queryKey: ["intent-logs", params.accountAddress],
    queryFn: async () => {
      if (!params.accountAddress) return [];
      return getAidraIntentLogs(AidraRegistryAddress, EVENT_SIGNATURES.IntentCreated, padAddress(params.accountAddress));
    },
    enabled: (params.enabled ?? true) && !!params.accountAddress,
    staleTime: 30_000,
    refetchInterval: 30_000,
  });
}

/**
 * @notice Aggregates and decodes all transaction types using the transactor aggregator into a unified data structure
 * @dev Combines normal transactions, internal transactions, and event logs
 * @param params Query parameters
 * @param params.address The wallet address to aggregate transactions for
 * @param params.enabled Whether the query should run (default: true)
 * @returns Aggregated transaction data with loading states and pagination controls
 */
export function useAggregatedTransactions(params: {
  address?: Address;
  enabled?: boolean;
}) {
  const txHistory = useTransactionHistory({
    address: params.address,
    enabled: params.enabled,
  });

  const internalTxs = useInternalTransactions({
    address: params.address,
    enabled: params.enabled,
  });

  const logs = useCompiledLogs({
    accountAddress: params.address,
    enabled: params.enabled,
  });

  const intentLogs = getIntentLogs({
    accountAddress: params.address,
    enabled: params.enabled,
  });



  const aggregatedTxs = useMemo<AggregatedTransaction[]>(() => {
    if (!params.address) return [];

    const normalTxs = txHistory.data?.pages.flat() || [];
    const internalTxsList = internalTxs.data?.pages.flat() || [];
    const logsList = logs.data || [];
    const intentLogsList = intentLogs.data || [];
    const totalLogList=[...intentLogsList,...logsList]
    


    return aggregateTransactions(
      params.address!,
      normalTxs,
      internalTxsList,
      totalLogList
    );
  }, [txHistory.data, internalTxs.data, logs.data, params.address]);

  return {
    transactions: aggregatedTxs,
    isLoading: txHistory.isLoading || internalTxs.isLoading || logs.isLoading,
    isError: txHistory.isError || internalTxs.isError || logs.isError,
    error: txHistory.error || internalTxs.error || logs.error,
    fetchNextPage: () => {
      txHistory.fetchNextPage();
      internalTxs.fetchNextPage();
    },
    hasNextPage: txHistory.hasNextPage || internalTxs.hasNextPage,
    isFetchingNextPage:
      txHistory.isFetchingNextPage || internalTxs.isFetchingNextPage,
  };
}