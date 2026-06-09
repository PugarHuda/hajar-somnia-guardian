"use client";

import { useEffect, useState } from "react";
import { client, ADDRESSES, guardianAbi } from "../lib/somnia";
import DemoConsole from "../components/DemoConsole";

export default function DefensePage() {
  const [t, setT] = useState<{ hard: number; rapid: number; grey: number; risk: number } | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const proto = await client.readContract({ address: ADDRESSES.guardian as `0x${string}`, abi: guardianAbi, functionName: "protocols", args: [ADDRESSES.vault as `0x${string}`] });
        const p = proto as unknown as [boolean, boolean, string, string, bigint, bigint, bigint, bigint];
        setT({ hard: Number(p[4]) / 100, rapid: Number(p[5]) / 100, grey: Number(p[6]) / 100, risk: Number(p[7]) });
      } catch { /* ignore */ }
    })();
  }, []);

  const pct = (v?: number) => (v != null ? `${v}%` : "—");

  return (
    <main className="wrap">
      <div className="page-head">
        <h2>How Hajar defends — every tier, live</h2>
        <p className="sub">
          Defense in depth: synchronous deterministic blocks stop blatant attacks same-block, async
          AI judges the grey zone, event-driven reactivity latches persistently, and a TVL-drop
          detector catches drains that bypass the hook. Try it yourself below — deposit, then trigger
          a drain, the AI, or a reset.
        </p>
      </div>

      <DemoConsole />

      <div className="section-title">Synchronous tiers · same block · no waiting</div>
      <div className="tiers">
        <div className="tier t1"><div className="num">1</div><div>
          <h3>Deterministic hard rule</h3>
          <div className="meta">single-tx drain ≥ {pct(t?.hard)} of TVL, or velocity ≥ {pct(t?.rapid)} in the window</div>
          <p>Every withdrawal is checked in-line and reverted instantly if it&apos;s a blatant drain. Never latches — a revert would roll it back.</p>
        </div></div>
        <div className="tier t1"><div className="num" style={{ fontSize: 15 }}>1c</div><div>
          <h3>Synchronous spot-price guard</h3>
          <div className="meta">atomic · reads the vault&apos;s spotPrice() in-line</div>
          <p>Reverts in the same tx when the live price diverges from the reference beyond tolerance — the only tier fast enough to stop an <em>atomic flash-loan</em> manipulation. Fails open if unreadable.</p>
        </div></div>
        <div className="tier t1"><div className="num" style={{ fontSize: 15 }}>1d</div><div>
          <h3>Vault-wide outflow budget</h3>
          <div className="meta">ERC-7265 rate-limiter · aggregate across all users</div>
          <p>Blocks once the vault has bled its budget of TVL per window across <em>all</em> users combined — closing the sybil slow-drain gap that per-user velocity can&apos;t see.</p>
        </div></div>
      </div>

      <div className="section-title">Asynchronous AI tiers · Somnia validator consensus</div>
      <div className="tiers">
        <div className="tier t2"><div className="num">2</div><div>
          <h3>Consensus-verified AI judgment</h3>
          <div className="meta">grey zone ≥ {pct(t?.grey)} → LLM agent · latches if score ≥ {t?.risk ?? "—"}</div>
          <p>Ambiguous activity escalates to Somnia&apos;s deterministic LLM. Validators reach consensus on a 0–100 risk score; a high score latches the breaker. See it run on the <a href="/agents" style={{ color: "var(--accent-2)" }}>AI Agents</a> page.</p>
        </div></div>
        <div className="tier t2"><div className="num" style={{ fontSize: 14 }}>2b·c</div><div>
          <h3>Price oracle + threat intel</h3>
          <div className="meta">JSON API price sanity · Parse Website / JSON threat feed</div>
          <p>An external price-divergence check catches oracle manipulation / depeg; a self-updating threat feed learns about new exploits. Both latch on alarm.</p>
        </div></div>
        <div className="tier t2"><div className="num" style={{ fontSize: 15 }}>2d</div><div>
          <h3>Autonomous remediation</h3>
          <div className="meta">LLM tools-chat · the AI is given pause() and decides to act</div>
          <p>Not just a score — the agent is offered a <code>pause()</code> tool and <em>decides whether to use it</em>. Safe by design: the worst it can do is pause, which an admin resets. Verified live: it correctly declined to pause a healthy vault.</p>
        </div></div>
      </div>

      <div className="section-title">Event-driven &amp; post-hoc</div>
      <div className="tiers">
        <div className="tier t3"><div className="num">3</div><div>
          <h3>Reactivity latch</h3>
          <div className="meta">validator-triggered · separate execution · no keeper</div>
          <p>A real Somnia Reactivity subscription fires on the vault&apos;s withdrawal event and latches persistently. Verified live on v4: a withdrawal auto-fired the subscriber ~20 blocks later, no keeper.</p>
        </div></div>
        <div className="tier t3"><div className="num" style={{ fontSize: 13 }}>TVL</div><div>
          <h3>TVL-drop detector</h3>
          <div className="meta">catches drains that bypass the withdrawal hook</div>
          <p>Samples the vault&apos;s TVL and latches when it falls more than the guarded outflow Hajar actually saw — catching value that left through a path the guardian never observed.</p>
        </div></div>
      </div>
    </main>
  );
}
