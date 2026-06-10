"use client";

import { useEffect, useState, useCallback } from "react";
import Logo from "../components/Logo";

/**
 * Hajar pitch deck — a self-contained, keyboard-navigable slide deck at /slide.
 * Arrow keys / Space / click to advance. Dark, minimal, demo-day ready.
 */

type Slide = { kicker?: string; title: string; body: React.ReactNode };

// 8bitcn palette — matches the web (retro green accent, hard mono pixel frames).
const C = { bg: "#0b0d0e", panel: "#15191b", ink: "#e9eef0", dim: "#8b969b", cyan: "#4ee08a", red: "#ff5b6e", green: "#4ee08a", line: "#e9eef0" };
const PIX = "var(--font-pixel), 'Press Start 2P', monospace";
const BODY = "var(--font-body), 'Pixelify Sans', ui-sans-serif, system-ui, sans-serif";

const ulS: React.CSSProperties = { fontSize: 21, color: C.ink, lineHeight: 1.7, maxWidth: 820, display: "flex", flexDirection: "column", gap: 14, listStyle: "none", padding: 0, fontFamily: BODY };
const cardS: React.CSSProperties = { background: C.panel, border: "none", borderRadius: 0, padding: "16px 18px", boxShadow: `0 0 0 3px ${C.ink}` };
const codeS: React.CSSProperties = { background: "#0b0d0e", color: C.green, padding: "1px 6px", borderRadius: 0, fontSize: "0.9em", border: `2px solid ${C.green}`, fontFamily: BODY };

const SLIDES: Slide[] = [
  {
    kicker: "Somnia Agentathon · Agentic L1",
    title: "Hajar",
    body: (
      <p style={{ fontSize: 24, color: C.dim, maxWidth: 760, lineHeight: 1.5 }}>
        An <b style={{ color: C.ink }}>autonomous DeFi guardian</b> — a multi-tier security layer that
        stops drains and exploits, combining instant deterministic circuit breakers with
        <b style={{ color: C.cyan }}> AI risk scoring run inside Somnia validator consensus</b>.
      </p>
    ),
  },
  {
    kicker: "The problem",
    title: "DeFi bleeds billions, reactively",
    body: (
      <ul style={ulS}>
        <li>Exploits drain protocols in <b style={{ color: C.red }}>seconds</b>; audits are one-time and humans are too slow.</li>
        <li>Most "monitoring" is off-chain dashboards that <b>alert after the money is gone</b>.</li>
        <li>No standard, autonomous, on-chain breaker that <b>acts</b> — and keeps learning.</li>
      </ul>
    ),
  },
  {
    kicker: "The solution",
    title: "A circuit breaker that thinks and acts",
    body: (
      <ul style={ulS}>
        <li><b style={{ color: C.cyan }}>Synchronous</b> deterministic blocks stop blatant drains same-block.</li>
        <li><b style={{ color: C.cyan }}>Asynchronous</b> AI (validator consensus) judges the grey zone and can latch the breaker.</li>
        <li><b style={{ color: C.cyan }}>Event-driven</b> reactivity + a self-learning threat brain run 24/7, no human in the loop.</li>
        <li>Multi-tenant: <b>any</b> protocol calls <code style={codeS}>registerProtocol()</code> — protection as a service.</li>
      </ul>
    ),
  },
  {
    kicker: "How it defends",
    title: "Defense in depth — every tier live",
    body: (
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, maxWidth: 880 }}>
        {[
          ["Tier 1 · hard rule", "single-tx & velocity drain → instant revert"],
          ["Tier 1c · spot guard", "atomic price-deviation block (flash-loan)"],
          ["Tier 1d · outflow budget", "vault-wide cap catches sybil slow-drains"],
          ["Tier 2 · LLM risk", "Qwen3-30B consensus 0–100 score → latch"],
          ["Tier 2b · price oracle", "external price divergence → latch"],
          ["Tier 2c · threat intel", "scraped threat score → latch"],
          ["Tier 2d · AI remediation", "LLM is given pause() and decides to act"],
          ["Tier 3 · reactivity", "validators auto-trigger a latch, no keeper"],
          ["TVL-drop detector", "catches drains that bypass the hook"],
        ].map(([t, d]) => (
          <div key={t} style={cardS}>
            <div style={{ color: C.cyan, fontWeight: 700, fontSize: 15 }}>{t}</div>
            <div style={{ color: C.dim, fontSize: 14, marginTop: 4 }}>{d}</div>
          </div>
        ))}
      </div>
    ),
  },
  {
    kicker: "The differentiator",
    title: "It learns new exploits — and applies them",
    body: (
      <ul style={ulS}>
        <li>A self-updating loop using <b style={{ color: C.cyan }}>all three Somnia agents</b>, <b>rotating sources</b> each scan
          (rekt.news, Immunefi, a JSON index…) so it never trusts just one feed.</li>
        <li>What it learns accumulates on-chain — then <b>feeds back into the AI</b>: Hajar injects its learned
          landscape into an LLM risk read, so the AI&apos;s judgment is shaped by what it learned.</li>
        <li style={{ color: C.green }}>Live-proven, the loop closed: it learned <b>market-stress = 9</b> by consensus, then the AI scored a
          withdrawal <b>75 / 100 — informed by that learning</b>, on-chain.</li>
        <li style={{ color: C.dim, fontSize: 16 }}>Honest scope: knowledge accumulation &amp; adaptation, not model training.</li>
      </ul>
    ),
  },
  {
    kicker: "Agent-native, end to end",
    title: "Hajar uses agents — and IS an agent",
    body: (
      <ul style={ulS}>
        <li>It <b>uses</b> 4 Somnia agent capabilities (LLM number/string/tools-chat, JSON, Parse).</li>
        <li>It <b style={{ color: C.cyan }}>is</b> a registered <b>ERC-8004 Trustless Agent</b> (agentId 1) — other agents discover it via a
          <code style={codeS}>/.well-known/agent-card.json</code> and verify its on-chain identity.</li>
        <li>Trust model <code style={codeS}>crypto-economic</code> = Somnia validator consensus. Discoverable via MCP + x402-ready.</li>
      </ul>
    ),
  },
  {
    kicker: "Standards, not a one-off",
    title: "ERC-7265 · ERC-8004 · x402",
    body: (
      <ul style={ulS}>
        <li><b style={{ color: C.cyan }}>ERC-7265</b> — the DeFi Circuit Breaker standard; Hajar's outflow-budget tier IS its rate-limiter, extended with AI.</li>
        <li><b style={{ color: C.cyan }}>ERC-8004</b> — Trustless Agents (live on ETH mainnet); Hajar is a first-class on-chain agent.</li>
        <li><b style={{ color: C.cyan }}>x402</b> — agent payments; the path to Hajar-as-a-Service, paid per risk-query.</li>
      </ul>
    ),
  },
  {
    kicker: "Proof",
    title: "Live & verified on Somnia testnet",
    body: (
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, maxWidth: 860 }}>
        {[
          ["Guardian v4", "9 tiers live + Tier-3 verified (+20 blocks)"],
          ["ERC-8004 registry", "Hajar = agentId 1, verified on-chain"],
          ["Threat learner", "market-stress=10 learned by consensus"],
          ["Autonomous keeper", "24/7 cron, no human in the loop"],
          ["78 tests", "0 failing · fuzz · integration · edge"],
          ["0 mocks in prod", "every value read on-chain"],
        ].map(([t, d]) => (
          <div key={t} style={cardS}>
            <div style={{ color: C.ink, fontWeight: 700, fontSize: 16 }}>{t}</div>
            <div style={{ color: C.dim, fontSize: 14, marginTop: 4 }}>{d}</div>
          </div>
        ))}
      </div>
    ),
  },
  {
    kicker: "Why Somnia",
    title: "Only possible on an Agentic L1",
    body: (
      <ul style={ulS}>
        <li><b style={{ color: C.cyan }}>AI inside validator consensus</b> — every verdict carries receipts you can audit on-chain.</li>
        <li><b>Sub-cent fees + ~400k TPS</b> make checking <i>every</i> withdrawal economically viable.</li>
        <li><b>Reactivity</b> gives a validator-triggered latch with no keeper — a first-class primitive.</li>
      </ul>
    ),
  },
  {
    kicker: "The ask",
    title: "Protect every protocol. Get hired.",
    body: (
      <div>
        <p style={{ fontSize: 22, color: C.dim, maxWidth: 760, lineHeight: 1.5 }}>
          Hajar is production-shaped today: standards-compliant, agent-native, self-learning, and live.
          The next step is design partners and a paid Hajar-as-a-Service tier via x402.
        </p>
        <p style={{ marginTop: 28, fontSize: 18 }}>
          <a href="https://hajar-somnia-guardian.vercel.app" style={{ color: C.cyan }}>hajar-somnia-guardian.vercel.app</a>
          <span style={{ color: C.line, margin: "0 12px" }}>·</span>
          <a href="https://github.com/PugarHuda/hajar-somnia-guardian" style={{ color: C.cyan }}>GitHub</a>
        </p>
      </div>
    ),
  },
];

export default function Deck() {
  const [i, setI] = useState(0);
  const go = useCallback((d: number) => setI((p) => Math.min(SLIDES.length - 1, Math.max(0, p + d))), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight" || e.key === " " || e.key === "PageDown") go(1);
      if (e.key === "ArrowLeft" || e.key === "PageUp") go(-1);
      if (e.key === "Home") setI(0);
      if (e.key === "End") setI(SLIDES.length - 1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go]);

  const s = SLIDES[i];
  return (
    <main
      onClick={() => go(1)}
      style={{ minHeight: "100vh", background: C.bg, color: C.ink, display: "flex", flexDirection: "column",
        justifyContent: "center", padding: "6vh 8vw", fontFamily: BODY, cursor: "pointer" }}
    >
      {i === 0 && <div style={{ marginBottom: 24 }}><Logo size={96} /></div>}
      {s.kicker && <div style={{ color: C.green, letterSpacing: 1.5, textTransform: "uppercase", fontSize: 11, marginBottom: 22, fontFamily: PIX }}>{s.kicker}</div>}
      <h1 style={{ fontSize: i === 0 ? 64 : 30, margin: "0 0 28px", lineHeight: 1.4, fontFamily: PIX, color: C.ink }}>{s.title}</h1>
      <div>{s.body}</div>

      <div style={{ position: "fixed", bottom: 26, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 8 }}>
        {SLIDES.map((_, k) => (
          <button key={k} onClick={(e) => { e.stopPropagation(); setI(k); }}
            style={{ width: k === i ? 24 : 10, height: 10, borderRadius: 0, border: "none", cursor: "pointer",
              background: k === i ? C.green : "#2a3033", transition: "all .15s" }} aria-label={`slide ${k + 1}`} />
        ))}
      </div>
      <div style={{ position: "fixed", bottom: 20, right: 26, color: C.dim, fontSize: 11, fontFamily: PIX }}>{i + 1}/{SLIDES.length} · ← →</div>
    </main>
  );
}
