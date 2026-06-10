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

// Kill the white flash-of-unstyled-page (initial load AND every navigation): paint the dark theme
// bg from frame 0, before the app's CSS loads.
await ctx.addInitScript(() => {
  const paint = () => {
    const el = document.documentElement;
    if (el) el.style.background = "#0b0d0e";
    if (document.body) document.body.style.background = "#0b0d0e";
    const s = document.createElement("style");
    s.textContent = "html,body{background:#0b0d0e !important;}";
    (document.head || document.documentElement).appendChild(s);
  };
  paint();
  document.addEventListener("DOMContentLoaded", paint);
});

// Inject a VISIBLE cursor (headless Chromium renders none). Append to <html> (NOT body) so React's
// hydration can't reconcile it away, re-ensure it on an interval, and drive it from Node so it never
// depends on synthetic DOM events firing.
await ctx.addInitScript(() => {
  const ensure = () => {
    let c = document.getElementById("__cur");
    if (!c) {
      c = document.createElement("div");
      c.id = "__cur";
      c.style.cssText =
        "position:fixed;z-index:2147483647;width:30px;height:30px;border:4px solid #4ee08a;border-radius:50%;" +
        "background:rgba(78,224,138,.25);pointer-events:none;transform:translate(-50%,-50%);left:-300px;top:-300px;" +
        "box-shadow:0 0 18px #4ee08a, inset 0 0 8px rgba(78,224,138,.6);transition:width .08s,height .08s,background .08s";
      document.documentElement.appendChild(c);
    }
    return c;
  };
  window.__moveCur = (x, y) => { const c = ensure(); c.style.left = x + "px"; c.style.top = y + "px"; };
  window.__pressCur = (d) => { const c = ensure(); if (d) { c.style.width = "16px"; c.style.height = "16px"; c.style.background = "rgba(78,224,138,.7)"; } else { c.style.width = "30px"; c.style.height = "30px"; c.style.background = "rgba(78,224,138,.25)"; } };
  setInterval(ensure, 250);
  document.addEventListener("mousemove", (e) => window.__moveCur(e.clientX, e.clientY));
});

const page = await ctx.newPage();
const wait = (ms) => page.waitForTimeout(ms);
// Smoothly move the fake cursor to (x,y), driving it from Node so it's guaranteed visible.
const pointer = async (x, y) => {
  const steps = 24;
  await page.mouse.move(x, y, { steps });
  await page.evaluate(([px, py]) => (window).__moveCur && (window).__moveCur(px, py), [x, y]).catch(() => {});
};
// Pre-position the cursor over a button (visible travel, NO click yet) — call during the prior
// sentence so the cursor is already there when the narration names it.
const goTo = async (rx) => {
  const b = page.getByRole("button", { name: rx }).first();
  await b.scrollIntoViewIfNeeded();
  const box = await b.boundingBox();
  if (box) await pointer(box.x + box.width / 2, box.y + box.height / 2);
  return b;
};
// Click a pre-positioned button INSTANTLY (cursor already there) — call exactly when its word is said.
const tap = async (b) => {
  await page.evaluate(() => (window).__pressCur && (window).__pressCur(true)).catch(() => {});
  await b.click();
  await wait(140);
  await page.evaluate(() => (window).__pressCur && (window).__pressCur(false)).catch(() => {});
};
// (legacy one-shot move+click, still used where exact timing doesn't matter)
const click = async (rx) => { const b = await goTo(rx); await wait(350); await tap(b); };

console.log("acting as", account.address);

const t0 = Date.now();
const at = () => Date.now() - t0;
const mark = {};

// ===== SECTION 1: DEFENSE (>= seg1 28.7s) =====
// VO sentence timings from edge-tts SentenceBoundary (+ 300ms VO offset from mark.defense):
//   "I connect a wallet"      → 4450ms into VO → abs 4750ms from mark
//   "Now I deposit..."        → 9887ms into VO → abs 10187ms from mark
//   "I try to drain..."       → 19712ms into VO → abs 20012ms from mark
await page.goto(SITE + "/defense", { waitUntil: "domcontentloaded", timeout: 45000 });
await page.getByRole("button", { name: /connect/i }).first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
await pointer(760, 300); // bring cursor on-screen
mark.defense = at();

// goTo takes ~800ms. Need tap at mark+4750ms → wait(4750-800-50) = wait(3900)
const bConnect = await goTo(/connect/i);
await wait(3900);           // "I connect a wallet." → tap at ~4.75s
await tap(bConnect);

// fill input while "Every button here sends a real signed transaction on-chain."
const amt = page.locator("input.inp").first();
await amt.fill("0.03");
await pointer(700, 290);    // point at wallet address shown in console-head

// goTo+fill cost ~1200ms. Deposit tap target: mark+10187ms. Time so far: ~4950+1200=6150ms → wait(3900)
const bDep = await goTo(/^deposit/i);
await wait(3900);           // "Now I deposit into the protected vault" → tap at ~10.2s
await tap(bDep);

// "A real transaction, and the protected value goes up on-chain." — point at live feed
await wait(2500);
await pointer(480, 390);    // feed area (deposited event appears here)
await wait(1700);           // "Now watch the guardian defend."

// Drain tap target: mark+20012ms. Time so far: ~10327+2500+1700=14527ms → goTo(~500ms)=15027ms → wait(4800)
const bDrain = await goTo(/try drain/i);
await wait(4800);           // "I try to drain eighty percent..." → tap at ~20s
await tap(bDrain);

// "Tier one reverts it instantly, same block." — point at feed showing HardBlock
await wait(2000);
await pointer(480, 390);    // HardBlock event appears in feed
await wait(1700);           // "No waiting."

// "The breaker holds." — scroll down to show Tier-1 explanation card
await page.mouse.wheel(0, 500);
await wait(1800);
await page.mouse.wheel(0, -500);

const bReset = await goTo(/reset breaker/i); await tap(bReset);
await wait(2000);

// ===== SECTION 2: INTELLIGENCE (>= seg2 27.6s) =====
await page.goto(SITE + "/intelligence", { waitUntil: "domcontentloaded", timeout: 45000 }).catch(() => {});
await page.getByText(/Self-learning/i).first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
mark.intelligence = at();
await pointer(340, 210);    // point at "Highest learned threat" card
await wait(3800);
await pointer(680, 210);    // point at "Categories tracked" card
await wait(3200);
await page.mouse.wheel(0, 300); // scroll to knowledge base bars
await pointer(480, 380);    // point at oracle-manipulation bar
await wait(4000);
await pointer(480, 430);    // point at market-stress bar (market-stress = 10)
await wait(3500);
await page.mouse.wheel(0, 320); // scroll to feedback loop callout
await pointer(500, 360);
await wait(4500);           // "what it learned shapes the AI"
await page.mouse.wheel(0, 260); // scroll to "How it learns"
await pointer(520, 340);
await wait(4200);
await page.mouse.wheel(0, -1200); // scroll back to top
await wait(2000);

// ===== SECTION 3: AI AGENTS (>= seg3 31.6s) =====
await page.goto(SITE + "/agents", { waitUntil: "domcontentloaded", timeout: 45000 }).catch(() => {});
await page.getByText(/AI agents/i).first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
mark.agents = at();
await pointer(280, 320);    // LLM Inference card
await wait(4000);
await pointer(640, 320);    // JSON API card
await wait(3500);
await pointer(1000, 320);   // Parse Website card
await wait(3500);
await page.mouse.wheel(0, 460); // scroll to AgentLab / "Fire an agent live"
await pointer(480, 460);    // connect wallet button area
await wait(5000);           // "Connecting a wallet here lets you fire one yourself"
await page.mouse.wheel(0, 200);
await pointer(520, 500);    // feed section
await wait(5500);           // "Watch EscalatedToAI then AIVerdict stream in"
await page.mouse.wheel(0, 400); // scroll to "How a verdict is produced"
await pointer(440, 400);
await wait(5000);
await page.mouse.wheel(0, -1460); // scroll to top

// ===== SECTION 4: IDENTITY (>= seg4 33.3s) =====
await page.goto(SITE + "/identity", { waitUntil: "domcontentloaded", timeout: 45000 }).catch(() => {});
await page.getByText(/Agent identity/i).first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
mark.identity = at();
await pointer(280, 260);    // agentId card
await wait(4000);           // "Hajar is a registered ERC 8004 Trustless Agent"
await pointer(640, 260);    // owner card (verified on-chain)
await wait(3800);           // "To verify: open the agent card, call ownerOf one"
await pointer(1000, 260);   // agents-in-registry card
await wait(3200);
await page.mouse.wheel(0, 360); // scroll to standards
await pointer(400, 380);    // ERC-8004 tier
await wait(4500);           // "crypto-economic trust IS Somnia validator consensus"
await pointer(400, 500);    // ERC-7265 tier
await wait(4000);           // "outflow budget tier IS the ERC-7265 rate-limiter"
await pointer(400, 600);    // x402 tier
await wait(3500);           // "x402 flag for agent payments"
await page.mouse.wheel(0, 300); // scroll to discovery surface
await pointer(500, 420);
await wait(4500);           // "Real clicks. Real transactions. Real on-chain data."
await page.mouse.wheel(0, -1000);
await wait(3000);

writeFileSync(new URL("./out/demo-timings.json", import.meta.url), JSON.stringify(mark, null, 2));
console.log("timings", mark);
await ctx.close();
await browser.close();
console.log("interactive demo recorded -> out/demo-interactive/");
