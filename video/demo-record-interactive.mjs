// Records a GENUINELY INTERACTIVE demo of the live Hajar site: Playwright clicks the real buttons
// (Connect -> Deposit -> Try Drain), and a headless wallet (the deployer's testnet key, injected as
// window.ethereum and signed server-side via viem) makes the clicks send REAL transactions on
// Somnia. The guardian reacts on-chain; the feed + console messages update on camera.
//
// Output: out/demo-interactive/<auto>.webm  ->  convert with the npm script.
import { readFileSync, writeFileSync } from "node:fs";
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

// Inject a VISIBLE cursor (headless Chromium renders none) that follows the mouse + pulses on click.
await ctx.addInitScript(() => {
  const mk = () => {
    if (document.getElementById("__cur")) return;
    const c = document.createElement("div");
    c.id = "__cur";
    c.style.cssText =
      "position:fixed;z-index:2147483647;width:26px;height:26px;border:3px solid #4ee08a;border-radius:50%;" +
      "background:rgba(78,224,138,.22);pointer-events:none;transform:translate(-50%,-50%);left:-100px;top:-100px;" +
      "box-shadow:0 0 14px #4ee08a;transition:width .08s,height .08s,background .08s";
    document.body && document.body.appendChild(c);
  };
  const set = (x, y) => { const c = document.getElementById("__cur"); if (c) { c.style.left = x + "px"; c.style.top = y + "px"; } };
  document.addEventListener("DOMContentLoaded", mk);
  if (document.body) mk();
  document.addEventListener("mousemove", (e) => set(e.clientX, e.clientY));
  document.addEventListener("mousedown", () => { const c = document.getElementById("__cur"); if (c) { c.style.width = "14px"; c.style.height = "14px"; c.style.background = "rgba(78,224,138,.6)"; } });
  document.addEventListener("mouseup", () => { const c = document.getElementById("__cur"); if (c) { c.style.width = "26px"; c.style.height = "26px"; c.style.background = "rgba(78,224,138,.22)"; } });
});

const page = await ctx.newPage();
const wait = (ms) => page.waitForTimeout(ms);
// Move the cursor SMOOTHLY to a button's center (so you see it travel), then click.
const click = async (rx) => {
  const b = page.getByRole("button", { name: rx }).first();
  await b.scrollIntoViewIfNeeded();
  const box = await b.boundingBox();
  if (box) { await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 25 }); await wait(400); }
  await b.click();
};

console.log("acting as", account.address);

// Section waits are tuned >= each VO segment's length so narration never spills into the next page.
const t0 = Date.now();
const at = () => Date.now() - t0;
const mark = {};

// ===== SECTION 1: DEFENSE (>= seg1 ~28.7s) =====
// domcontentloaded (fast) instead of networkidle (the live RPC polling keeps the network busy ~7s,
// which showed a long white screen). Wait for real content, then a short settle — no white gap.
await page.goto(SITE + "/defense", { waitUntil: "domcontentloaded", timeout: 45000 });
await page.getByRole("button", { name: /connect/i }).first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
await page.mouse.move(960, 540, { steps: 10 }); // bring the cursor on-screen
mark.defense = at();
await wait(2500);
await click(/connect/i); await wait(4500);              // connect
const amt = page.locator("input.inp").first();
await amt.fill("0.03"); await wait(900);
await click(/^deposit/i); await wait(12000);            // deposit (real tx)
await click(/try drain/i); await wait(11000);           // drain -> reverted
await page.mouse.wheel(0, 350); await wait(3500);       // show the block message
await click(/reset breaker/i).catch(() => {}); await wait(2500);

// ===== SECTION 2: INTELLIGENCE (>= seg2 ~14.1s) =====
await page.goto(SITE + "/intelligence", { waitUntil: "networkidle", timeout: 45000 }).catch(() => {});
mark.intelligence = at();
await wait(7000); await page.mouse.wheel(0, 380); await wait(6000); await page.mouse.wheel(0, -380); await wait(1500);

// ===== SECTION 3: AI AGENTS (>= seg3 ~11.1s) =====
await page.goto(SITE + "/agents", { waitUntil: "networkidle", timeout: 45000 }).catch(() => {});
mark.agents = at();
await wait(5500); await page.mouse.wheel(0, 460); await wait(6500);

// ===== SECTION 4: IDENTITY + close (>= seg4 ~19s) =====
await page.goto(SITE + "/identity", { waitUntil: "networkidle", timeout: 45000 }).catch(() => {});
mark.identity = at();
await wait(9000); await page.mouse.wheel(0, 350); await wait(8000); await page.mouse.wheel(0, -350); await wait(3000);

writeFileSync(new URL("./out/demo-timings.json", import.meta.url), JSON.stringify(mark, null, 2));
console.log("timings", mark);
await ctx.close();
await browser.close();
console.log("interactive demo recorded -> out/demo-interactive/");
