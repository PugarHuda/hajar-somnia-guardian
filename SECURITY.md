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
| 2 — LLM risk | If underfunded / no consensus / non-Success → does **not** block, emits a verdict | **fail-open** (availability) |
| 2b — price oracle | Divergence ≥ threshold latches; bad/empty response → no alarm | fail-open |
| 2c — threat intel | High score latches; failed scrape → no latch (Parse-Website consensus is unreliable today) | **fail-safe on action** |
| 2d — remediation | Latches **only** on a decoded `pause()` tool call; anything else → no action | **fail-closed on action** |
| 3 — reactivity | Validator-triggered latch in a separate execution | fail-safe |

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
