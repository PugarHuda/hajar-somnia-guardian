# Hajar — Project Memory

Autonomous DeFi Guardian on **Somnia** (Agentic L1). Submission for the **Somnia Agentathon**
(deadline 8 Jun 2026, prize pool $5,000, also a get-hired track).

## Stack
- **Solidity 0.8.24** + **Foundry** (forge 1.5.1). EVM target: `cancun`.
- No JS/frontend yet. Pure contracts + Foundry tests.

## Run
```bash
forge build
forge test -vv          # 42 tests, all passing
forge script script/Deploy.s.sol --rpc-url somnia_testnet --broadcast --private-key $PRIVATE_KEY
```

## Architecture (the core idea)
Multi-tenant three-tier security layer. Somnia Agent calls are **async** (request → callback), so:
- **Tier 1** (`HajarGuardian.checkWithdrawal`): synchronous deterministic rule (single-tx drain
  `>= hardBps` OR windowed velocity `>= rapidBps`), blocks blatant drains same-block by returning
  false (vault reverts). Does NOT latch `paused` — reverting the trigger tx would roll the latch
  back anyway. The per-protocol thresholds (`hardBps/rapidBps/greyBps/risk`) ARE the policy brain.
- **Tier 1c** (`_spotPriceOk`, opt-in `setSpotGuard`): synchronous spot-price deviation guard. If
  the vault exposes `spotPrice()`, reads it inline and returns false (atomic block) when divergence
  from `referencePrice` `>= maxDeviationBps`. The only tier fast enough to stop an **atomic
  flash-loan** price manipulation (async AI is always a block too late). Default-off.
- **Tier 1d** (`_outflowBudgetOk`, opt-in `setOutflowBudget`): vault-wide cumulative outflow budget.
  Aggregates outflow across **all** users in a window and atomically blocks once the vault bled
  `budgetBps` of window-start TVL — closes the **sybil slow-drain** gap the per-user velocity tier
  can't see. Sync, never latches. Default-off.
- **TVL-drop detector** (`checkTvlDrop`, opt-in `setTvlMonitor`): catches drains that **bypass the
  withdrawal hook** (other buggy fn, direct transfer). Samples `totalAssets()`; latches in a
  separate execution when TVL falls MORE than the guarded outflow recorded since baseline. Wire to
  cron or the reactive monitor. Default-off.
- **Tier 2** (`_escalateToAI` → `handleResponse`): grey-zone activity (`>= greyBps`) escalated to
  Somnia **LLM Inference agent** (`inferNumber`, 0–100 risk score). Validators reach consensus;
  callback latches the breaker if score `>= risk`.
- **Tier 2b** (`requestPriceCheck` → `handleResponse`, `Kind.Price`): external price sanity via
  **JSON API agent** (`fetchUint`); divergence from `referencePrice` latches the breaker.
- **Tier 2c** (`requestThreatScan` / `requestThreatScanJson`, `Kind.Threat`): self-updating threat
  intel via **Parse Website** (`ExtractANumber`) + JSON API agents; high threat score latches.
- **Tier 2d** (`requestAutonomousRemediation`, `Kind.Tools`): LLM **tools-chat** (`inferToolsChat`,
  selector `0xd0683905`, OnchainTool{string signature; string description}). AI is offered the
  `pause()` tool and decides whether to ACT; callback latches on finishReason=="tool_calls".
  Safe-by-design (only a pause, never raw agent calldata). Callback decodes only finishReason
  (try/catch) — full pendingToolCalls decode pending a live response sample.
- **Tier 3** (`HajarReactiveSubscriber.onEvent` → `onReactiveSignal`): real validator-triggered
  Reactivity subscription that latches in a separate execution.

## Standards (positioning — grounded, not hype)
- **ERC-7265** (DeFi Circuit Breaker Standard): Tier-1d outflow budget IS this standard's
  rate-limiter; Hajar extends it with validator-consensus AI. Citation only + framing.
- **ERC-8004** (Trustless Agents, live ETH mainnet 29 Jan 2026): Hajar is a registered on-chain
  agent. `src/HajarAgentRegistry.sol` = minimal Identity Registry (ERC-721 + register/metadata);
  `web/app/.well-known/agent-card.json` = ERC-8004 Agent Registration File (services, supportedTrust
  ["reputation","crypto-economic"] = validator consensus, x402Support). Makes Hajar discoverable +
  trustable by other agents — the core Agent-First win.
- **x402** (Coinbase agent payments): `x402Support` flag in the card; Hajar-as-a-Service vision.

## Key files
- `src/HajarGuardian.sol` — guardian. The per-protocol thresholds (`hardBps/rapidBps/greyBps/risk`
  set via `registerProtocol`/`setThresholds`) ARE the tunable policy brain; Tier-1 logic lives
  inline in `checkWithdrawal()`. Hardening tiers (opt-in): outflow budget, spot-price guard,
  TVL-drop detector. NOTE: `via_ir = true` is REQUIRED in foundry.toml (without it the contract
  exceeds EIP-170 24KB).
- `src/HajarAgentRegistry.sol` — ERC-8004 Identity Registry (separate contract, ~4KB).
- `src/ProtectedVault.sol` — demo protected protocol.
- `src/HajarReactiveSubscriber.sol` — real Tier-3 (validator-triggered Reactivity subscription).
- `src/interfaces/ISomniaAgents.sol` — Somnia platform + agent interfaces (reconciled to live ABI).
- `test/mocks/MockAgentPlatform.sol` — local validator simulation (`fulfillNumber`); test-only.

## Conventions
- Custom errors (not `require` strings) for reverts.
- Events for every state transition (judges audit on-chain behavior).
- Callbacks MUST guard `msg.sender == address(platform)` + track pending request ids.
- Contract needs STT balance (`fund()`) to pay for AI escalations; `receive()` accepts rebates.

## ABI status
`ISomniaAgents` is **reconciled to the live platform ABI** (15-field `Request`, real agent
selectors, verified by live testnet calls). No `TODO(verify)` left in `src/`. The one
still-open ABI gap is `inferToolsChat`'s `onchainTools` tuple (not published) — see
`DISCORD_QUESTION.md`; don't guess that selector.

## Deployed (Somnia testnet — multi-tenant, all tiers live, no mocks)
- **HajarGuardian v3 (current, all agents + remediation)** `0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c`
  — v2 features + **Tier-2d autonomous remediation (inferToolsChat)**. Live-verified 4 Jun 2026:
  inferToolsChat reached validator consensus, AI reasoned "No action required" on a healthy vault
  → finishReason="stop", RemediationVerdict acted=false (correct, no false latch). Raw fulfill
  calldata confirmed tuple format (leading finishReason string) → decoder validated. Frontend
  points here. Vault `0x237A…` re-pointed to v3.
- HajarGuardian v2 `0x42245cEef96D432c8DA3918dc66D3663E36bFE72` — v2 added Tier-2b/2c; live-verified
  LLM AIVerdict (score 0, 2 validators), PriceVerdict (EUR 0.861, 641bps), JSON ThreatVerdict (1).
  Superseded by v3.
- HajarGuardian v1 `0x6BA6c7c52413A592F7799288CbC42d187ddda2f8` (Tier-1/2/3 first proven).
- **Tier-3 subscriber for v3:** `0x5aE10c3c1FE5eCf0b2a44a23E3bB62f7A7deD502` (subscriptionId 4638272,
  33 STT). setMonitor(vault, sub) done on v3. LIVE-VERIFIED: withdrawal 0.01 → ReactiveForwarded
  ~25 blocks later (validator-triggered, no keeper), no false latch. ALL tiers now live on v3.
  (Old subscriber 0x9857 was bound to v1.)
- ProtectedVault `0x237A48d4B05944cC78b2b469F68F1f21D7AdfF39`
- HajarReactiveSubscriber (real Tier-3) `0x9857aF25fFa558C382AbB916803Ee441502b0F8D` (subscriptionId 4542758)
- LLM agentId `12847293847561029384`. Tier-2 AI verified live (scores 0 and 10, real validator consensus).
- Tier-3 verified live: real Reactivity subscription via precompile 0x0100; withdrawal auto-triggered
  the subscriber `onEvent` ~20 blocks later (validator-triggered, no keeper).
- Multi-tenant: registerProtocol(vault,...); per-protocol admin/breaker/thresholds; paused(vault).
- Frontend live: https://hajar-somnia-guardian.vercel.app (auto-deploys from GitHub web/).

## Somnia facts (verified Jun 2026)
- Platform: testnet `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` (chain 50312),
  mainnet `0x5E5205CF39E766118C01636bED000A54D93163E6` (chain 5031).
- Agents: JSON API (0.03 STT/validator), LLM Inference Qwen3-30B (0.07), Parse Website (0.10).
- Deposit = `getRequestDeposit()` + pricePerValidator × subcommitteeSize.
- Agent ids from https://agents.somnia.network. Docs: https://docs.somnia.network/agents
