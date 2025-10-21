import { readContract } from "@/lib/server";
import { getBalance } from "@/lib/server";
import AidraSmartWalletABI from "@aidra/contracts/AidraSmartWallet";
import type { Abi } from "viem";
import { formatNumber } from "./format";


/**
 * Fetches wallet balances :
 * - availableBalance: spendable funds
 * - committedFunds: locked rewards
 * - totalBalance: total ETH in smart account
 */

export async function fetchWalletBalance(smartAccountAddress: `0x${string}`) {
  const [availableBalance, committedFunds] = await Promise.all([
    readContract({
      address: smartAccountAddress,
      abi:  AidraSmartWalletABI as Abi,
      functionName: "getAvailableBalance",
    }),
    readContract({
      address: smartAccountAddress,
      abi:  AidraSmartWalletABI as Abi,
      functionName: "s_committedFunds",
    }),
  ]);

  return {
    availableBalance: formatNumber(availableBalance as bigint),
    committedFunds: formatNumber(committedFunds as bigint),
    totalBalance: formatNumber(availableBalance as bigint + (committedFunds as bigint)),
  };
}