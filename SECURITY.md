# Security model & threat analysis — Hajar

Hajar is a security product, so its own design has to be conservative. This documents the
threat model, the deliberate safety choices, and the known limitations — honestly.

## Trust assumptions

| Actor | Trusted for | NOT trusted for |
|-------|-------------|-----------------|
| Protocol admin | Configuring thresholds, resetting its own breaker, setting its monitor | Other protocols' state (per-vault isolation) |
| Guardian owner | Agent config (ids, costs, window), funding | Per-protocol breaker decisions (those are admin/AI/reactivity) |
| Somnia validators | Running agent inference + reaching consensus; triggering Reactivity | Individual validator results (consensus + status checks gate everything) |
| Somnia Agents platform | Delivering callbacks | — callbacks are authenticated: `msg.sender == platform` |

## Tier-by-tier failure mode

| Tier | On failure | Direction |
|------|-----------|-----------|
| 1 — hard rule | Reverts the withdrawal (per-tx); never latches (a revert would roll a latch back) | **fail-safe** (blocks) |
| 1c — spot-price guard | Reverts the withdrawal in-tx when the vault's `spotPrice()` diverges ≥ tolerance; opt-in | **fail-safe** (blocks) |
| 1d — outflow budget | Reverts once vault-wide cumulative outflow ≥ `budgetBps` of window-start TVL; opt-in, never latches | **fail-safe** (blocks) |
| 2 — LLM risk | If underfunded / no consensus / non-Success → does **not** block, emits a verdict | **fail-open** (availability) |
| 2b — price oracle | Divergence ≥ threshold latches; bad/empty response → no alarm | fail-open |
| 2c — threat intel | High score latches; failed scrape → no latch (Parse-Website consensus is unreliable today) | **fail-safe on action** |
| 2d — remediation | Latches **only** on a decoded `pause()` tool call; anything else → no action | **fail-closed on action** |
| 3 — reactivity | Validator-triggered latch in a separate execution | fail-safe |
| TVL-drop detector | Latches in a separate execution when TVL falls MORE than the guarded outflow we recorded; opt-in | **fail-safe on action** |
| Self-learning intel | `HajarThreatLearner` scrapes/classifies external feeds via all 3 agents into an on-chain knowledge base; bad/empty response → no record (no fake data) | **fail-open** (knowledge only) |

The split is deliberate: a withdrawal must never be *blocked by accident* (Tier-1/2 fail open on
infra problems), but the breaker must never *latch by accident* (Tier-2d/3 fail closed on action).

## Key safety decisions

- **The AI never executes arbitrary calldata.** Tier-2d offers the LLM exactly one tool,
  `pause()`. The callback fully decodes `pendingToolCalls` and acts only if a call's 4-byte
  selector equals `pause()` (`0x8456cb59`). Any other selector is ignored. The worst an AI (or a
  compromised validator majority) can do is pause a protocol — which its admin can immediately
  `resetBreaker`. No funds can move on the AI's say-so.
- **Callbacks are authenticated.** `handleResponse` / `onReactiveSignal` require
  `msg.sender == platform` / `== monitor`, and every request id is tracked in `pending` and
  deleted on use (no replay).
- **The latch lives only in separate executions.** Tier-1 runs inside the withdrawal tx and only
  returns `false`; it never writes `paused`, because the revert would undo it. Latching happens
  exclusively in async callbacks and the reactivity handler.
- **Decode is isolated.** The tools-chat tuple decode runs in an external `try/catch`, so a
  malformed agent response can never revert (and thus never DoS) the callback.
- **Per-protocol isolation.** State is keyed by vault; one protocol's breaker, thresholds,
  whitelist, and velocity window can't affect another's. Covered by `test_MultiTenant_Isolation`.
- **Two-step ownership** for the guardian owner role (no accidental transfer to a wrong/dead key).
- **Reentrancy:** `ProtectedVault` follows checks-effects-interactions (balance/TVL decremented
  before the external transfer); covered by `test_Reentrancy_CannotDrainOthers`.

## Exploit coverage — what Hajar actually catches (honest)

Hajar detects exploits **by their effect on fund outflow**, not by their technique. Most exploits
end in an abnormal outflow, so this is broad — but the boundary matters and we state it plainly.

| Attack pattern | Caught by | Notes |
|----------------|-----------|-------|
| Single-tx drain (≥ `hardBps` of TVL) | Tier-1 | synchronous, same-block revert |
| Looped / rapid drain (one user, cumulative ≥ `rapidBps`) | Tier-1 velocity | windowed per-user |
| **Slow drain sprayed across many sybil addresses** (each under per-user limit) | **Tier-1d outflow budget** | aggregate, vault-wide — closes the sybil gap |
| Grey-zone suspicious withdrawal (15–40%) | Tier-2 LLM | validator-consensus risk score |
| Oracle manipulation / depeg (out-of-band) | Tier-2b price | async JSON price vs reference |
| **Atomic flash-loan price manipulation (same tx)** | **Tier-1c spot guard** | only works if the protocol exposes `spotPrice()`; the sole tier fast enough for an atomic attack |
| **Drain that bypasses the withdrawal hook** (other buggy fn, direct transfer) | **TVL-drop detector** | catches unexplained TVL loss; latches in a separate execution |
| Known-exploit / active-incident intel | Tier-2c threat | self-updating threat feed |

### Still out of Hajar's reach (architectural, not laziness)

- **A truly atomic drain via a non-withdraw path** can't be *prevented* in the same tx (the
  guardian isn't on that code path) — the TVL-drop detector catches it *after the fact* and latches
  to stop the next action, but value already lost in that single tx is gone.
- **Logic / accounting bugs, governance takeover, access-control flaws, signature/approval abuse**
  that don't move value out of the vault in an abnormal pattern are **outside the model**. Hajar is a
  circuit breaker on abnormal outflow, not a formal-verification or internal-accounting auditor.
  Treat it as defense-in-depth alongside audits, not a replacement.

## On "self-learning" (honest scope)

`HajarThreatLearner` is a real, autonomous **knowledge loop** — NOT on-chain model training (which
is infeasible). It uses the three Somnia agents to read the outside world and keep an on-chain
threat knowledge base current:
- **Parse Website** scrapes a security feed (rekt.news / advisories) and extracts a 0..100 threat
  level per exploit category. *Caveat:* Parse-Website consensus is unreliable on Somnia testnet
  today (validators diverge on scrapes) — it fails open (no record) rather than inventing data.
- **JSON API** pulls a structured score (verified live: it learned `market-stress = 10` from the
  Fear & Greed Index via validator consensus, recorded on-chain).
- **LLM `inferString`** classifies an observed pattern onto the exploit taxonomy.

What it genuinely does: **accumulate + update** threat knowledge from external sources over time,
with no human in the loop (keeper-driven). What it does NOT do: invent new detection logic by
itself, or train a model. The knowledge informs policy and is exposed to other agents (`/api/learn`).

## Known limitations (honest)

- **Parse-Website consensus is unreliable** on Somnia testnet today — even a maximally
  deterministic single-number page returned a non-`Success` status (validators diverge on
  scrape/extraction). Hajar fails safe and ships a reliable **JSON-API** threat source as the
  primary path; the scrape is best-effort. Re-test as the platform matures.
- **Tier-3 vs Tier-1 overlap:** for a vault that already calls `checkWithdrawal` synchronously,
  the reactive path uses the same rule Tier-1 enforces, so it won't latch on a withdrawal Tier-1
  allowed. Its value is reactive-only protection for protocols that don't add the sync hook.
- **Economic:** the guardian must hold STT to pay validators; Tier-2 fails open if underfunded
  (emits `EscalationSkipped("underfunded")`), prioritising availability. Fund accordingly.
- **`ISomniaAgents` ABI** is reconciled to the live platform; the tools-chat return-tuple format
  was confirmed against on-chain bytes. Reconcile again before mainnet.

## Reporting

This is a hackathon submission on testnet. For real deployments, route security reports to the
protocol's admin and the guardian owner; never disclose an unmitigated drain vector publicly
before the breaker policy is tuned.
