# Hajar — QA & Test Report

Comprehensive quality assurance across contracts, integration, security, on-chain state, and the
live web layer. Last run: **10 Jun 2026**.

## Summary

| Dimension | Result |
|-----------|--------|
| Unit + integration tests (Foundry) | **78 passing · 0 failing · 0 skipped** (6 suites) |
| Fuzz | hard-drain always blocked (256 runs) |
| Contract sizes (EIP-170 ≤ 24,576 B) | all pass — Guardian 21,649 · Learner 8,108 · Registry 4,044 · Subscriber 1,593 |
| Frontend build (Next.js) | clean · 6 routes |
| Live API endpoints | `/api/state`, `/api/learn`, `/.well-known/agent-card.json`, `/api/mcp` → 200, correct data |
| On-chain state sweep | guardian / vault / registry / learner / subscriber all consistent |
| Mocks in production path | **none** (only `test/mocks/` — test-only) |

## 1. Contract test inventory (78 cases)

**`HajarGuardian.t.sol` (26)** — Tier-1 hard drain blocked same-block; normal withdrawal; Tier-2 grey
escalation trips / low-score no-trip; Tier-2d remediation tool-call latches / stop no-latch / gated /
decode-only-pause; pause blocks everyone until reset; whitelist bypass; callback only-platform;
velocity rapid-drain blocked; Tier-3 reactivity latch; only-monitor; underfunded fails open;
escalation cooldown; no double-count across reactive; autonomous risk check + gating; multi-tenant
isolation; price-oracle divergence trips / in-range no-trip; threat-intel high/low/JSON; selector lock.

**`HajarEdgeCases.t.sol` (7)** — reentrancy can't drain others; velocity window resets after expiry;
whitelist still blocked when paused; mixed validators average successes only; negative AI score
clamped; risk-check underfunded returns zero; **fuzz** hard-drain always blocked (256 runs).

**`HajarHardening.t.sol` (11)** — outflow budget blocks distributed drain / disabled-by-default /
window resets; TVL-drop unexplained latches / explained-by-guarded-outflow no-latch / below-threshold
no-latch / whitelisted-outflow accounted (no false latch) / gated; spot guard divergence blocks
atomically / in-range passes / missing-spotPrice fails open.

**`HajarThreatLearner.t.sol` (9)** — JSON learn records level; Parse learn records level; classify
tags category; unknown label ignored; highestThreat tracks max; learn unconfigured reverts;
underfunded returns zero; callback only-platform; classify gated.

**`HajarAgentRegistry.t.sol` (7)** — register mints to caller (not the registry — regression for a
self-call bug); register with metadata; setAgentURI only-owner; agentWallet defaults to owner then
settable; transfer portable identity; supportsInterface ERC-721; tokenURI unknown reverts.

**`HajarIntegration.t.sol` (18)** — end-to-end + boundary:
- *Scenario* sybil drain stopped by aggregate budget (5 sybils, each under the grey zone).
- *Scenario* bypass-hook drain caught by the TVL-drop detector.
- *Scenario* atomic flash-loan spot manipulation blocked in-tx.
- *Scenario* all hardening tiers compose without interfering on a normal flow.
- Budget boundary is inclusive (`>=`); disabling re-opens flow.
- TVL monitor: grow-then-drop no false latch; `syncTvlBaseline` clears a legit move.
- Spot guard: reference 0 = disabled (no div-by-zero); `setSpotReference` updates.
- Learner: mixed validators average successes; no-consensus → no record; observations accumulate;
  level clamped to 100.
- Registry: multiple agents increment ids; metadata overwrite; transfer moves control; approved can transfer.

## 2. Security checks

- **Access control** — per-protocol admin gates config/reset; `onlyOwner` gates platform config;
  callbacks require `msg.sender == platform` / `== monitor`; covered by `*_OnlyPlatform`, `*_Gated`.
- **Fail direction** — Tier-1/1c/1d revert (fail-safe, never latch); Tier-2/2b fail open on infra;
  Tier-2c/2d/3 + TVL-drop fail closed on action. See `SECURITY.md`.
- **No silent fakes** — the learner / price / threat paths write nothing when consensus fails
  (`ScanSkipped`); the web reads only on-chain values; the agent-card is pinned to a canonical origin
  (no Host-header trust-anchor poisoning) and sent `Cache-Control: no-store`.
- **Reentrancy** — `ProtectedVault` is checks-effects-interactions; covered by a reentrant-attacker test.
- **Decode isolation** — the tools-chat tuple decode runs under `try/catch` so a malformed agent
  response can never revert (DoS) the callback.

## 3. On-chain state sweep (Somnia testnet)

| Contract | Verified |
|----------|----------|
| HajarGuardian v4 | registered, thresholds 40/60/15/risk 70, outflowBudget 70%, tvlMonitor 20%, monitor = subscriber, **ACTIVE** |
| ProtectedVault v4 | `guardian` → v4, TVL live |
| HajarAgentRegistry | agentId 1 owner = deployer, totalAgents 1, tokenURI → agent card |
| HajarThreatLearner | 6 categories, **highestThreat market-stress = 10** (validator-consensus), funded |
| HajarReactiveSubscriber | subscription registered, `guardian`/`vault` → v4, ≥ 32 STT held |

**Live-verified agent runs (no mocks):** JSON API learned market-stress = 10 via validator consensus;
Tier-3 reactivity auto-fired `ReactiveForwarded` ~20 blocks after a withdrawal (validator-triggered).
LLM-agent verdicts are intermittent on testnet today (heavier 0.07-STT/validator path); the JSON +
reactivity proofs stand, and the `/agents` page lets anyone trigger a fresh run.

## 4. How to reproduce

```bash
forge test -vv          # 78 tests
forge build --sizes     # confirm all < 24,576 B (requires via_ir = true)
cd web && pnpm build    # 6 routes, clean
```
