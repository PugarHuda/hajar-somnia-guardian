import { createPublicClient, http, defineChain } from "viem";

export const somniaTestnet = defineChain({
  id: 50312,
  name: "Somnia Shannon Testnet",
  nativeCurrency: { name: "Somnia Test Token", symbol: "STT", decimals: 18 },
  rpcUrls: { default: { http: ["https://dream-rpc.somnia.network"] } },
  blockExplorers: {
    default: { name: "Shannon Explorer", url: "https://shannon-explorer.somnia.network" },
  },
});

export const client = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});

export const ADDRESSES = {
  guardian: "0xa5F1d1781bB50B41434E2f507667e22De3Df27a9",
  vault: "0x7e02327D9e6097DA2a30C588A9BA62C923ad8AD6",
  monitor: "0x40C37188A192866459A50A6D68b6160De9812bFc",
  platform: "0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776",
} as const;

export const explorer = (addr: string) =>
  `https://shannon-explorer.somnia.network/address/${addr}`;

export const guardianAbi = [
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "hardWithdrawalBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "rapidDrainBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "greyZoneBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "riskThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "llmAgentId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

export const vaultAbi = [
  { type: "function", name: "totalAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
