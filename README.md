# Hajar — Autonomous DeFi Guardian on Somnia

> Built for the **Somnia Agentathon**. Hajar is a two-tier autonomous security layer that
> protects DeFi protocols from drains and exploits — combining instant deterministic
> circuit breakers with **consensus-verified AI judgment** from Somnia Agents.

## The problem

Existing DeFi security (monitoring bots, keepers, off-chain risk engines) reacts *after*
an exploit, off-chain, with a single trusted party deciding. Hajar moves the whole loop
on-chain and makes the AI verdict **verifiable by multiple Somnia validators**.

## How it works — two tiers

Somnia Agent calls are **asynchronous** (request now, callback later). You cannot block an
in-flight transaction on an AI verdict. Hajar embraces that with two tiers:

| Tier | Path | When | What it does |
|------|------|------|--------------|
| **1 — Hard rule** | Synchronous, same-block, no AI | Every withdrawal | Deterministic rule (e.g. `> 40% of TVL in one tx`) reverts blatant drains instantly. Re-evaluated each call, so it re-blocks every retry. |
| **2 — AI judgment** | Async, Somnia LLM Inference agent | Grey-zone activity (`>= 15%` of TVL) | Validators run `inferNumber` deterministically, reach consensus on a 0–100 risk score. If `>= riskThreshold`, Hajar **latches the circuit breaker**, pausing all withdrawals. |

> **Why the split is honest:** in one EVM tx you cannot both `revert` the trigger and
> persist a `paused = true` latch (the revert rolls it back). So Tier-1 blocks per-tx;
> the latch lives in Tier-2's async callback (a separate execution) — or, in production,
> in a Somnia Reactivity subscription that fires on the withdrawal event.

## Why Somnia (not Chainlink CRE / an oracle)

- **AI runs inside validator consensus**, not an off-chain runtime. Every risk verdict
  carries a `receipt` and N validator responses you can audit on-chain.
- **Sub-cent fees + ~400k TPS** make a guardian that checks *every block* economically
  viable — infeasible on most chains.

## Contracts

| File | Role |
|------|------|
| `src/HajarGuardian.sol` | The two-tier guardian. Tier-1 rule lives in `_isHardViolation()`. |
| `src/ProtectedVault.sol` | Demo protocol being protected (stands in for any vault/lending market). |
| `src/interfaces/ISomniaAgents.sol` | Somnia Agents platform + base-agent payload interfaces. |
| `src/mocks/MockAgentPlatform.sol` | Local simulation of validators fulfilling AI requests. |

## Quickstart

```bash
forge build
forge test -vv     # 7 passing tests cover both tiers, pause/reset, whitelist, auth
```

## Deploy to Somnia testnet

```bash
cp .env.example .env   # fill PRIVATE_KEY + LLM_AGENT_ID (from agents.somnia.network)
forge script script/Deploy.s.sol --rpc-url somnia_testnet --broadcast --private-key $PRIVATE_KEY
```

## ⚠️ Before mainnet — verify the live ABI

The Somnia Agents interface in `ISomniaAgents.sol` is reconstructed from the docs and is
**self-consistent with the local mock** (tests pass), but the exact `Request` struct shape
and the LLM agent function selectors **must be reconciled with the official SDK / the live
platform ABI** before broadcasting. Search for `TODO(verify)` in `src/`.

## The one knob that matters

`HajarGuardian._isHardViolation()` is the policy brain — tune it to the protocol you
protect. Too strict → false pauses; too loose → an exploit drains funds before Tier-2 reacts.

## Deployments — Somnia Shannon Testnet (chain 50312)

| Contract | Address | Explorer |
|----------|---------|----------|
| HajarGuardian (multi-tenant) | `0x6BA6c7c52413A592F7799288CbC42d187ddda2f8` | [view](https://shannon-explorer.somnia.network/address/0x6BA6c7c52413A592F7799288CbC42d187ddda2f8) |
| ProtectedVault | `0x237A48d4B05944cC78b2b469F68F1f21D7AdfF39` | [view](https://shannon-explorer.somnia.network/address/0x237A48d4B05944cC78b2b469F68F1f21D7AdfF39) |
| HajarReactiveSubscriber (real Tier-3) | `0x9857aF25fFa558C382AbB916803Ee441502b0F8D` | [view](https://shannon-explorer.somnia.network/address/0x9857aF25fFa558C382AbB916803Ee441502b0F8D) |
| Agents platform | `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` | (Somnia) |

**Verified live on testnet (all three tiers, real — no mocks):**
- **Tier 1** — hard-block reverts an 80%-of-TVL withdrawal.
- **Tier 2 (the differentiator)** — real requests sent to the Somnia Agents platform; a
  3-validator subcommittee ran Qwen3-30B inference and consensus `AIVerdict`s were delivered
  on-chain (proactive check → score 0; 30% withdrawal → score 10).
- **Tier 3 (genuinely validator-triggered)** — `HajarReactiveSubscriber` registered a **real
  on-chain Reactivity subscription** (id `4542758`) via the precompile `0x0100`. A withdrawal
  emitted `Withdrawn`; ~20 blocks later the **validators auto-invoked** the subscriber's
  `onEvent` in a separate execution (`ReactiveForwarded` event) → `onReactiveSignal`. No keeper.

Multi-tenant: any protocol can `registerProtocol()` its vault and get its own admin, breaker,
and thresholds. `LLM_AGENT_ID` = `12847293847561029384`.

**Somnia Agents — reconciled to the live ABI:**
- **LLM Inference agent id:** `12847293847561029384` (Qwen3-30B, same id testnet & mainnet).
- Live `inferNumber(string prompt, string system, int256 min, int256 max, bool chainOfThought)
  → int256`; 15-field `Request` struct; `ConsensusType { Majority, Threshold }`. Hajar's
  `ISomniaAgents.sol` now matches exactly (the earlier `TODO(verify)` is closed).
- Tier-2 escalates with consensus subcommittee = 3, ~0.07 STT/validator (~0.24 STT/call).

### ⚠️ Somnia deploy gotchas (learned the hard way)
- **Use legacy txs** (`--legacy`). EIP-1559 deploys fail on Somnia.
- **Gas is metered ~10x higher than mainnet-EVM intuition.** `HajarGuardian` costs **~24M
  gas** to deploy (block limit is 333M). `forge script` under-estimates and the CREATE
  fails *silently* (prints an address with no code). Deploy with **`forge create
  --gas-limit 35000000`** (or `cast send --gas-limit`), not `forge script`.

## Status

- [x] Three-tier guardian (sync hard rule + velocity, async AI, reactivity latch)
- [x] Proactive autonomous monitoring (`requestRiskCheck`) for 24/7 AI health checks
- [x] Demo vault + Exploiter (looped-drain) scenario
- [x] Local async AI flow via mock platform
- [x] `ISomniaAgents` reconciled to the live ABI; real `LLM_AGENT_ID` wired
- [x] 15 passing tests
- [x] Tier-1/Tier-3 deployed + live-verified on Somnia testnet
- [x] Frontend dashboard live on Vercel
- [ ] Redeploy reconciled guardian + live Tier-2 AI inference demo (needs testnet STT)
- [ ] (roadmap) `inferToolsChat` agent that emits remediation calldata — pending the
      onchainTools tuple ABI so the selector can be computed correctly
- [ ] Demo video
