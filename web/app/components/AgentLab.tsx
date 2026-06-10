"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { parseEther, parseEventLogs, type Address } from "viem";
import {
  client,
  walletClient,
  connectWallet,
  ADDRESSES,
  guardianAbi,
  vaultAbi,
  learnerAbi,
  txExplorer,
} from "../lib/somnia";

type Feed = { key: string; agent: string; badge: string; detail: string; hash: string };

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const eventAbi = [
  ...guardianAbi.filter((x) => x.type === "event"),
  ...vaultAbi.filter((x) => x.type === "event"),
  ...learnerAbi.filter((x) => x.type === "event"),
];

/** Maps an on-chain event to (which agent, a badge, a human sentence). This is the proof surface:
 *  every line here is a real request to / verdict from a Somnia agent, with its receipt on-chain. */
function describe(name: string, a: Record<string, unknown>): { agent: string; badge: string; detail: string } | null {
  const n = (v: unknown) => Number(v as bigint);
  switch (name) {
    case "EscalatedToAI":
      return { agent: "LLM Inference", badge: "request", detail: `escalated withdrawal to the LLM agent → req ${a.requestId}` };
    case "AIVerdict":
      return { agent: "LLM Inference", badge: a.tripped ? "tripped" : "verdict", detail: `risk score ${a.riskScore} from ${a.validatorCount} validators${a.tripped ? " → breaker LATCHED" : " → safe"}` };
    case "PriceChecked":
      return { agent: "JSON API", badge: "request", detail: `price sanity check sent → req ${a.requestId}` };
    case "PriceVerdict":
      return { agent: "JSON API", badge: a.alarm ? "tripped" : "verdict", detail: `market ${a.marketPrice} vs ref ${a.referencePrice} · ${n(a.divergenceBps) / 100}% divergence${a.alarm ? " → LATCHED" : ""}` };
    case "ThreatScanned":
      return { agent: "Parse / JSON", badge: "request", detail: `threat scan sent → req ${a.requestId}` };
    case "ThreatVerdict":
      return { agent: "Parse / JSON", badge: a.alarm ? "tripped" : "verdict", detail: `threat score ${a.threatScore}${a.alarm ? " → LATCHED" : ""}` };
    case "RemediationRequested":
      return { agent: "LLM tools-chat", badge: "request", detail: `autonomous remediation offered pause() → req ${a.requestId}` };
    case "RemediationVerdict":
      return { agent: "LLM tools-chat", badge: a.acted ? "tripped" : "verdict", detail: `AI decided: "${a.finishReason || "stop"}"${a.acted ? " → AI PAUSED the protocol" : " → AI judged safe, no action"}` };
    case "LearnRequested":
      return { agent: "Threat Learner", badge: "request", detail: `learning a category → req ${a.requestId}` };
    case "Learned":
      return { agent: "Threat Learner", badge: "learned", detail: `learned threat level ${a.level} from ${a.validatorCount} validators (obs #${a.observations})` };
    case "Classified":
      return { agent: "LLM inferString", badge: "learned", detail: `classified pattern as "${a.name}" (obs #${a.observations})` };
    case "AssessRequested":
      return { agent: "LLM + learned", badge: "request", detail: `AI risk read, informed by learned context: "${a.landscape}"` };
    case "AssessVerdict":
      return { agent: "LLM + learned", badge: n(a.risk) >= 70 ? "tripped" : "verdict", detail: `AI risk ${a.risk}/100 — shaped by what Hajar learned, from ${a.validatorCount} validators` };
    default:
      return null;
  }
}

export default function AgentLab() {
  const [account, setAccount] = useState<Address | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ kind: "ok" | "err" | "info"; text: string } | null>(null);
  const [feed, setFeed] = useState<Feed[]>([]);
  const startBlock = useRef<bigint | null>(null);
  const note = (kind: "ok" | "err" | "info", text: string) => setMsg({ kind, text });

  const onConnect = async () => {
    try { setBusy("connect"); const acc = await connectWallet(); setAccount(acc); note("ok", `Connected ${short(acc)}`); }
    catch (e: unknown) { note("err", (e as Error)?.message ?? "connect failed"); }
    finally { setBusy(null); }
  };

  // PUBLIC trigger: a 25%-of-TVL withdrawal sits in the grey zone, so the guardian auto-escalates
  // to the Somnia LLM agent. Anyone can fire this and watch the validator verdict arrive below.
  const triggerAI = async () => {
    if (!account) return note("err", "Connect your wallet first.");
    try {
      setBusy("ai");
      const tvl = (await client.readContract({ address: ADDRESSES.vault as Address, abi: vaultAbi, functionName: "totalAssets" })) as bigint;
      const grey = (tvl * 25n) / 100n;
      if (grey === 0n) return note("err", "Vault TVL is 0 — deposit on the Defense page first.");
      note("info", "Grey-zone withdrawal sent → the guardian is escalating to the Somnia LLM agent. Watch the feed: EscalatedToAI → AIVerdict (validator consensus) lands in ~20–60s.");
      const hash = await walletClient().writeContract({ account, address: ADDRESSES.vault as Address, abi: vaultAbi as unknown as [], functionName: "withdraw", args: [grey] });
      await client.waitForTransactionReceipt({ hash });
      note("ok", "Escalated ✓ — the LLM agent is now running across the validator subcommittee. Verdict incoming below.");
    } catch (e: unknown) {
      note("err", (e as { shortMessage?: string; message?: string })?.shortMessage ?? (e as Error)?.message ?? "failed");
    } finally { setBusy(null); }
  };

  // live agent-activity feed across the guardian + the learner (accumulates from page load).
  useEffect(() => {
    let stop = false;
    (async () => { startBlock.current = await client.getBlockNumber(); })();
    const poll = async () => {
      try {
        const latest = await client.getBlockNumber();
        const from = startBlock.current && latest - startBlock.current < 900n ? startBlock.current : latest - 900n;
        const logs = await client.getLogs({
          address: [ADDRESSES.guardian as Address, ADDRESSES.vault as Address, ADDRESSES.learner as Address],
          fromBlock: from, toBlock: latest,
        });
        const parsed = parseEventLogs({ abi: eventAbi as unknown as [], logs });
        const items: Feed[] = [];
        for (const p of parsed as unknown as { eventName: string; args: Record<string, unknown>; transactionHash: string; logIndex: number }[]) {
          const d = describe(p.eventName, p.args);
          if (d) items.push({ key: `${p.transactionHash}-${p.logIndex}`, agent: d.agent, badge: d.badge, detail: d.detail, hash: p.transactionHash });
        }
        if (!stop && items.length) {
          setFeed((prev) => {
            const seen = new Set(prev.map((x) => x.key));
            const fresh = items.filter((x) => !seen.has(x.key));
            return fresh.length ? [...fresh.reverse(), ...prev].slice(0, 40) : prev;
          });
        }
      } catch { /* RPC hiccup — next tick */ }
    };
    poll();
    const t = setInterval(poll, 6000);
    return () => { stop = true; clearInterval(t); };
  }, []);

  const badgeClass = (b: string) => (b === "tripped" ? "red" : b === "request" ? "gray" : b === "learned" ? "green" : "cyan");

  return (
    <div className="console">
      <div className="console-head">
        <div className="acct">
          {account ? <><span className="dot green" /> {short(account)}</> : <><span className="dot gray" /> wallet not connected</>}
        </div>
      </div>
      <div className="row wrap">
        {!account ? (
          <button className="btn primary" disabled={!!busy} onClick={onConnect}>Connect wallet</button>
        ) : (
          <button className="btn primary" disabled={busy === "ai"} onClick={triggerAI}>🤖 Make an AI agent run now (25% TVL)</button>
        )}
        <span className="unit">↳ a grey-zone withdrawal escalates to the Somnia LLM agent — fully public, no admin</span>
      </div>
      {msg && <div className={`msg ${msg.kind}`}>{msg.text}</div>}

      <div className="feed">
        <div className="feed-title">Live agent activity · guardian + learner · validator-verified on-chain</div>
        <div className="callout" style={{ marginTop: 0, marginBottom: 14, fontSize: 14 }}>
          <strong>What you&apos;re watching:</strong> a{" "}
          <span className="badge gray">request</span> is Hajar asking a Somnia agent (the guardian pays
          the validators); a <span className="badge cyan">verdict</span> is the consensus answer
          coming back on-chain; <span className="badge green">learned</span> means the threat brain
          recorded new intel; <span className="badge red">tripped</span> means the AI latched the
          breaker. Click any row to open its transaction.
        </div>
        {feed.length === 0 ? (
          <div className="feed-empty">Watching the chain… trigger an agent above, or wait for the autonomous keeper. Every line below is a real Somnia-agent request or a consensus verdict, linked to its tx.</div>
        ) : (
          feed.map((f) => (
            <a key={f.key} className="feed-row" href={txExplorer(f.hash)} target="_blank" rel="noreferrer">
              <span className={`badge ${badgeClass(f.badge)}`}>{f.badge}</span>
              <span className="chip">{f.agent}</span>
              <span className="feed-detail">{f.detail}</span>
            </a>
          ))
        )}
      </div>
    </div>
  );
}
