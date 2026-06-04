# Hajar — Project Memory

Autonomous DeFi Guardian on **Somnia** (Agentic L1). Submission for the **Somnia Agentathon**
(deadline 8 Jun 2026, prize pool $5,000, also a get-hired track).

## Stack
- **Solidity 0.8.24** + **Foundry** (forge 1.5.1). EVM target: `cancun`.
- No JS/frontend yet. Pure contracts + Foundry tests.

## Run
```bash
forge build
forge test -vv          # 28 tests, all passing
forge script script/Deploy.s.sol --rpc-url somnia_testnet --broadcast --private-key $PRIVATE_KEY
```

## Architecture (the core idea)
Multi-tenant three-tier security layer. Somnia Agent calls are **async** (request → callback), so:
- **Tier 1** (`HajarGuardian.checkWithdrawal`): synchronous deterministic rule (single-tx drain
  `>= hardBps` OR windowed velocity `>= rapidBps`), blocks blatant drains same-block by returning
  false (vault reverts). Does NOT latch `paused` — reverting the trigger tx would roll the latch
  back anyway. The per-protocol thresholds (`hardBps/rapidBps/greyBps/risk`) ARE the policy brain.
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

## Key files
- `src/HajarGuardian.sol` — guardian. The per-protocol thresholds (`hardBps/rapidBps/greyBps/risk`
  set via `registerProtocol`/`setThresholds`) ARE the tunable policy brain; Tier-1 logic lives
  inline in `checkWithdrawal()`.
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
- **HajarGuardian v2 (current, all agents)** `0x42245cEef96D432c8DA3918dc66D3663E36bFE72` —
  adds Tier-2b price oracle + Tier-2c threat intel. Live-verified 4 Jun 2026: LLM AIVerdict
  (score 0, 2 validators), PriceVerdict (EUR 0.861 fetched, 641bps div, no alarm), JSON
  ThreatVerdict (1, no alarm). Parse-Website scrape returned non-Success (validators diverge) →
  fails safe. Frontend points here.
- HajarGuardian v1 (Tier-1/2/3 first proven) `0x6BA6c7c52413A592F7799288CbC42d187ddda2f8`
  — the Tier-3 subscriber is immutably bound to this one.
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
