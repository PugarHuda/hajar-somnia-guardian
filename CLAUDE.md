# Hajar — Project Memory

Autonomous DeFi Guardian on **Somnia** (Agentic L1). Submission for the **Somnia Agentathon**
(deadline 8 Jun 2026, prize pool $5,000, also a get-hired track).

## Stack
- **Solidity 0.8.24** + **Foundry** (forge 1.5.1). EVM target: `cancun`.
- No JS/frontend yet. Pure contracts + Foundry tests.

## Run
```bash
forge build
forge test -vv          # 7 tests, all passing
forge script script/Deploy.s.sol --rpc-url somnia_testnet --broadcast --private-key $PRIVATE_KEY
```

## Architecture (the core idea)
Two-tier security layer. Somnia Agent calls are **async** (request → callback), so:
- **Tier 1** (`HajarGuardian.checkWithdrawal` → `_isHardViolation`): synchronous deterministic
  rule, blocks blatant drains same-block by returning false (vault reverts). Does NOT latch
  `paused` — reverting the trigger tx would roll the latch back anyway.
- **Tier 2** (`_escalateToAI` → `handleResponse`): grey-zone activity escalated to Somnia
  **LLM Inference agent** (`inferNumber`, 0–100 risk score). Validators reach consensus;
  callback latches the circuit breaker if score >= `riskThreshold`.

## Key files
- `src/HajarGuardian.sol` — guardian. **`_isHardViolation()` is the tunable policy brain.**
- `src/ProtectedVault.sol` — demo protected protocol.
- `src/interfaces/ISomniaAgents.sol` — Somnia platform + agent interfaces.
- `src/mocks/MockAgentPlatform.sol` — local validator simulation (`fulfillNumber`).

## Conventions
- Custom errors (not `require` strings) for reverts.
- Events for every state transition (judges audit on-chain behavior).
- Callbacks MUST guard `msg.sender == address(platform)` + track pending request ids.
- Contract needs STT balance (`fund()`) to pay for AI escalations; `receive()` accepts rebates.

## ⚠️ Known unverified surface
`ISomniaAgents` is reconstructed from docs, self-consistent with the mock. Before testnet/
mainnet, reconcile the `Request` struct + agent selectors with the official ABI.
Grep `TODO(verify)`.

## Deployed (Somnia testnet — multi-tenant, all tiers live, no mocks)
- HajarGuardian (multi-tenant) `0x6BA6c7c52413A592F7799288CbC42d187ddda2f8`
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
