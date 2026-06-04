"use client";

import { useEffect, useState } from "react";
import { formatEther } from "viem";
import { client, ADDRESSES, explorer, guardianAbi, vaultAbi } from "./lib/somnia";
import DemoConsole from "./components/DemoConsole";

type State = {
  paused: boolean;
  tvl: bigint;
  hardBps: bigint;
  rapidBps: bigint;
  greyBps: bigint;
  risk: bigint;
  agentId: bigint;
  jsonId: bigint;
  parseId: bigint;
};

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

export default function Home() {
  const [s, setS] = useState<State | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [at, setAt] = useState<string>("");

  async function load() {
    try {
      const g = { address: ADDRESSES.guardian as `0x${string}`, abi: guardianAbi };
      const vaultArg = [ADDRESSES.vault as `0x${string}`] as const;
      const [paused, proto, agentId, jsonId, parseId, tvl] = await Promise.all([
        client.readContract({ ...g, functionName: "paused", args: vaultArg }),
        client.readContract({ ...g, functionName: "protocols", args: vaultArg }),
        client.readContract({ ...g, functionName: "llmAgentId" }),
        client.readContract({ ...g, functionName: "jsonAgentId" }),
        client.readContract({ ...g, functionName: "parseAgentId" }),
        client.readContract({
          address: ADDRESSES.vault as `0x${string}`,
          abi: vaultAbi,
          functionName: "totalAssets",
        }),
      ]);
      const p = proto as unknown as {
        hardBps: bigint; rapidBps: bigint; greyBps: bigint; risk: bigint;
      };
      setS({ paused: paused as boolean, hardBps: p.hardBps, rapidBps: p.rapidBps, greyBps: p.greyBps, risk: p.risk, agentId: agentId as bigint, jsonId: jsonId as bigint, parseId: parseId as bigint, tvl: tvl as bigint });
      setErr(null);
      setAt(new Date().toLocaleTimeString());
    } catch (e: any) {
      setErr(e?.shortMessage || e?.message || "read failed");
    }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 12000);
    return () => clearInterval(t);
  }, []);

  const pct = (bps?: bigint) => (bps ? `${Number(bps) / 100}%` : "—");

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
        A three-tier security layer that protects DeFi protocols from drains and exploits —
        combining instant deterministic circuit breakers with{" "}
        <strong>consensus-verified AI risk scoring</strong> run by Somnia validators. Status
        below is read live from the Shannon testnet.
      </p>

      <div className="statusbar">
        <div className="card">
          <div className="label">Circuit breaker</div>
          <div className="value">
            {!s && !err ? (
              <span className="pill">
                <span className="dot gray" /> loading…
              </span>
            ) : s?.paused ? (
              <span className="pill" style={{ color: "var(--red)" }}>
                <span className="dot red" /> PAUSED
              </span>
            ) : (
              <span className="pill" style={{ color: "var(--green)" }}>
                <span className="dot green" /> ACTIVE
              </span>
            )}
          </div>
        </div>
        <div className="card">
          <div className="label">Protected TVL</div>
          <div className="value">{s ? `${formatEther(s.tvl)} STT` : "—"}</div>
        </div>
        <div className="card">
          <div className="label">Somnia AI agents</div>
          <div className="value">
            {s ? (
              <span title={`LLM ${s.agentId} · JSON ${s.jsonId} · Parse ${s.parseId}`}>
                3 wired
                <span style={{ fontSize: 12, color: "var(--muted)", marginLeft: 6 }}>LLM · JSON · Parse</span>
              </span>
            ) : "—"}
          </div>
        </div>
      </div>
      {err && (
        <p className="refresh" style={{ color: "var(--red)" }}>
          RPC error: {err}
        </p>
      )}
      {at && <p className="refresh">Live from Somnia testnet · last update {at} · auto-refresh 12s</p>}

      <DemoConsole />

      <div className="section-title">How it defends — three tiers</div>
      <div className="tiers">
        <div className="tier t1">
          <div className="num">1</div>
          <div>
            <h3>Deterministic hard rule</h3>
            <div className="meta">synchronous · same block · no AI · threshold {pct(s?.hardBps)} of TVL</div>
            <p>
              Every withdrawal is checked in-line. A single drain ≥ {pct(s?.hardBps)} of TVL, or a
              looped <em>rapid drain</em> ≥ {pct(s?.rapidBps)} within the velocity window, is
              reverted instantly — no waiting on anything off-chain.
            </p>
          </div>
        </div>
        <div className="tier t2">
          <div className="num">2</div>
          <div>
            <h3>Consensus-verified AI judgment</h3>
            <div className="meta">async · Somnia LLM Inference agent · grey zone ≥ {pct(s?.greyBps)}</div>
            <p>
              Ambiguous activity is escalated to Somnia&apos;s deterministic LLM agent. Validators
              run the model and reach consensus on a 0–100 risk score; ≥ {s ? s.risk.toString() : "—"}{" "}
              latches the breaker. The verdict carries a receipt and N validator signatures — auditable on-chain.
            </p>
            <p className="subagents">
              <strong>+ three more agent paths on the same consensus callback:</strong> a{" "}
              <em>JSON API</em> price-oracle sanity check (oracle-manipulation / depeg), a{" "}
              <em>Parse Website</em> self-updating threat-intel feed (learns new exploits), and{" "}
              <strong>Tier-2d autonomous remediation</strong> — the LLM is given a{" "}
              <code>pause()</code> tool via <em>inferToolsChat</em> and <em>decides whether to act</em>,
              not just score. Verified live: the agent reasoned on-chain and correctly declined to
              pause a healthy vault.
            </p>
          </div>
        </div>
        <div className="tier t3">
          <div className="num">3</div>
          <div>
            <h3>Reactivity latch</h3>
            <div className="meta">event-driven · validator-triggered · separate execution</div>
            <p>
              A Somnia Reactivity subscription fires on the vault&apos;s withdrawal event and can
              latch the circuit breaker persistently — the one thing the synchronous Tier-1 path
              cannot do, because reverting its trigger tx would roll the latch back.
            </p>
          </div>
        </div>
      </div>

      <div className="section-title">Deployed on Somnia Shannon testnet</div>
      <div className="addrs">
        <div className="addr">
          <span className="k">HajarGuardian</span>
          <a href={explorer(ADDRESSES.guardian)} target="_blank" rel="noreferrer">{short(ADDRESSES.guardian)}</a>
        </div>
        <div className="addr">
          <span className="k">ProtectedVault</span>
          <a href={explorer(ADDRESSES.vault)} target="_blank" rel="noreferrer">{short(ADDRESSES.vault)}</a>
        </div>
        <div className="addr">
          <span className="k">HajarReactiveSubscriber (Tier-3)</span>
          <a href={explorer(ADDRESSES.monitor)} target="_blank" rel="noreferrer">{short(ADDRESSES.monitor)}</a>
        </div>
        <div className="addr">
          <span className="k">Somnia Agents platform</span>
          <a href={explorer(ADDRESSES.platform)} target="_blank" rel="noreferrer">{short(ADDRESSES.platform)}</a>
        </div>
      </div>

      <p className="foot">
        Built for the Somnia Agentathon ·{" "}
        <a href="https://github.com/PugarHuda/hajar-somnia-guardian" target="_blank" rel="noreferrer">
          GitHub repository
        </a>{" "}
        · chain 50312 · STT testnet
      </p>
    </main>
  );
}
