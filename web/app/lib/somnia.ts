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
  // Guardian v3 — adds Tier-2d autonomous remediation (inferToolsChat, live-verified)
  // on top of v2's Tier-2b price oracle + Tier-2c threat intel.
  guardian: "0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c",
  vault: "0x237A48d4B05944cC78b2b469F68F1f21D7AdfF39",
  monitor: "0x5aE10c3c1FE5eCf0b2a44a23E3bB62f7A7deD502", // real reactivity subscriber (Tier-3, bound to v3)
  platform: "0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776",
} as const;

// ERC-8004 Identity Registry where Hajar is registered as a Trustless Agent. Empty until the
// HajarAgentRegistry is deployed; the agent-card omits on-chain registrations while empty (no fakes).
export const REGISTRY = {
  address: "" as string, // set to the deployed HajarAgentRegistry address
  agentId: 0, // the agentId minted to Hajar on register()
} as const;

export const explorer = (addr: string) =>
  `https://shannon-explorer.somnia.network/address/${addr}`;
export const txExplorer = (hash: string) =>
  `https://shannon-explorer.somnia.network/tx/${hash}`;

/*//////////////////////////////////////////////////////////////
                              ABIs
//////////////////////////////////////////////////////////////*/

export const guardianAbi = [
  { type: "function", name: "paused", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "llmAgentId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "jsonAgentId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "parseAgentId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function", name: "protocols", stateMutability: "view", inputs: [{ type: "address" }],
    outputs: [
      { type: "bool", name: "registered" },
      { type: "bool", name: "paused" },
      { type: "address", name: "admin" },
      { type: "address", name: "monitor" },
      { type: "uint256", name: "hardBps" },
      { type: "uint256", name: "rapidBps" },
      { type: "uint256", name: "greyBps" },
      { type: "uint256", name: "risk" },
    ],
  },
  { type: "function", name: "resetBreaker", stateMutability: "nonpayable", inputs: [{ type: "address" }], outputs: [] },
  { type: "function", name: "requestRiskCheck", stateMutability: "nonpayable", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "event", name: "HardBlock", inputs: [
    { type: "address", name: "vault", indexed: true },
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "bps", indexed: false }] },
  { type: "event", name: "AIVerdict", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true },
    { type: "uint256", name: "riskScore", indexed: false },
    { type: "uint256", name: "validatorCount", indexed: false },
    { type: "bool", name: "tripped", indexed: false }] },
  { type: "event", name: "EscalatedToAI", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true },
    { type: "address", name: "user", indexed: false },
    { type: "uint256", name: "amount", indexed: false }] },
  { type: "event", name: "CircuitBreakerTripped", inputs: [
    { type: "address", name: "vault", indexed: true },
    { type: "string", name: "reason", indexed: false }] },
  { type: "event", name: "CircuitBreakerReset", inputs: [{ type: "address", name: "vault", indexed: true }] },
  { type: "event", name: "PriceChecked", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true }] },
  { type: "event", name: "PriceVerdict", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true },
    { type: "uint256", name: "marketPrice", indexed: false },
    { type: "uint256", name: "referencePrice", indexed: false },
    { type: "uint256", name: "divergenceBps", indexed: false },
    { type: "bool", name: "alarm", indexed: false }] },
  { type: "event", name: "ThreatScanned", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true }] },
  { type: "event", name: "ThreatVerdict", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true },
    { type: "uint256", name: "threatScore", indexed: false },
    { type: "bool", name: "alarm", indexed: false }] },
  { type: "event", name: "RemediationRequested", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true }] },
  { type: "event", name: "RemediationVerdict", inputs: [
    { type: "uint256", name: "requestId", indexed: true },
    { type: "address", name: "vault", indexed: true },
    { type: "string", name: "finishReason", indexed: false },
    { type: "bool", name: "acted", indexed: false }] },
  // Hardening tiers (guardian v4+): outflow budget, spot-price guard, TVL-drop detector.
  { type: "function", name: "checkTvlDrop", stateMutability: "nonpayable", inputs: [{ type: "address" }], outputs: [{ type: "bool" }] },
  { type: "event", name: "OutflowBudgetBlocked", inputs: [
    { type: "address", name: "vault", indexed: true },
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "cumBps", indexed: false }] },
  { type: "event", name: "SpotPriceBlocked", inputs: [
    { type: "address", name: "vault", indexed: true },
    { type: "address", name: "user", indexed: true },
    { type: "uint256", name: "spotPrice", indexed: false },
    { type: "uint256", name: "divergenceBps", indexed: false }] },
  { type: "event", name: "TvlChecked", inputs: [
    { type: "address", name: "vault", indexed: true },
    { type: "uint256", name: "currentTvl", indexed: false },
    { type: "uint256", name: "unexplainedBps", indexed: false },
    { type: "bool", name: "latched", indexed: false }] },
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
