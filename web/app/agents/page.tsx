"use client";

import { useEffect, useState } from "react";
import { ADDRESSES, client, explorer, guardianAbi, learnerAbi } from "../lib/somnia";
import AgentLab from "../components/AgentLab";

type Live = { llm: string; json: string; parse: string; topThreat: string; topLevel: number };

const AGENTS = [
  {
    name: "LLM Inference",
    sub: "Qwen3-30B · deterministic",
    id: "12847293847561029384",
    cost: "0.07 STT / validator",
    methods: ["inferNumber", "inferString", "inferToolsChat"],
    used: "Tier-2 risk scoring (0–100), Tier-2d autonomous remediation (the AI is given pause() and decides to act), and exploit-pattern classification in the learner.",
  },
  {
    name: "JSON API Request",
    sub: "on-chain oracle primitive",
    id: "13174292974160097713",
    cost: "0.03 STT / validator",
    methods: ["fetchUint", "fetchString", "fetchBool"],
    used: "Tier-2b price-oracle sanity (oracle-manipulation / depeg) and the learner's structured threat feeds. Live-proven: learned market-stress = 10 from the Fear & Greed Index.",
  },
  {
    name: "Parse Website",
    sub: "scrape + reason",
    id: "12875401142070969085",
    cost: "0.10 STT / validator",
    methods: ["ExtractANumber"],
    used: "Tier-2c self-updating threat intel and the learner — scrapes security feeds (rekt.news, advisories) for a 0–100 threat level per exploit category.",
  },
];

export default function AgentsPage() {
  const [s, setS] = useState<Live | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const g = { address: ADDRESSES.guardian as `0x${string}`, abi: guardianAbi };
        const [llm, json, parse, top] = await Promise.all([
          client.readContract({ ...g, functionName: "llmAgentId" }),
          client.readContract({ ...g, functionName: "jsonAgentId" }),
          client.readContract({ ...g, functionName: "parseAgentId" }),
          client.readContract({ address: ADDRESSES.learner as `0x${string}`, abi: learnerAbi, functionName: "highestThreat" }),
        ]);
        const t = top as [string, number];
        setS({ llm: (llm as bigint).toString(), json: (json as bigint).toString(), parse: (parse as bigint).toString(), topThreat: t[0], topLevel: t[1] });
      } catch { /* ignore */ }
    })();
  }, []);

  const wired = (id: string, expected: string) => s && id === expected;

  return (
    <main className="wrap">
      <div className="page-head">
        <h2>The AI agents — watch them work</h2>
        <p className="sub">
          Hajar runs its judgment on <strong>Somnia&apos;s on-chain AI agents</strong>. Each request is
          executed by a subcommittee of validators that reach <strong>consensus</strong>; the verdict
          comes back to the guardian with a receipt and N validator signatures — fully auditable.
          Below: the three agents, then a live console where you can fire one yourself and watch the
          consensus verdict land on-chain.
        </p>
      </div>

      <div className="agent-grid">
        {AGENTS.map((a) => {
          const live = s && (a.id === s.llm || a.id === s.json || a.id === s.parse);
          return (
            <div className="agent-card" key={a.id}>
              <div className="an">{a.name}</div>
              <div style={{ fontSize: 12, color: "var(--muted)" }}>{a.sub}</div>
              <div className="ai">id {a.id}</div>
              <div className="am">
                <span className={`chip ${live ? "live" : ""}`}>{live ? "● wired on v4" : "agent"}</span>
                <span className="chip">{a.cost}</span>
              </div>
              <div className="am">{a.methods.map((m) => <span className="chip" key={m}>{m}()</span>)}</div>
              <div className="ad">{a.used}</div>
            </div>
          );
        })}
      </div>

      <div className="section-title" style={{ marginTop: 36 }}>Fire an agent live</div>
      <AgentLab />

      <div className="callout">
        <strong>Proof it reaches consensus.</strong> Hajar&apos;s self-learning engine already ran the
        JSON API agent across the validator subcommittee and wrote the result on-chain:
        the highest learned threat right now is{" "}
        <strong>{s ? `${s.topThreat} = ${s.topLevel}/100` : "…"}</strong>. That number was produced by
        validator consensus, not by this website. See the full knowledge base on the{" "}
        <a href="/intelligence" style={{ color: "var(--accent-2)" }}>Intelligence</a> page.
      </div>

      <div className="section-title" style={{ marginTop: 36 }}>How a verdict is produced</div>
      <div className="tiers">
        <div className="tier t2">
          <div className="num">1</div>
          <div>
            <h3>Request</h3>
            <p>The guardian calls <code>platform.createRequest()</code> with the agent id, a callback, and an ABI-encoded payload (e.g. <code>inferNumber(prompt, …)</code>). It pays the validator subcommittee in STT.</p>
          </div>
        </div>
        <div className="tier t2">
          <div className="num">2</div>
          <div>
            <h3>Consensus</h3>
            <p>A subcommittee of Somnia validators each run the agent (deterministic Qwen3-30B / a JSON fetch / a scrape) and submit signed responses. The platform aggregates them into a consensus result with a receipt per validator.</p>
          </div>
        </div>
        <div className="tier t2">
          <div className="num">3</div>
          <div>
            <h3>Callback &amp; act</h3>
            <p>The platform invokes <code>handleResponse()</code> on the guardian, which checks <code>msg.sender == platform</code>, decodes the result, and acts — latching the breaker, recording learned intel, or (Tier-2d) honoring the AI&apos;s <code>pause()</code> decision.</p>
          </div>
        </div>
      </div>

      <p className="foot">
        Agents browsable at <a href="https://agents.somnia.network" target="_blank" rel="noreferrer">agents.somnia.network</a> ·
        platform <a href={explorer(ADDRESSES.platform)} target="_blank" rel="noreferrer">{ADDRESSES.platform.slice(0, 10)}…</a> ·
        guardian v4 <a href={explorer(ADDRESSES.guardian)} target="_blank" rel="noreferrer">{ADDRESSES.guardian.slice(0, 10)}…</a>
      </p>
    </main>
  );
}
