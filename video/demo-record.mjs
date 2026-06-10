// Records a guided tour of the LIVE Hajar site (real on-chain data) to a video.
// Output: out/demo/<auto>.webm  ->  convert to mp4 with the npm script.
import { chromium } from "playwright";

const SITE = process.env.SITE || "https://hajar-somnia-guardian.vercel.app";
const W = 1920, H = 1080;

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: W, height: H },
  recordVideo: { dir: "out/demo", size: { width: W, height: H } },
  deviceScaleFactor: 1,
});
const page = await ctx.newPage();
const wait = (ms) => page.waitForTimeout(ms);

const visit = async (path, settle = 5000) => {
  await page.goto(SITE + path, { waitUntil: "networkidle", timeout: 45000 }).catch(() => {});
  await wait(settle);
};

// Landing — let the live status (breaker HP bar, TVL) load, then scroll the "Try it" cards.
await visit("/", 4500);
await page.mouse.wheel(0, 500); await wait(2500);
await page.mouse.wheel(0, 600); await wait(2500);
await page.mouse.wheel(0, -1100); await wait(1500);

// Intelligence — the anchor: the self-learned knowledge base (market-stress).
await visit("/intelligence", 5500);
await page.mouse.wheel(0, 400); await wait(3500);
await page.mouse.wheel(0, -400); await wait(1000);

// Defense — the tiers + interactive console.
await visit("/defense", 5000);
await page.mouse.wheel(0, 500); await wait(3000);

// AI Agents — the catalog + live feed + the consensus explainer.
await visit("/agents", 5500);
await page.mouse.wheel(0, 500); await wait(3500);

// Identity — ERC-8004.
await visit("/identity", 5000);

// Back to the landing crest to close.
await visit("/", 3000);

await ctx.close(); // finalizes + writes the .webm
await browser.close();
console.log("demo recorded -> out/demo/");
