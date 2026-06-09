"use client";

import { useEffect, useState } from "react";
import { ADDRESSES, client, explorer, learnerAbi } from "../lib/somnia";

type Cat = { name: string; level: number; observations: number; updated: number };

export default function IntelligencePage() {
  const [cats, setCats] = useState<Cat[] | null>(null);
  const [top, setTop] = useState<{ name: string; level: number } | null>(null);
  const [at, setAt] = useState("");

  async function load() {
    try {
      const l = { address: ADDRESSES.learner as `0x${string}`, abi: learnerAbi };
      const count = (await client.readContract({ ...l, functionName: "categoryCount" })) as bigint;
      const ids = (await Promise.all(
        Array.from({ length: Number(count) }, (_, i) => client.readContract({ ...l, functionName: "categoryIds", args: [BigInt(i)] }))
      )) as `0x${string}`[];
      const recs = await Promise.all(ids.map((id) => client.readContract({ ...l, functionName: "knowledge", args: [id] })));
      const parsed = recs.map((r) => {
        const k = r as unknown as [boolean, number, bigint, number, string];
        return { name: k[4], level: k[1], observations: k[3], updated: Number(k[2]) };
      });
      const t = (await client.readContract({ ...l, functionName: "highestThreat" })) as [string, number];
      setCats(parsed);
      setTop({ name: t[0], level: t[1] });
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
      <div className="page-head">
        <h2>Self-learning threat intelligence</h2>
        <p className="sub">
          Hajar doesn&apos;t just enforce fixed rules — it <strong>keeps learning about exploits from
          the outside world</strong>. An autonomous loop uses all three Somnia agents to read security
          feeds and write what it learns into an on-chain knowledge base, so the guardian stays current
          with no human in the loop. Read live from the learner contract.
        </p>
      </div>

      <div className="statusbar" style={{ gridTemplateColumns: "1fr 1fr" }}>
        <div className="card">
          <div className="label">Highest learned threat</div>
          <div className="value">{top ? `${top.name}` : "—"}</div>
          <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 4 }}>{top ? `${top.level}/100` : ""}</div>
        </div>
        <div className="card">
          <div className="label">Categories tracked</div>
          <div className="value">{cats ? cats.length : "—"}</div>
          <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 4 }}>updated live · {at || "loading…"}</div>
        </div>
      </div>

      <div className="section-title" style={{ marginTop: 36 }}>Knowledge base · on-chain</div>
      <div className="kb">
        {!cats ? (
          <div className="feed-empty">Loading the learned knowledge base…</div>
        ) : (
          cats.map((c) => (
            <div className="kb-row" key={c.name}>
              <div className="kb-name">{c.name}</div>
              <div className="kb-bar"><div className="kb-fill" style={{ width: `${Math.max(3, c.level)}%` }} /></div>
              <div className="kb-meta">
                {c.level}/100 · {c.observations} obs
                {c.updated ? <><br />{new Date(c.updated * 1000).toLocaleDateString()}</> : <><br />never scanned</>}
              </div>
            </div>
          ))
        )}
      </div>

      <div className="callout">
        <strong>How it learns.</strong> 1) The <em>Parse Website</em> agent scrapes a security feed and
        extracts a 0–100 threat level per category. 2) The <em>JSON API</em> agent pulls a structured
        score (live-proven: <strong>market-stress = 10</strong> from the Fear &amp; Greed Index, by
        validator consensus). 3) The <em>LLM inferString</em> agent classifies an observed pattern onto
        the taxonomy. Every result is written on-chain and accumulates over time.
      </div>

      <div className="callout" style={{ background: "var(--panel)", borderColor: "var(--border)", color: "var(--muted)" }}>
        <strong style={{ color: "var(--text)" }}>Honest scope:</strong> this is real knowledge
        accumulation &amp; adaptation driven by agents — not on-chain model training (infeasible). When
        a scrape can&apos;t reach validator consensus it fails open (no record) rather than inventing
        data. The knowledge is exposed to other agents at{" "}
        <code>/api/learn</code> and informs Hajar&apos;s policy.
      </div>

      <p className="foot">
        Learner contract <a href={explorer(ADDRESSES.learner)} target="_blank" rel="noreferrer">{ADDRESSES.learner.slice(0, 10)}…</a> ·
        machine-readable at <a href="/api/learn" target="_blank" rel="noreferrer">/api/learn</a>
      </p>
    </main>
  );
}
