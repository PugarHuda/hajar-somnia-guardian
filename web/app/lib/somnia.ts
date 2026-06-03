import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  defineChain,
  type Address,
  type EIP1193Provider,
} from "viem";

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
export const txExplorer = (hash: string) =>
  `https://shannon-explorer.somnia.network/tx/${hash}`;

/*//////////////////////////////////////////////////////////////
                              ABIs
//////////////////////////////////////////////////////////////*/

export const guardianAbi = [
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "hardWithdrawalBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "rapidDrainBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "greyZoneBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "riskThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "llmAgentId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "resetBreaker", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "requestRiskCheck", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "event", name: "HardBlock", inputs: [
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "amount", indexed: false },
    { type: "uint256", name: "bps", indexed: false }] },
  { type: "event", name: "AIVerdict", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "uint256", name: "riskScore", indexed: false },
    { type: "uint256", name: "validatorCount", indexed: false },
    { type: "bool", name: "tripped", indexed: false }] },
  { type: "event", name: "EscalatedToAI", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "amount", indexed: false }] },
  { type: "event", name: "CircuitBreakerTripped", inputs: [{ type: "string", name: "reason", indexed: false }] },
  { type: "event", name: "CircuitBreakerReset", inputs: [] },
] as const;

export const vaultAbi = [
  { type: "function", name: "totalAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "deposit", stateMutability: "payable", inputs: [], outputs: [] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [{ type: "uint256", name: "amount" }], outputs: [] },
  { type: "event", name: "Deposited", inputs: [
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "amount", indexed: false }] },
  { type: "event", name: "Withdrawn", inputs: [
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "amount", indexed: false }] },
  { type: "event", name: "WithdrawalBlocked", inputs: [
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "amount", indexed: false },
    { type: "string", name: "reason", indexed: false }] },
] as const;

/*//////////////////////////////////////////////////////////////
                          WALLET HELPERS
//////////////////////////////////////////////////////////////*/

export function getProvider(): EIP1193Provider | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as { ethereum?: EIP1193Provider }).ethereum;
}

const CHAIN_HEX = "0xc488"; // 50312

/** Connect the injected wallet and ensure it is on Somnia testnet. Returns the address. */
export async function connectWallet(): Promise<Address> {
  const provider = getProvider();
  if (!provider) throw new Error("No wallet found. Install MetaMask.");

  const accounts = (await provider.request({ method: "eth_requestAccounts" })) as Address[];

  try {
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: CHAIN_HEX }] });
  } catch (e: unknown) {
    // 4902 = chain not added; add it then switch.
    if ((e as { code?: number })?.code === 4902) {
      await provider.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: CHAIN_HEX,
          chainName: "Somnia Shannon Testnet",
          nativeCurrency: { name: "STT", symbol: "STT", decimals: 18 },
          rpcUrls: ["https://dream-rpc.somnia.network"],
          blockExplorerUrls: ["https://shannon-explorer.somnia.network"],
        }],
      });
    } else {
      throw e;
    }
  }
  return accounts[0];
}

export function walletClient() {
  const provider = getProvider();
  if (!provider) throw new Error("No wallet found.");
  return createWalletClient({ chain: somniaTestnet, transport: custom(provider) });
}
