import { createPimlicoClient } from 'permissionless/clients/pimlico'
import { createPublicClient, http } from 'viem';
import { baseSepolia } from 'viem/chains';
import { entryPoint06Address } from "viem/account-abstraction"

// Bundler URL with API key + sponsorship policy
export const pimlicoBundlerUrl = `https://api.pimlico.io/v2/11155111/rpc?apikey=${process.env.NEXT_PUBLIC_PIMLICO_API_KEY}&sponsorshipPolicyId=${process.env.NEXT_PUBLIC_PIMPLICO_SPONSOR_ID}`;
export const pimlicoBundlerTransport = http(pimlicoBundlerUrl);

// Pimlico client for account abstraction (ERC-4337)
export const pimlicoClient = createPimlicoClient({
  transport: pimlicoBundlerTransport,
  entryPoint: {
    address: entryPoint06Address,
    version: "0.6",
  }
})

// Public client for standard JSON-RPC calls
export const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(),
});
