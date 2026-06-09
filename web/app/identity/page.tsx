"use client";

import { useEffect, useState } from "react";
import { ADDRESSES, REGISTRY, client, explorer, registryAbi } from "../lib/somnia";

type Id = { owner: string; uri: string; total: number };

export default function IdentityPage() {
  const [id, setId] = useState<Id | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const r = { address: REGISTRY.address as `0x${string}`, abi: registryAbi };
        const [owner, uri, total] = await Promise.all([
          client.readContract({ ...r, functionName: "ownerOf", args: [BigInt(REGISTRY.agentId)] }),
          client.readContract({ ...r, functionName: "tokenURI", args: [BigInt(REGISTRY.agentId)] }),
          client.readContract({ ...r, functionName: "totalAgents" }),
        ]);
        setId({ owner: owner as string, uri: uri as string, total: Number(total as bigint) });
      } catch { /* ignore */ }
    })();
  }, []);

  return (
    <main className="wrap">
      <div className="page-head">
        <h2>Agent identity &amp; standards</h2>
        <p className="sub">
          Hajar isn&apos;t just a contract you call — it&apos;s a <strong>discoverable on-chain
          agent</strong>. It registers as an <strong>ERC-8004 Trustless Agent</strong> so other agents
          can find it, read what it does, and verify its identity with no pre-existing trust. It also
          composes the emerging DeFi-security and agent-payment standards.
        </p>
      </div>

      <div className="statusbar" style={{ gridTemplateColumns: "1fr 1fr 1fr" }}>
        <div className="card">
          <div className="label">ERC-8004 agentId</div>
          <div className="value">#{REGISTRY.agentId}</div>
        </div>
        <div className="card">
          <div className="label">Owner (verified on-chain)</div>
          <div className="value" style={{ fontSize: 15, fontFamily: "ui-monospace, monospace" }}>{id ? `${id.owner.slice(0, 10)}…${id.owner.slice(-6)}` : "—"}</div>
        </div>
        <div className="card">
          <div className="label">Agents in registry</div>
          <div className="value">{id ? id.total : "—"}</div>
        </div>
      </div>

      <div className="callout">
        <strong>Verify it yourself.</strong> The registry&apos;s <code>tokenURI({REGISTRY.agentId})</code> resolves to Hajar&apos;s
        live agent card:{" "}
        <a href={id?.uri || "/.well-known/agent-card.json"} target="_blank" rel="noreferrer" style={{ color: "var(--accent-2)" }}>
          {id?.uri ? id.uri.replace("https://", "") : "/.well-known/agent-card.json"}
        </a>. An agent that finds the card can read its endpoints (MCP, state, threat-intel), its
        trust model, and the on-chain <code>registrations</code> pointer — then verify the owner against the registry.
      </div>

      <div className="section-title" style={{ marginTop: 36 }}>Standards it composes</div>
      <div className="tiers">
        <div className="tier t2">
          <div className="num" style={{ fontSize: 13 }}>8004</div>
          <div>
            <h3>ERC-8004 · Trustless Agents</h3>
            <div className="meta">live on Ethereum mainnet since 29 Jan 2026 · identity / reputation / validation</div>
            <p>Hajar is registered with a portable ERC-721 identity + agent card. <code>supportedTrust: [&quot;reputation&quot;, &quot;crypto-economic&quot;]</code> — where crypto-economic trust <em>is</em> Somnia validator consensus.</p>
          </div>
        </div>
        <div className="tier t1">
          <div className="num" style={{ fontSize: 13 }}>7265</div>
          <div>
            <h3>ERC-7265 · Circuit Breaker</h3>
            <div className="meta">the DeFi rate-limiter standard</div>
            <p>Hajar&apos;s vault-wide outflow-budget tier <em>is</em> the ERC-7265 rate-limiter — a temporary halt on protocol outflows past a metric threshold — extended with validator-consensus AI on the grey zone.</p>
          </div>
        </div>
        <div className="tier t3">
          <div className="num" style={{ fontSize: 13 }}>x402</div>
          <div>
            <h3>x402 · Agent payments</h3>
            <div className="meta">HTTP-native machine-to-machine payments</div>
            <p>The agent card carries the <code>x402Support</code> flag — the path to Hajar-as-a-Service, where a protocol&apos;s agent pays per risk-query with no human in the loop.</p>
          </div>
        </div>
      </div>

      <div className="section-title" style={{ marginTop: 36 }}>Discovery surface</div>
      <div className="addrs">
        <div className="addr"><span className="k">ERC-8004 registry</span><a href={explorer(REGISTRY.address)} target="_blank" rel="noreferrer">{REGISTRY.address.slice(0, 10)}…{REGISTRY.address.slice(-6)}</a></div>
        <div className="addr"><span className="k">Agent card (ERC-8004)</span><a href="/.well-known/agent-card.json" target="_blank" rel="noreferrer">/.well-known/agent-card.json</a></div>
        <div className="addr"><span className="k">MCP tool catalog</span><a href="/api/mcp" target="_blank" rel="noreferrer">/api/mcp</a></div>
        <div className="addr"><span className="k">Live state (machine-readable)</span><a href="/api/state" target="_blank" rel="noreferrer">/api/state</a></div>
        <div className="addr"><span className="k">Threat intel (machine-readable)</span><a href="/api/learn" target="_blank" rel="noreferrer">/api/learn</a></div>
      </div>
    </main>
  );
}
