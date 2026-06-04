"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { parseEther, formatEther, parseEventLogs, type Address } from "viem";
import {
  client,
  walletClient,
  connectWallet,
  getProvider,
  ADDRESSES,
  guardianAbi,
  vaultAbi,
  txExplorer,
} from "../lib/somnia";

type Feed = { key: string; name: string; detail: string; hash: string };

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const eventAbi = [...guardianAbi, ...vaultAbi].filter((x) => x.type === "event");

export default function DemoConsole() {
  const [account, setAccount] = useState<Address | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [stt, setStt] = useState<string>("—");
  const [vaultBal, setVaultBal] = useState<string>("—");
  const [amount, setAmount] = useState<string>("0.01");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ kind: "ok" | "err" | "info"; text: string } | null>(null);
  const [feed, setFeed] = useState<Feed[]>([]);
  const startBlock = useRef<bigint | null>(null);

  const note = (kind: "ok" | "err" | "info", text: string) => setMsg({ kind, text });

  const refreshBalances = useCallback(async (acc: Address) => {
    const [bal, vb, proto] = await Promise.all([
      client.getBalance({ address: acc }),
      client.readContract({ address: ADDRESSES.vault as Address, abi: vaultAbi, functionName: "balanceOf", args: [acc] }),
      client.readContract({ address: ADDRESSES.guardian as Address, abi: guardianAbi, functionName: "protocols", args: [ADDRESSES.vault as Address] }),
    ]);
    setStt(Number(formatEther(bal)).toFixed(4));
    setVaultBal(Number(formatEther(vb as bigint)).toFixed(4));
    const admin = (proto as unknown as { admin: string }).admin;
    setIsAdmin(admin.toLowerCase() === acc.toLowerCase());
  }, []);

  const onConnect = async () => {
    try {
      setBusy("connect");
      const acc = await connectWallet();
      setAccount(acc);
      await refreshBalances(acc);
      note("ok", `Connected ${short(acc)}`);
    } catch (e: unknown) {
      note("err", (e as Error)?.message ?? "connect failed");
    } finally {
      setBusy(null);
    }
  };

  // generic write helper
  const send = useCallback(
    async (
      label: string,
      address: Address,
      abi: readonly unknown[],
      functionName: string,
      args: unknown[],
      value?: bigint,
    ) => {
      if (!account) return note("err", "Connect your wallet first.");
      try {
        setBusy(label);
        note("info", `${label}: confirm in wallet…`);
        const hash = await walletClient().writeContract({
          account,
          address,
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          abi: abi as any,
          functionName,
          args,
          value,
        });
        note("info", `${label}: pending…`);
        const rcpt = await client.waitForTransactionReceipt({ hash });
        if (rcpt.status === "success") note("ok", `${label}: success ✓`);
        else note("err", `${label}: reverted — guardian blocked it (that's the point!)`);
        await refreshBalances(account);
      } catch (e: unknown) {
        const m = (e as { shortMessage?: string; message?: string })?.shortMessage ?? (e as Error)?.message ?? "failed";
        // a revert here usually means the guardian did its job
        note("err", `${label}: ${m.slice(0, 140)}`);
      } finally {
        setBusy(null);
      }
    },
    [account, refreshBalances],
  );

  const tvlNow = async () =>
    (await client.readContract({ address: ADDRESSES.vault as Address, abi: vaultAbi, functionName: "totalAssets" })) as bigint;

  const doDeposit = () => send("Deposit", ADDRESSES.vault as Address, vaultAbi, "deposit", [], parseEther(amount || "0"));
  const doWithdraw = () => send("Withdraw", ADDRESSES.vault as Address, vaultAbi, "withdraw", [parseEther(amount || "0")]);
  const doDrain = async () => {
    const tvl = await tvlNow();
    const big = (tvl * 80n) / 100n; // 80% of TVL -> trips Tier-1
    if (big === 0n) return note("err", "Vault TVL is 0 — deposit first.");
    send("Try Drain (80% TVL)", ADDRESSES.vault as Address, vaultAbi, "withdraw", [big]);
  };
  // Grey-zone withdrawal (≈25% of TVL) sits between greyBps (15%) and hardBps (40%), so the
  // guardian auto-escalates to the Somnia LLM agent — a fully PUBLIC way to trigger Tier-2 AI
  // (no admin needed). Watch EscalatedToAI → AIVerdict stream into the feed below.
  const doEscalate = async () => {
    const tvl = await tvlNow();
    const grey = (tvl * 25n) / 100n;
    if (grey === 0n) return note("err", "Vault TVL is 0 — deposit first.");
    note("info", "Grey-zone withdrawal → guardian escalates to Somnia AI (watch the feed)…");
    send("Trigger AI (25% TVL)", ADDRESSES.vault as Address, vaultAbi, "withdraw", [grey]);
  };
  const doRiskCheck = () => send("AI Risk Check", ADDRESSES.guardian as Address, guardianAbi, "requestRiskCheck", [ADDRESSES.vault]);
  const doReset = () => send("Reset Breaker", ADDRESSES.guardian as Address, guardianAbi, "resetBreaker", [ADDRESSES.vault]);

  // live event feed (from page load onward)
  useEffect(() => {
    let stop = false;
    (async () => {
      startBlock.current = await client.getBlockNumber();
    })();
    const poll = async () => {
      try {
        const latest = await client.getBlockNumber();
        const from = startBlock.current && latest - startBlock.current < 1500n ? startBlock.current : latest - 1500n;
        const logs = await client.getLogs({
          address: [ADDRESSES.guardian as Address, ADDRESSES.vault as Address],
          fromBlock: from,
          toBlock: latest,
        });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const parsed = parseEventLogs({ abi: eventAbi as any, logs });
        const items: Feed[] = parsed.map((p: any) => ({
          key: `${p.transactionHash}-${p.logIndex}`,
          name: p.eventName as string,
          detail: describe(p.eventName as string, p.args),
          hash: p.transactionHash as string,
        }));
        if (!stop && items.length) {
          setFeed((prev) => {
            const seen = new Set(prev.map((x) => x.key));
            const fresh = items.filter((x) => !seen.has(x.key));
            return [...fresh.reverse(), ...prev].slice(0, 14);
          });
        }
      } catch {
        /* transient RPC error — ignore */
      }
    };
    const t = setInterval(poll, 9000);
    poll();
    return () => {
      stop = true;
      clearInterval(t);
    };
  }, []);

  const hasWallet = typeof window !== "undefined" && !!getProvider();

  return (
    <>
      <div className="section-title">Try it live — interactive demo</div>
      <div className="console">
        <div className="console-head">
          {account ? (
            <div className="acct">
              <span className="dot green" /> {short(account)} · {stt} STT · vault {vaultBal} STT
            </div>
          ) : (
            <button className="btn primary" disabled={busy === "connect" || !hasWallet} onClick={onConnect}>
              {hasWallet ? (busy === "connect" ? "Connecting…" : "Connect Wallet") : "Install MetaMask"}
            </button>
          )}
        </div>

        <div className="row">
          <input className="inp" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.01" inputMode="decimal" />
          <span className="unit">STT</span>
          <button className="btn" disabled={!!busy} onClick={doDeposit}>Deposit</button>
          <button className="btn" disabled={!!busy} onClick={doWithdraw}>Withdraw</button>
        </div>

        <div className="row wrap">
          <button className="btn danger" disabled={!!busy} onClick={doDrain}>⚔️ Try Drain (80% TVL)</button>
          <button className="btn primary" disabled={!!busy} onClick={doEscalate} title="Public — anyone can trigger the Somnia LLM agent">🤖 Trigger AI (25% TVL)</button>
          <button className="btn" disabled={!!busy || (!!account && !isAdmin)} onClick={doRiskCheck} title={!isAdmin ? "protocol admin only" : ""}>🛰️ Proactive Check{account && !isAdmin ? " (admin)" : ""}</button>
          <button className="btn ghost" disabled={!!busy || (!!account && !isAdmin)} onClick={doReset} title={!isAdmin ? "protocol admin only" : ""}>♻️ Reset Breaker{account && !isAdmin ? " (admin)" : ""}</button>
        </div>

        {msg && <div className={`msg ${msg.kind}`}>{msg.text}</div>}

        <div className="feed">
          <div className="feed-title">Live on-chain events</div>
          {feed.length === 0 ? (
            <div className="feed-empty">No events yet — interact above and watch them stream in.</div>
          ) : (
            feed.map((f) => (
              <a key={f.key} className="feed-row" href={txExplorer(f.hash)} target="_blank" rel="noreferrer">
                <span className={`badge ${badgeKind(f.name)}`}>{f.name}</span>
                <span className="feed-detail">{f.detail}</span>
              </a>
            ))
          )}
        </div>
      </div>
    </>
  );
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function describe(name: string, a: any): string {
  try {
    switch (name) {
      case "Deposited": return `${short(a.user)} deposited ${fmt(a.amount)} STT`;
      case "Withdrawn": return `${short(a.user)} withdrew ${fmt(a.amount)} STT`;
      case "WithdrawalBlocked": return `blocked ${short(a.user)} (${a.reason})`;
      case "HardBlock": return `Tier-1 blocked ${short(a.user)} — ${Number(a.bps) / 100}% of TVL`;
      case "EscalatedToAI": return `escalated to Somnia AI (req ${a.requestId})`;
      case "AIVerdict": return `AI score ${a.riskScore} from ${a.validatorCount} validators${a.tripped ? " → TRIPPED" : ""}`;
      case "CircuitBreakerTripped": return `breaker tripped (${a.reason})`;
      case "CircuitBreakerReset": return `breaker reset → ACTIVE`;
      default: return name;
    }
  } catch {
    return name;
  }
}
const fmt = (w: bigint) => Number(formatEther(w)).toFixed(3);
function badgeKind(name: string): string {
  if (name.includes("Block") || name.includes("Tripped")) return "red";
  if (name.includes("Reset") || name === "Deposited") return "green";
  if (name.includes("AI") || name.includes("Escalated")) return "cyan";
  return "gray";
}
