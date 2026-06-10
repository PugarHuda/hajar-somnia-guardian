// Records a GENUINELY INTERACTIVE demo of the live Hajar site: Playwright clicks the real buttons
// (Connect -> Deposit -> Try Drain), and a headless wallet (the deployer's testnet key, injected as
// window.ethereum and signed server-side via viem) makes the clicks send REAL transactions on
// Somnia. The guardian reacts on-chain; the feed + console messages update on camera.
//
// Output: out/demo-interactive/<auto>.webm  ->  convert with the npm script.
import { readFileSync } from "node:fs";
import { chromium } from "playwright";
import { createWalletClient, http, defineChain } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const SITE = process.env.SITE || "https://hajar-somnia-guardian.vercel.app";
const RPC = "https://dream-rpc.somnia.network";
const W = 1920, H = 1080;

// --- read the deployer key from ../.env (testnet throwaway) ---
const env = readFileSync(new URL("../.env", import.meta.url), "utf8");
let pk = (env.match(/^PRIVATE_KEY=(.*)$/m)?.[1] || "").trim().replace(/^"|"$/g, "");
if (!pk.startsWith("0x")) pk = "0x" + pk;
const account = privateKeyToAccount(pk);

const somnia = defineChain({ id: 50312, name: "Somnia", nativeCurrency: { name: "STT", symbol: "STT", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } });
const wallet = createWalletClient({ account, chain: somnia, transport: http(RPC) });

async function rpc(method, params = []) {
  const r = await fetch(RPC, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  const j = await r.json();
  if (j.error) throw new Error(j.error.message);
  return j.result;
}

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: W, height: H }, recordVideo: { dir: "out/demo-interactive", size: { width: W, height: H } } });

// node-side signer: take {to,data,value} from the page and send a LEGACY tx on Somnia.
await ctx.exposeFunction("__sendTx", async (tx) => {
  const gasPrice = BigInt(await rpc("eth_gasPrice"));
  const hash = await wallet.sendTransaction({
    to: tx.to, data: tx.data || "0x", value: tx.value ? BigInt(tx.value) : 0n,
    gas: 8_000_000n, gasPrice, type: "legacy",
  });
  return hash;
});
// node-side read passthrough for everything else viem needs (nonce, estimate, blocks, calls).
await ctx.exposeFunction("__rpcCall", async (method, params) => {
  try { return await rpc(method, params); }
  catch (e) {
    if (method === "eth_maxPriorityFeePerGas") return "0x0";
    throw e;
  }
});

// inject a minimal EIP-1193 provider BEFORE the app loads.
await ctx.addInitScript(({ addr }) => {
  const provider = {
    isMetaMask: true,
    request: async ({ method, params }) => {
      if (method === "eth_requestAccounts" || method === "eth_accounts") return [addr];
      if (method === "eth_chainId") return "0xc488";
      if (method === "net_version") return "50312";
      if (method === "wallet_switchEthereumChain" || method === "wallet_addEthereumChain") return null;
      if (method === "eth_sendTransaction") return await window.__sendTx(params[0]);
      return await window.__rpcCall(method, params || []);
    },
    on: () => {}, removeListener: () => {},
  };
  // @ts-ignore
  window.ethereum = provider;
}, { addr: account.address });

const page = await ctx.newPage();
const wait = (ms) => page.waitForTimeout(ms);
const click = async (rx) => { const b = page.getByRole("button", { name: rx }).first(); await b.scrollIntoViewIfNeeded(); await b.click(); };

console.log("acting as", account.address);

await page.goto(SITE + "/defense", { waitUntil: "networkidle", timeout: 45000 });
await wait(3500);

// 1) Connect the (headless) wallet.
await click(/connect/i); await wait(4000);

// 2) Deposit a small amount -> real tx -> Deposited shows in the feed.
const amt = page.locator("input.inp").first();
await amt.fill("0.03"); await wait(800);
await click(/^deposit/i); await wait(11000);

// 3) Try Drain 80% of TVL -> the guardian reverts it instantly (Tier-1). Console shows the block.
await click(/try drain/i); await wait(11000);
await page.mouse.wheel(0, 400); await wait(4000); // show the message / feed

// 4) Reset (if anything latched) + settle.
await click(/reset breaker/i).catch(() => {}); await wait(6000);

await ctx.close();
await browser.close();
console.log("interactive demo recorded -> out/demo-interactive/");
