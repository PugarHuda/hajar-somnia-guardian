"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { formatEther } from "viem";
import { client, ADDRESSES, explorer, guardianAbi, vaultAbi } from "./lib/somnia";

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

const PAGES = [
  { href: "/defense", t: "Defense", d: "Every tier, live — plus an interactive demo you can drive: deposit, drain, trigger the AI, reset the breaker." },
  { href: "/agents", t: "AI Agents", d: "Watch Somnia's on-chain agents work: fire one yourself and see the validator-consensus verdict land on-chain." },
  { href: "/intelligence", t: "Intelligence", d: "Hajar's self-learning threat knowledge base — what it has learned about exploits, accumulated on-chain." },
  { href: "/identity", t: "Identity", d: "Hajar as a discoverable ERC-8004 agent, composing ERC-7265 and x402. Verify its identity on-chain." },
];

export default function Landing() {
  const [paused, setPaused] = useState<boolean | null>(null);
  const [tvl, setTvl] = useState<bigint | null>(null);

  useEffect(() => {
    const load = async () => {
      try {
        const g = { address: ADDRESSES.guardian as `0x${string}`, abi: guardianAbi };
        const [p, t] = await Promise.all([
          client.readContract({ ...g, functionName: "paused", args: [ADDRESSES.vault as `0x${string}`] }),
          client.readContract({ address: ADDRESSES.vault as `0x${string}`, abi: vaultAbi, functionName: "totalAssets" }),
        ]);
        setPaused(p as boolean); setTvl(t as bigint);
      } catch { /* ignore */ }
    };
    load();
    const i = setInterval(load, 12000);
    return () => clearInterval(i);
  }, []);

  const active = paused === false;

  return (
    <main className="landing">
      <section className="hero">
        <div className="crest">H</div>
        <h1>HAJAR</h1>
        <div className="quest">⚔ AUTONOMOUS DEFI GUARDIAN · SOMNIA AGENTIC L1</div>
        <p className="pitch">
          A multi-tier security layer that stops drains and exploits — instant deterministic circuit
          breakers, <strong>AI run inside Somnia validator consensus</strong>, a self-learning threat
          brain, and a discoverable on-chain agent identity. Every word below is live on the testnet.
        </p>

        <div className="hpwrap">
          <div className="hplabel">
            <span>◆ CIRCUIT BREAKER</span>
            <span>{paused === null ? "…" : active ? "ACTIVE" : "PAUSED"} · {tvl != null ? `${Number(formatEther(tvl)).toFixed(3)} STT GUARDED` : "…"}</span>
          </div>
          <div className="hpbar"><div className={`hpfill ${active ? "" : "red"}`} style={{ width: active ? "100%" : "22%" }} /></div>
        </div>

        <div className="cta">
          <Link href="/agents" className="btn primary">▶ See the agents work</Link>
          <Link href="/defense" className="btn">🛡 Try the defense demo</Link>
          <Link href="/slide" className="btn">📜 Pitch deck</Link>
        </div>

        <div className="statline">
          <div className="stat framed"><div className="n">9</div><div className="l">defense tiers</div></div>
          <div className="stat framed"><div className="n">3</div><div className="l">Somnia agents</div></div>
          <div className="stat framed"><div className="n">78</div><div className="l">tests passing</div></div>
          <div className="stat framed"><div className="n">100%</div><div className="l">on-chain, no mocks</div></div>
        </div>
      </section>

      <div className="section-title">Try it — 3 ways</div>
      <div className="agent-grid">
        <div className="agent-card">
          <div className="an" style={{ color: "var(--accent-2)" }}>1 · Just browse</div>
          <div className="ad">
            No wallet needed. Everything on this site is read <strong>live from the chain</strong> —
            the breaker, the protected TVL, and the threat knowledge base Hajar learned by itself.
            Start at <Link href="/intelligence">Intelligence</Link> to see <strong>market-stress = 10</strong>,
            learned via validator consensus.
          </div>
        </div>
        <div className="agent-card">
          <div className="an" style={{ color: "var(--accent-2)" }}>2 · Make an agent run</div>
          <div className="ad">
            Connect a wallet on <Link href="/agents">AI Agents</Link>, click <em>“Make an AI agent run”</em>,
            and watch the validator-consensus verdict stream in. Need test STT? Grab some from the{" "}
            <a href="https://testnet.somnia.network/" target="_blank" rel="noreferrer">Somnia faucet</a>{" "}
            (chain 50312) — the Connect button auto-adds the network.
          </div>
        </div>
        <div className="agent-card">
          <div className="an" style={{ color: "var(--accent-2)" }}>3 · Drive the defense</div>
          <div className="ad">
            On <Link href="/defense">Defense</Link>: deposit, then try an 80%-of-TVL drain (reverts
            instantly), trigger the AI, or reset the breaker — every tier is interactive and live.
          </div>
        </div>
      </div>

      <div className="section-title">Choose your path</div>
      <div className="agent-grid" style={{ gridTemplateColumns: "1fr 1fr" }}>
        {PAGES.map((p) => (
          <Link key={p.href} href={p.href} className="agent-card" style={{ textDecoration: "none", color: "inherit", display: "block" }}>
            <div className="an">{p.t} →</div>
            <div className="ad">{p.d}</div>
          </Link>
        ))}
      </div>

      <div className="section-title">The realm · deployed on Somnia Shannon testnet</div>
      <div className="addrs">
        <div className="addr"><span className="k">HajarGuardian v4 (all tiers)</span><a href={explorer(ADDRESSES.guardian)} target="_blank" rel="noreferrer">{short(ADDRESSES.guardian)}</a></div>
        <div className="addr"><span className="k">HajarThreatLearner (self-learning)</span><a href={explorer(ADDRESSES.learner)} target="_blank" rel="noreferrer">{short(ADDRESSES.learner)}</a></div>
        <div className="addr"><span className="k">HajarReactiveSubscriber (Tier-3)</span><a href={explorer(ADDRESSES.monitor)} target="_blank" rel="noreferrer">{short(ADDRESSES.monitor)}</a></div>
        <div className="addr"><span className="k">ProtectedVault</span><a href={explorer(ADDRESSES.vault)} target="_blank" rel="noreferrer">{short(ADDRESSES.vault)}</a></div>
      </div>

      <p className="foot">
        Built for the Somnia Agentathon ·{" "}
        <a href="https://github.com/PugarHuda/hajar-somnia-guardian" target="_blank" rel="noreferrer">GitHub</a> · chain 50312 · STT testnet
      </p>
    </main>
  );
}
