# Hajar — Demo Video Script (2–5 min)

Target: ~3 minutes. Record screen at 1080p+. Live site:
https://hajar-somnia-guardian.vercel.app · Explorer: https://shannon-explorer.somnia.network

Have ready before recording:
- Wallet (MetaMask) on Somnia Shannon testnet (chainId 50312) with a few STT.
- The guardian funded with STT (so Tier-2 escalations actually pay validators).
- A second browser tab open on the Shannon explorer for the guardian address.

---

## Shot 0 — Hook (0:00–0:20)
> "DeFi loses billions to exploits every year, and today's defenses react *after* the drain,
> off-chain, with one trusted party deciding. Meet **Hajar** — an autonomous, on-chain DeFi
> guardian where the AI risk verdict is reached by **Somnia validator consensus**."

On screen: the live dashboard. Point at the green **ACTIVE** circuit-breaker pill and
**Protected TVL** read live from the testnet.

## Shot 1 — The architecture (0:20–0:50)
Scroll to "How it defends — three tiers."
> "Three tiers. Tier 1 is a synchronous deterministic rule that reverts blatant drains in the
> same block. Tier 2 escalates grey-zone activity to Somnia's LLM Inference agent — validators
> run Qwen3-30B and reach consensus on a 0–100 risk score. Plus two more Somnia agents: a JSON
> API price-oracle sanity check and a Parse-Website threat-intel feed. And Tier 3 is a real
> validator-triggered Reactivity subscription."

## Shot 2 — Tier 1, instant block (0:50–1:20)
Connect wallet → **Deposit** 0.01 STT (show vault balance update).
Click **⚔️ Try Drain (80% TVL)**.
> "An 80%-of-TVL withdrawal is a blatant drain. Tier 1 reverts it in the same block — no waiting
> on anything off-chain."

On screen: the red **WithdrawalBlocked / HardBlock** event streams into the live feed. Click it
through to the explorer tx.

## Shot 3 — Tier 2, AI by validator consensus (1:20–2:20) ★ the differentiator
Click **🤖 Trigger AI (25% TVL)**.
> "A 25% withdrawal is ambiguous — not obviously an attack. So the guardian escalates to the
> Somnia agent. This isn't an off-chain API call: a subcommittee of validators each runs the
> model and they reach consensus."

On screen, watch the feed: **EscalatedToAI** → (a few seconds later) **AIVerdict — score X from
N validators**. Open the explorer to show the on-chain request + the N validator responses with
receipts.
> "The verdict lives on-chain with a receipt per validator — fully auditable. If the score
> crosses the threshold, the breaker latches and every withdrawal pauses."

## Shot 3.5 — Tier-2d: the agent ACTS, not just scores (the agentic moment) ★★
Show the explorer for guardian v3's `RemediationVerdict` from the live test (or call
`requestAutonomousRemediation` as admin). Open the validator response and read the LLM's
on-chain reasoning aloud:
> "Here's the strongest part. Hajar doesn't just ask the AI for a score — it gives the agent a
> `pause()` tool via `inferToolsChat` and lets it DECIDE whether to act. Validators reached
> consensus; the model reasoned, on-chain: *'the protocol appears to be operating normally… no
> action required'* — and correctly chose **not** to pause. The agent takes autonomous on-chain
> action, and it's safe-by-design: the only tool it can ever call is pause, which an admin resets.
> Arbitrary AI calldata is never executed."

## Shot 3.7 — Agent-discoverable (Somnia is an Agentic L1) (optional, 15s)
Hit `https://hajar-somnia-guardian.vercel.app/api/mcp` and `/api/state` in the browser.
> "And because Somnia's whole thesis is that the main users are AIs, Hajar exposes a lite MCP
> tool catalog — any other agent can discover it and read a protocol's live security posture."

## Shot 4 — Reset + multi-tenant (2:20–2:45)
If breaker tripped: click **♻️ Reset Breaker** (admin) → pill back to ACTIVE.
> "Any protocol can `registerProtocol` its vault and instantly get its own admin, thresholds,
> and circuit breaker — Hajar-as-a-Service."

## Shot 5 — Tier 3, validator-triggered (2:45–3:05)
Show the explorer for `HajarReactiveSubscriber` (0x9857…) — point at the `Subscribed` event
(subscription id 4542758) and a `ReactiveForwarded` event from an earlier withdrawal.
> "Tier 3 is a real on-chain Reactivity subscription. A withdrawal event auto-fires the
> subscriber ~20 blocks later — triggered by validators, no keeper, no bot."

## Shot 6 — Close (3:05–3:20)
Back to the dashboard.
> "Hajar: three tiers, three Somnia agents, real validator-consensus AI, all on-chain and live
> on Shannon testnet today. Built for the Somnia Agentathon."

Show: GitHub link + live URL on the final frame.

---

### Backup talking points (if something doesn't fire)
- Validator consensus on Parse-Website can be flaky (extractions diverge) — if a Tier-2c scan
  returns `Failed`, fall back to the Tier-2 LLM demo, which is the reliable headline path.
- If the guardian is underfunded, escalation `fail-opens` (emits `EscalationSkipped` "underfunded")
  rather than blocking — fund the guardian before recording.
- Tier-1 drain needs the connected wallet to hold most of the TVL (it can only withdraw its own
  balance) — deposit first, ideally from a fresh vault, then drain.
