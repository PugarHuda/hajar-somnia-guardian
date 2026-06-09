"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { formatEther } from "viem";
import { client, ADDRESSES, explorer, guardianAbi, vaultAbi } from "./lib/somnia";

type State = { paused: boolean; tvl: bigint };

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

const PAGES = [
  { href: "/defense", t: "Defense", d: "Every tier, live — and an interactive demo you can drive: deposit, drain, trigger the AI, reset the breaker." },
  { href: "/agents", t: "AI Agents", d: "Watch Somnia's on-chain agents work: fire one yourself and see the validator-consensus verdict land on-chain." },
  { href: "/intelligence", t: "Intelligence", d: "Hajar's self-learning threat knowledge base — what it has learned about exploits, accumulated on-chain." },
  { href: "/identity", t: "Identity", d: "Hajar as a discoverable ERC-8004 agent, composing ERC-7265 and x402. Verify its identity on-chain." },
];

export default function Home() {
  const [s, setS] = useState<State | null>(null);
  const [at, setAt] = useState("");

  async function load() {
    try {
      const g = { address: ADDRESSES.guardian as `0x${string}`, abi: guardianAbi };
      const [paused, tvl] = await Promise.all([
        client.readContract({ ...g, functionName: "paused", args: [ADDRESSES.vault as `0x${string}`] }),
        client.readContract({ address: ADDRESSES.vault as `0x${string}`, abi: vaultAbi, functionName: "totalAssets" }),
      ]);
      setS({ paused: paused as boolean, tvl: tvl as bigint });
      setAt(new Date().toLocaleTimeString());
    } catch { /* ignore */ }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 12000);
    return () => clearInterval(t);
  }, []);

  return (
    <main className="wrap">
      <div className="brand">
        <div className="logo">H</div>
        <div>
          <h1>Hajar</h1>
          <span className="tag">Autonomous DeFi Guardian · Somnia Agentic L1</span>
        </div>
      </div>

      <p className="lede">
        A multi-tier security layer that protects DeFi protocols from drains and exploits — combining
        instant deterministic circuit breakers with <strong>consensus-verified AI run by Somnia
        validators</strong>, a self-learning threat brain, and a discoverable on-chain agent identity.
        Everything below is live on the Shannon testnet.
      </p>

      <div className="statusbar">
        <div className="card">
          <div className="label">Circuit breaker</div>
          <div className="value">
            {!s ? <span className="pill"><span className="dot gray" /> loading…</span>
              : s.paused ? <span className="pill" style={{ color: "var(--red)" }}><span className="dot red" /> PAUSED</span>
              : <span className="pill" style={{ color: "var(--green)" }}><span className="dot green" /> ACTIVE</span>}
          </div>
        </div>
        <div className="card">
          <div className="label">Protected TVL</div>
          <div className="value">{s ? `${Number(formatEther(s.tvl)).toFixed(3)} STT` : "—"}</div>
        </div>
        <div className="card">
          <div className="label">Somnia AI agents</div>
          <div className="value">3 wired<span style={{ fontSize: 12, color: "var(--muted)", marginLeft: 6 }}>LLM · JSON · Parse</span></div>
        </div>
      </div>
      {at && <p className="refresh">Live from Somnia testnet · last update {at} · auto-refresh 12s</p>}

      <div className="section-title">Explore</div>
      <div className="agent-grid" style={{ gridTemplateColumns: "1fr 1fr" }}>
        {PAGES.map((p) => (
          <Link key={p.href} href={p.href} className="agent-card" style={{ textDecoration: "none", color: "inherit", display: "block" }}>
            <div className="an" style={{ color: "var(--accent-2)" }}>{p.t} →</div>
            <div className="ad">{p.d}</div>
          </Link>
        ))}
      </div>

      <div className="section-title">Deployed on Somnia Shannon testnet</div>
      <div className="addrs">
        <div className="addr"><span className="k">HajarGuardian v4 (all tiers)</span><a href={explorer(ADDRESSES.guardian)} target="_blank" rel="noreferrer">{short(ADDRESSES.guardian)}</a></div>
        <div className="addr"><span className="k">HajarThreatLearner (self-learning)</span><a href={explorer(ADDRESSES.learner)} target="_blank" rel="noreferrer">{short(ADDRESSES.learner)}</a></div>
        <div className="addr"><span className="k">HajarReactiveSubscriber (Tier-3)</span><a href={explorer(ADDRESSES.monitor)} target="_blank" rel="noreferrer">{short(ADDRESSES.monitor)}</a></div>
        <div className="addr"><span className="k">ProtectedVault</span><a href={explorer(ADDRESSES.vault)} target="_blank" rel="noreferrer">{short(ADDRESSES.vault)}</a></div>
        <div className="addr"><span className="k">Somnia Agents platform</span><a href={explorer(ADDRESSES.platform)} target="_blank" rel="noreferrer">{short(ADDRESSES.platform)}</a></div>
      </div>

      <p className="foot">
        Built for the Somnia Agentathon · <Link href="/slide" style={{ color: "var(--accent-2)" }}>view the pitch deck</Link> ·{" "}
        <a href="https://github.com/PugarHuda/hajar-somnia-guardian" target="_blank" rel="noreferrer">GitHub</a> · chain 50312 · STT testnet
      </p>
    </main>
  );
}
