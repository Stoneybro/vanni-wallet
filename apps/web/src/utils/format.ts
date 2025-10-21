import { formatEther } from "viem";

/**
 * Formats a BigInt ETH value to a human-readable string with 4 decimal places.
 * Standardizes ETH display across the app for balances and transactions.
 */
export function formatNumber(number: bigint): string {
  return parseFloat(Number(formatEther(number)).toFixed(4)).toString();
}

/**
 * Shortens a blockchain address for display purposes.
 * Defaults to 6 chars start / 4 chars end, improving UI readability.
 */
export function truncateAddress(address: string, start = 6, end = 6): string {
  if (!address) return "";
  return `${address.slice(0, start)}...${address.slice(-end)}`;
}

/**
 * Formats a UNIX timestamp (seconds) to a localized date string.
 * Provides consistent human-readable date display in the UI.
 */
export function formatDate(date: bigint): string {
  return new Date(Number(date) * 1000).toLocaleString("en-US", {
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

export function formatTimestamp(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);
  
  if (diffMins < 1) return "Just now";
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * @notice Formats wei value to human-readable ETH string
 * @param wei Wei amount as bigint
 * @returns Formatted ETH string with appropriate precision
 */
export function formatEth(wei: bigint): string {
  const eth = Number(wei) / 1e18;
  if (eth === 0) return "0";
  if (eth < 0.000001) return eth.toExponential(2);
  if (eth < 1) return eth.toFixed(6).replace(/\.?0+$/, "");
  return eth.toFixed(4).replace(/\.?0+$/, "");
}