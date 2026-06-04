# src/ — Contracts

## Pattern
- One contract per file. Solidity 0.8.24.
- **Custom errors** over revert strings. **Events** on every state change.
- Async agent flow: build payload with `abi.encodeWithSelector(IAgentFn.method.selector, ...)`,
  call `platform.createRequest{value: deposit}(...)`, store a per-`requestId` context struct,
  resolve in `handleResponse`. Always: guard `msg.sender == platform`, check `requestId` is
  pending, check `ResponseStatus.Success` before `abi.decode`-ing `result`.

## The tiers (don't break this invariant)
- Tier-1 (inline in `checkWithdrawal`) is **synchronous + must not latch state** — it runs inside
  a tx that reverts, so any latch is rolled back. It only returns `false` (vault reverts) on a
  hard/velocity violation.
- The breaker latches (`paused = true`) **only** in separate executions: `handleResponse` (Tier-2
  AI / 2b price / 2c threat — async callbacks) and `onReactiveSignal` (Tier-3 Reactivity handler).

## Editing the Tier-1 policy
The policy lives inline in `checkWithdrawal(user, amount, tvlBefore)`. It computes
`bps = amount * 10_000 / tvlBefore` and a windowed `windowBps`, then blocks if
`bps >= p.hardBps || windowBps >= p.rapidBps`, and escalates to AI if `>= p.greyBps`.
Thresholds are **per-protocol** (`registerProtocol`/`setThresholds`) — tune per protocol type
(lending vs vault vs AMM have different "obviously malicious" signatures).

## Files
- `HajarGuardian.sol` — core guardian.
- `ProtectedVault.sol` — demo protocol (`IGuardian` consumer).
- `interfaces/ISomniaAgents.sol` — platform + base-agent payload interfaces (reconciled to the
  live ABI; no `TODO(verify)` left).
- `HajarReactiveSubscriber.sol` — real Tier-3 (validator-triggered). `HajarReactiveMonitor.sol` —
  keeper-driven Tier-3 variant for local tests.
- `test/mocks/MockAgentPlatform.sol` — test-only; mirrors platform shape, `fulfillNumber()` drives callbacks.
