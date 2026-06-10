# Hajar — Autonomous DeFi Guardian on Somnia

> Built for the **Somnia Agentathon**. Hajar is a **multi-tenant, three-tier autonomous
> security layer** that protects DeFi protocols from drains and exploits — combining instant
> deterministic circuit breakers with **consensus-verified AI judgment** run by Somnia
> validators, plus an external price-oracle sanity check and a self-updating threat-intel feed.

Any protocol can `registerProtocol()` its vault and instantly get exploit protection —
**Hajar-as-a-Service**. Each protocol gets its own admin, thresholds, and circuit breaker.

- **Live frontend:** https://hajar-somnia-guardian.vercel.app
- **Agent-discoverable (lite MCP):** [`/api/mcp`](https://hajar-somnia-guardian.vercel.app/api/mcp) tool catalog · [`/api/state`](https://hajar-somnia-guardian.vercel.app/api/state) live JSON state
- **GitHub:** https://github.com/PugarHuda/hajar-somnia-guardian
- **Security model & threat analysis:** [`SECURITY.md`](./SECURITY.md)
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
| **1c — Spot-price guard** | Synchronous, same-block, no AI | Every withdrawal (opt-in) | Reads the protocol's own `spotPrice()` **inline** and atomically reverts when it diverges from the reference beyond `maxDeviationBps`. The only tier fast enough to stop an **atomic flash-loan** price manipulation (async AI is always a block too late). Fails open if the price is unreadable. |
| **1d — Outflow budget** | Synchronous, same-block, no AI | Every withdrawal (opt-in) | Aggregates outflow across **all** users in a window and reverts once the vault has bled `budgetBps` of TVL — closing the **sybil slow-drain** gap (many addresses each under the per-user limit). |
| **2 — AI judgment** | Async, Somnia **LLM Inference** agent (`inferNumber`) | Grey-zone activity (`>= greyBps` of TVL) | Validators run Qwen3-30B deterministically and reach **consensus** on a 0–100 risk score. If `>= risk`, Hajar **latches** the circuit breaker, pausing all withdrawals. |
| **2b — Price oracle** | Async, Somnia **JSON API** agent (`fetchUint`) | On demand / scheduled | Fetches the real market price from a public endpoint and compares it to the protocol's reference price. A divergence `>= maxDivergenceBps` latches the breaker — catching **oracle manipulation / depeg** the velocity & LLM tiers can't see. |
| **2c — Threat intel** | Async, Somnia **Parse Website** agent (`ExtractANumber`) + JSON API | Scheduled (cron) | Scrapes a security/advisory page (or polls a threat-intel API) for a 0–100 threat score. A high score latches the breaker, so the guardian **continuously learns** about new exploit patterns. |
| **2d — Autonomous remediation** | Async, Somnia **LLM tools-chat** (`inferToolsChat`) | On demand | The agent is given an on-chain tool (`pause()`) and **decides whether to act**, not just score. If it returns a tool call, the callback latches the breaker. The AI takes autonomous on-chain action — verified by validator consensus. (Safe by design: the only consequence is a pause an admin can reset; raw agent calldata is never executed.) |
| **3 — Reactivity latch** | Event-driven, **validator-triggered** | On the vault's `Withdrawn` event | A real Somnia Reactivity subscription fires in a *separate* execution and can latch the breaker persistently — the one thing the synchronous Tier-1 path cannot do. |
| **TVL-drop detector** | Separate execution (`checkTvlDrop`) | Scheduled / reactive | Samples the vault's reported TVL and latches when it falls **more than the guarded outflow** the guardian actually saw — catching drains that **bypass the withdrawal hook** entirely (a bug in another function, a direct transfer). |

> **Operating autonomously, 24/7.** Tier-3 is fully on-chain autonomous (no keeper). The proactive
> tiers that must be *initiated* by a transaction (threat scan, AI risk check, TVL-drop sample) are
> driven with no human in the loop by [`.github/workflows/autonomous-guardian.yml`](.github/workflows/autonomous-guardian.yml):
> a gas-only TVL heartbeat every 2h plus a daily validator-paid threat/risk refresh.

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

## Standards & interoperability (why this is more than a one-off)

Hajar isn't a bespoke script — it implements and composes emerging agent + DeFi-security standards,
which is exactly the "composability + real-world utility" the brief asks for:

- **ERC-7265 (Circuit Breaker Standard).** Hajar's Tier-1d *vault-wide outflow budget* is the
  ERC-7265 rate-limiter — a temporary halt on protocol-wide outflows once a metric threshold is
  exceeded over a window. Hajar **extends** it with what only Somnia offers: validator-consensus AI
  on the grey-zone, not just a fixed threshold. ([EIP-7265](https://ethereum-magicians.org/t/eip-7265-circuit-breaker-standard/14909))
- **ERC-8004 (Trustless Agents).** Hajar registers as a first-class **on-chain agent** in an
  ERC-8004 Identity Registry (`src/HajarAgentRegistry.sol`) and serves a standards-compliant
  **Agent Registration File** at [`/.well-known/agent-card.json`](https://hajar-somnia-guardian.vercel.app/.well-known/agent-card.json).
  Other agents can *discover* Hajar, read its `services` (MCP + state endpoints), and *trust* it via
  `supportedTrust: ["reputation","crypto-economic"]` — where crypto-economic trust IS Somnia's
  validator consensus. Live on Ethereum mainnet since 29 Jan 2026. ([EIP-8004](https://eips.ethereum.org/EIPS/eip-8004))
- **x402 (agent payments).** The agent-card carries the `x402Support` flag — the path to
  *Hajar-as-a-Service*, where a protocol's agent pays per risk-query with no human in the loop.
  ([x402](https://www.coinbase.com/developer-platform/discover/launches/x402))

The result: Hajar is **agent-native end to end** — it *uses* Somnia agents (LLM/JSON/Parse/tools-chat),
it *is* a discoverable ERC-8004 agent other agents can find and verify, and it *acts* autonomously
(Reactivity + the keeper workflow).

## Contracts

| File | Role |
|------|------|
| `src/HajarGuardian.sol` | The multi-tenant guardian. Tier-1 policy in `checkWithdrawal()` (per-protocol `hardBps / rapidBps / greyBps / risk`); hardening tiers: outflow budget, spot-price guard, TVL-drop detector. |
| `src/HajarAgentRegistry.sol` | **ERC-8004 Identity Registry** — registers Hajar (and any agent) as a portable, discoverable on-chain identity (ERC-721 + agent-card URI + metadata). |
| `src/HajarThreatLearner.sol` | **Self-learning threat intel (v2)** — uses all 3 Somnia agents to keep an on-chain knowledge base current from **rotating sources**, then **feeds back into the AI**: `assessRisk()` injects the learned landscape into an LLM risk read so the AI's judgment is shaped by what Hajar learned. Live-proven: learned `market-stress = 9` by consensus → AI scored a withdrawal `75/100` informed by it. |
| `src/ProtectedVault.sol` | Demo protocol being protected (stands in for any vault / lending market / AMM treasury). |
| `src/HajarReactiveSubscriber.sol` | **Real Tier-3**: registers an on-chain Reactivity subscription; validators auto-invoke its `onEvent` on the vault's `Withdrawn` event. |
| `src/HajarReactiveMonitor.sol` | Keeper-driven Tier-3 variant used for local tests. |
| `src/interfaces/ISomniaAgents.sol` | Somnia Agents platform + agent payload interfaces, **reconciled to the live ABI**. |
| `src/demo/` | `Exploiter.sol` (looped-drain attacker), `JsonProbe.sol`, `WebProbe.sol` (agent probes). |
| `test/mocks/MockAgentPlatform.sol` | Local simulation of validators fulfilling AI requests (test-only — no mocks in `src/`). |

## Quickstart

```bash
forge build
forge test -vv     # 82 passing tests: all tiers, hardening, self-learning, ERC-8004 registry,
                   # guard, TVL-drop detector), ERC-8004 registry, price oracle, threat intel,
                   # autonomous remediation, pause/reset, whitelist, multi-tenant, fuzz, auth
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
| **HajarGuardian v4** (current — + outflow budget, spot-price guard, TVL-drop detector) | `0xf47D21Afd23639870c5185462B2F418eF59d6F67` | [view](https://shannon-explorer.somnia.network/address/0xf47D21Afd23639870c5185462B2F418eF59d6F67) |
| **HajarAgentRegistry** (ERC-8004 — Hajar = agentId 1) | `0xEa28EDF008A204BFeD65bD093ad5BC219fd35152` | [view](https://shannon-explorer.somnia.network/address/0xEa28EDF008A204BFeD65bD093ad5BC219fd35152) |
| **HajarThreatLearner** (self-learning, all 3 agents) | `0x97BE2B347682D72D98a2965ADa4947EA1B2B8Acc` | [view](https://shannon-explorer.somnia.network/address/0x97BE2B347682D72D98a2965ADa4947EA1B2B8Acc) |
| ProtectedVault (v4) | `0xe349707D8BAfA05BC7dd2A2dE16638CBE4673043` | [view](https://shannon-explorer.somnia.network/address/0xe349707D8BAfA05BC7dd2A2dE16638CBE4673043) |
| HajarGuardian v3 (Tier-1/2/2b/2c/2d + Tier-3, all verified live) | `0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c` | [view](https://shannon-explorer.somnia.network/address/0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c) |
| **HajarReactiveSubscriber (real Tier-3, bound to v4)** | `0xd6Fa24d9e388D12086D430e9F14ff99980E7789b` | [view](https://shannon-explorer.somnia.network/address/0xd6Fa24d9e388D12086D430e9F14ff99980E7789b) |
| HajarReactiveSubscriber (Tier-3, bound to v3) | `0x5aE10c3c1FE5eCf0b2a44a23E3bB62f7A7deD502` | [view](https://shannon-explorer.somnia.network/address/0x5aE10c3c1FE5eCf0b2a44a23E3bB62f7A7deD502) |
| Somnia Agents platform | `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` | (Somnia) |

> **All tiers now live on the single guardian v4** (`0xf47D…6F67`). The Tier-3 subscriber
> (`0xd6Fa…789b`, subscription id `5981959`) is bound to v4 and **verified live**: a withdrawal
> auto-fired its `onEvent` ~20 blocks later (`ReactiveForwarded`, amount 0.01 / tvlBefore 0.09),
> validator-triggered, no keeper. The full ERC-8004 identity + self-learning threat brain are live too.

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
- **Tier 2d (autonomous remediation) — verified live.** `requestAutonomousRemediation` sent a real
  `inferToolsChat` request offering the agent a `pause()` tool; the validator subcommittee reached
  **consensus** (`finishReason = "stop"`) and the LLM's on-chain reasoning was: *"The DeFi protocol
  0x237a… appears to be operating normally. There is no indication of an active exploit or drain…
  No action required."* The agent correctly **declined to act** on a healthy vault, so the breaker
  stayed active (`RemediationVerdict`, `acted = false`). The agent-first loop — AI given a tool,
  reasons, and decides whether to take on-chain action — works end-to-end. The live response also
  **confirmed the return-tuple format** (leading `finishReason` string), so the callback decoder is
  validated against real platform bytes.
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
- **`inferToolsChat` (autonomous remediation) — implemented (Tier-2d):** the Somnia team confirmed
  the `onchainTools` tuple (`struct OnchainTool { string signature; string description; }`) and the
  canonical selector `0xd0683905` (locked by `test_InferToolsChat_SelectorMatchesLiveABI`).
  `requestAutonomousRemediation` offers the LLM one safe tool (`pause()`) and latches when the
  agent returns that tool call. **Verified live** (guardian v3): a real `inferToolsChat` reached
  validator consensus and the full return-tuple `(string,string,string[],string[],uint256[],
  bytes[])` was confirmed against on-chain bytes. The callback now **fully decodes
  `pendingToolCalls`** (isolated in try/catch) and matches each call's 4-byte selector against the
  whitelisted `pause()` (`0x8456cb59`) — arbitrary agent calldata is **never executed**, only the
  one safe action is honored. See `DISCORD_QUESTION.md`.

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
- [x] **82 passing tests** (unit + integration + edge + fuzz · see QA_REPORT.md)
- [x] Tier-2d autonomous remediation (`inferToolsChat`) — **deployed + verified live** (selector
      `0xd0683905` test-locked; consensus reached; AI declined to act on a healthy vault)
- [x] All tiers deployed + live-verified on Somnia testnet (real validator consensus):
      Tier-1 (block), Tier-2 LLM (score 0, 2 validators), Tier-2b price oracle, Tier-2c JSON
      threat, Tier-3 reactivity
- [x] Interactive frontend dashboard live on Vercel
- [ ] Demo video (2–5 min)
- [x] Full `pendingToolCalls` decode + `pause()`-selector whitelist (safety: arbitrary agent
      calldata is never executed) — request-side, selector, live consensus all confirmed
- [ ] (stretch) multi-tool execution loop (append tool result, re-call until `finishReason=="stop"`)
