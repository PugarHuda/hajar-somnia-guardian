# src/ — Contracts

## Pattern
- One contract per file. Solidity 0.8.24.
- **Custom errors** over revert strings. **Events** on every state change.
- Async agent flow: build payload with `abi.encodeWithSelector(IAgentFn.method.selector, ...)`,
  call `platform.createRequest{value: deposit}(...)`, store a per-`requestId` context struct,
  resolve in `handleResponse`. Always: guard `msg.sender == platform`, check `requestId` is
  pending, check `ResponseStatus.Success` before `abi.decode`-ing `result`.

## The two tiers (don't break this invariant)
- Tier-1 (`_isHardViolation`) is **synchronous + must not latch state** — it runs inside a tx
  that reverts, so any latch is rolled back. Keep it pure-ish (view), return bool.
- Tier-2 (`handleResponse`) is the **only** place the breaker latches, because it's a separate
  (async) execution. Same for any future Reactivity handler.

## Editing `_isHardViolation`
This is the security policy. It receives `(user, amount, tvlBefore, bps)` where
`bps = amount * 10_000 / tvlBefore`. Return true to hard-block. Tune per protocol type
(lending vs vault vs AMM have different "obviously malicious" signatures).

## Files
- `HajarGuardian.sol` — core guardian.
- `ProtectedVault.sol` — demo protocol (`IGuardian` consumer).
- `interfaces/ISomniaAgents.sol` — platform + base-agent payload interfaces. `TODO(verify)`.
- `mocks/MockAgentPlatform.sol` — test-only; mirrors platform shape, `fulfillNumber()` drives callbacks.
