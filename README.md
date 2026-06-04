# Hajar — Autonomous DeFi Guardian on Somnia

> Built for the **Somnia Agentathon**. Hajar is a **multi-tenant, three-tier autonomous
> security layer** that protects DeFi protocols from drains and exploits — combining instant
> deterministic circuit breakers with **consensus-verified AI judgment** run by Somnia
> validators, plus an external price-oracle sanity check and a self-updating threat-intel feed.

Any protocol can `registerProtocol()` its vault and instantly get exploit protection —
**Hajar-as-a-Service**. Each protocol gets its own admin, thresholds, and circuit breaker.

- **Live frontend:** https://hajar-somnia-guardian.vercel.app
- **GitHub:** https://github.com/PugarHuda/hajar-somnia-guardian
- **Chain:** Somnia Shannon testnet (chainId 50312, token STT)

## The problem

Existing DeFi security (monitoring bots, keepers, off-chain risk engines) reacts *after* an
exploit, off-chain, with a single trusted party deciding. Hajar moves the whole loop on-chain
and makes the AI verdict **verifiable by multiple Somnia validators**.

## How it works — three tiers

Somnia Agent calls are **asynchronous** (request now, callback later). You cannot block an
in-flight transaction on an AI verdict. Hajar embraces that with a layered design:

| Tier | Path | When | What it does |
|------|------|------|--------------|
| **1 — Hard rule** | Synchronous, same-block, no AI | Every withdrawal | A deterministic rule (single-tx drain ≥ `hardBps`, or looped *velocity* drain ≥ `rapidBps` within the window) **reverts** blatant attacks instantly. Re-evaluated each call, so it re-blocks every retry. |
| **2 — AI judgment** | Async, Somnia **LLM Inference** agent (`inferNumber`) | Grey-zone activity (`>= greyBps` of TVL) | Validators run Qwen3-30B deterministically and reach **consensus** on a 0–100 risk score. If `>= risk`, Hajar **latches** the circuit breaker, pausing all withdrawals. |
| **2b — Price oracle** | Async, Somnia **JSON API** agent (`fetchUint`) | On demand / scheduled | Fetches the real market price from a public endpoint and compares it to the protocol's reference price. A divergence `>= maxDivergenceBps` latches the breaker — catching **oracle manipulation / depeg** the velocity & LLM tiers can't see. |
| **2c — Threat intel** | Async, Somnia **Parse Website** agent (`ExtractANumber`) + JSON API | Scheduled (cron) | Scrapes a security/advisory page (or polls a threat-intel API) for a 0–100 threat score. A high score latches the breaker, so the guardian **continuously learns** about new exploit patterns. |
| **3 — Reactivity latch** | Event-driven, **validator-triggered** | On the vault's `Withdrawn` event | A real Somnia Reactivity subscription fires in a *separate* execution and can latch the breaker persistently — the one thing the synchronous Tier-1 path cannot do. |

```
                         ┌──────────────────────────────────────────────┐
   withdraw() ──────────►│            ProtectedVault (any DeFi)           │
                         └───────────────┬──────────────────────────────┘
                                         │ checkWithdrawal(user, amount, tvl)
                                         ▼
        ┌────────────────────────────────────────────────────────────────────┐
        │                          HajarGuardian                              │
        │                                                                     │
        │  TIER 1  bps ≥ hardBps  OR  velocity ≥ rapidBps  ─► revert (block)  │  sync
        │                                                                     │
        │  TIER 2  greyBps ≤ bps < hardBps  ─► escalateToAI ─┐                │  async
        └────────────────────────────────────────────────────│───────────────┘
                                                              │ createRequest{value}
                       Somnia Agents platform (0x037B…6776)   ▼
        ┌──────────────────────┬───────────────────────┬──────────────────────┐
        │  LLM Inference (T2)   │   JSON API (T2b)       │  Parse Website (T2c) │
        │  inferNumber 0..100   │   fetchUint price      │  ExtractANumber 0..100│
        └──────────┬───────────┴───────────┬───────────┴──────────┬───────────┘
                   │  validator consensus   │                      │
                   ▼                        ▼                      ▼
        handleResponse(requestId, responses[], status)  ─► may latch paused=true
                                                              (separate execution)
        ┌────────────────────────────────────────────────────────────────────┐
   TIER 3│ HajarReactiveSubscriber  ◄── validators auto-fire on Withdrawn event │
        │  onEvent ─► guardian.onReactiveSignal ─► latch (no keeper, no bot)    │
        └────────────────────────────────────────────────────────────────────┘
```

> **Why the sync/async split is honest:** in one EVM tx you cannot both `revert` the trigger
> *and* persist a `paused = true` latch (the revert rolls it back). So Tier-1 blocks per-tx;
> the latch lives only in async callbacks (`handleResponse`) and in the Tier-3 Reactivity
> handler — separate executions that survive.

## Why Somnia (not Chainlink CRE / an oracle)

- **AI runs inside validator consensus**, not an off-chain runtime. Every risk verdict carries
  a `receipt` and N validator responses you can audit on-chain.
- **Sub-cent fees + ~400k TPS** make a guardian that checks *every block* economically viable —
  infeasible on most chains.
- **Agent-native + Reactivity** are first-class Somnia primitives — Hajar uses **three different
  agents** (LLM Inference, JSON API, Parse Website) and a real on-chain Reactivity subscription.

## Contracts

| File | Role |
|------|------|
| `src/HajarGuardian.sol` | The multi-tenant three-tier guardian. Tier-1 policy lives in `checkWithdrawal()`; per-protocol thresholds are `hardBps / rapidBps / greyBps / risk`. |
| `src/ProtectedVault.sol` | Demo protocol being protected (stands in for any vault / lending market / AMM treasury). |
| `src/HajarReactiveSubscriber.sol` | **Real Tier-3**: registers an on-chain Reactivity subscription; validators auto-invoke its `onEvent` on the vault's `Withdrawn` event. |
| `src/HajarReactiveMonitor.sol` | Keeper-driven Tier-3 variant used for local tests. |
| `src/interfaces/ISomniaAgents.sol` | Somnia Agents platform + agent payload interfaces, **reconciled to the live ABI**. |
| `src/demo/` | `Exploiter.sol` (looped-drain attacker), `JsonProbe.sol`, `WebProbe.sol` (agent probes). |
| `test/mocks/MockAgentPlatform.sol` | Local simulation of validators fulfilling AI requests (test-only — no mocks in `src/`). |

## Quickstart

```bash
forge build
forge test -vv     # 28 passing tests: 3 tiers, price oracle, threat intel,
                   # pause/reset, whitelist, multi-tenant isolation, velocity,
                   # reentrancy, fuzz, auth guards
```

## Deploy to Somnia testnet

```bash
cp .env.example .env   # fill PRIVATE_KEY + SOMNIA_PLATFORM + LLM_AGENT_ID
forge script script/Deploy.s.sol --rpc-url somnia_testnet --broadcast --legacy
```

The reactive subscriber (real Tier-3) is deployed separately — it needs `>= 32 STT` and the
live Reactivity precompile (`0x0100`), so it is not part of the main deploy script.

## Deployments — Somnia Shannon Testnet (chain 50312)

| Contract | Address | Explorer |
|----------|---------|----------|
| HajarGuardian v2 (multi-tenant, all agents) | `0x42245cEef96D432c8DA3918dc66D3663E36bFE72` | [view](https://shannon-explorer.somnia.network/address/0x42245cEef96D432c8DA3918dc66D3663E36bFE72) |
| ProtectedVault | `0x237A48d4B05944cC78b2b469F68F1f21D7AdfF39` | [view](https://shannon-explorer.somnia.network/address/0x237A48d4B05944cC78b2b469F68F1f21D7AdfF39) |
| HajarReactiveSubscriber (real Tier-3) | `0x9857aF25fFa558C382AbB916803Ee441502b0F8D` | [view](https://shannon-explorer.somnia.network/address/0x9857aF25fFa558C382AbB916803Ee441502b0F8D) |
| Somnia Agents platform | `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` | (Somnia) |

> The Tier-3 subscriber is bound (immutable) to the prior guardian `0x6BA6…a2f8`, where Tier-3
> was first proven live; guardian **v2** (`0x4224…FE72`) adds the price-oracle + threat-intel
> agents and is what the frontend reads today.

**Verified live on testnet (all tiers, real — no mocks):**
- **Tier 1** — a hard-block reverts an 80%-of-TVL withdrawal same-block.
- **Tier 2 (the differentiator)** — real requests to the Somnia Agents platform; a 3-validator
  subcommittee ran Qwen3-30B inference and consensus `AIVerdict`s were delivered on-chain
  (proactive check → score 0; 30% withdrawal → score 10).
- **Tier 2b (JSON API price oracle) — verified live.** `requestPriceCheck` fetched a real FX
  rate (USD→EUR `0.8610`) via validator consensus, computed a `641 bps` divergence from the
  reference on-chain, and emitted `PriceVerdict` (no false alarm). Real `fetchUint`, real
  consensus.
- **Tier 2c (threat intel) — JSON-API source verified live** (`requestThreatScanJson` →
  `ThreatVerdict`, score `1`, no alarm). The **Parse-Website** source (`ExtractANumber`) is
  implemented but the Somnia validators' web-scrape consensus is unreliable today (it returned a
  non-`Success` status — see `DISCORD_QUESTION.md`); Hajar **fails safe** (it emits a verdict and
  never latches on a failed scrape). This is exactly why Tier-2c ships **two sources** — the
  reliable JSON API path backs up the experimental scrape.
- **Tier 3 (genuinely validator-triggered)** — `HajarReactiveSubscriber` registered a real
  on-chain Reactivity subscription (id `4542758`) via precompile `0x0100`. A withdrawal emitted
  `Withdrawn`; ~20 blocks later **validators auto-invoked** `onEvent` in a separate execution
  (`ReactiveForwarded`) → `onReactiveSignal`. No keeper.

**Agent ids (same on testnet & mainnet):**
- LLM Inference (Qwen3-30B): `12847293847561029384` — ~0.07 STT/validator
- JSON API Request: `13174292974160097713` — ~0.03 STT/validator
- LLM Parse Website: `12875401142070969085` — ~0.10 STT/validator

Deposit per call = `getRequestDeposit()` + `pricePerValidator × subcommitteeSize` (default 3).

## The knobs that matter

`registerProtocol(vault, hardBps, rapidBps, greyBps, risk)` sets the policy per protocol
(pass `0` for sensible defaults: 40% / 60% / 15% / risk 70). Tune to the protocol type:
lending, vault, and AMM treasuries each have different "obviously malicious" signatures.
Too strict → false pauses; too loose → an exploit drains funds before Tier-2 reacts.

## Honest design notes (read before judging)

- **Tier-3 vs Tier-1 overlap:** for a vault that *already* calls `checkWithdrawal` synchronously,
  the reactive Tier-3 path uses the same rule Tier-1 enforces, so it won't latch on a withdrawal
  Tier-1 already allowed. Its real value is **reactive-only protection for protocols that do NOT
  add the sync hook** — the subscription still fires and is genuinely validator-triggered (proven
  on-chain). It's a layered safety net, not a duplicate.
- **`inferToolsChat` (autonomous remediation) — roadmap:** the next agent-first upgrade is having
  the AI emit on-chain remediation calldata, not just a score. It's blocked on the `onchainTools`
  tuple ABI, which isn't published on the agent page, so the function selector can't be computed
  reliably yet (see `DISCORD_QUESTION.md`). We don't guess selectors.

## Somnia deploy gotchas (learned the hard way)

- **Use legacy txs** (`--legacy`). EIP-1559 deploys fail on Somnia.
- **Gas is metered ~10× higher than mainnet-EVM intuition.** `HajarGuardian` costs **~24M gas**
  to deploy (block limit 333M). `forge script` under-estimates and the CREATE fails *silently*
  (prints an address with no code). For large contracts, deploy with
  **`forge create --gas-limit 35000000`** (or `cast send --gas-limit`).

## Status

- [x] Multi-tenant three-tier guardian (sync hard rule + velocity, async AI, reactivity latch)
- [x] Tier-2b external price-oracle sanity check (JSON API agent) — **deployed + verified live**
- [x] Tier-2c self-updating threat intelligence — JSON API source **deployed + verified live**;
      Parse-Website source implemented (validator scrape-consensus flaky, fails safe)
- [x] Proactive autonomous monitoring (`requestRiskCheck`) for 24/7 AI health checks
- [x] Demo vault + Exploiter (looped-drain) scenario
- [x] `ISomniaAgents` reconciled to the live ABI; real agent ids wired
- [x] **28 passing tests** (incl. fuzz, reentrancy, multi-tenant isolation)
- [x] All tiers deployed + live-verified on Somnia testnet (real validator consensus):
      Tier-1 (block), Tier-2 LLM (score 0, 2 validators), Tier-2b price oracle, Tier-2c JSON
      threat, Tier-3 reactivity
- [x] Interactive frontend dashboard live on Vercel
- [ ] Demo video (2–5 min)
- [ ] (roadmap) `inferToolsChat` agent that emits remediation calldata — pending the
      `onchainTools` tuple ABI so the selector can be computed correctly
