import { createPublicClient, createWalletClient, http, custom } from "viem";
import { sepolia } from "viem/chains";

// Public client: used for read-only blockchain interactions
export const getPublicClient = () =>
  createPublicClient({
    chain: sepolia,
    transport: http(
      `https://eth-sepolia.blockscout.com/api/eth-rpc?apikey=${process.env.NEXT_PUBLIC_BLOCKSCOUT_API_KEY}`
    ),
  });

// Wallet client: used for signed transactions via a connected wallet
export const getWalletClient = async ({
  address,
  eip1193,
}: {
  address: `0x${string}`;
  eip1193: import("viem").EIP1193Provider;
}) =>
  createWalletClient({
    account: address,
    chain: sepolia,
    transport: custom(eip1193),
  });
