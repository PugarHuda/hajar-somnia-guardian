# Hajar — Encode Club Somnia Agentathon Submission

Final submission package. Copy-paste each section into the Encode form.

---

## Project Name
```
Hajar
```

---

## Project Description
```
Hajar is an autonomous DeFi guardian on Somnia's Agentic L1. It protects any DeFi protocol
from drains and exploits through nine defense tiers — combining instant same-block circuit
breakers with AI risk scoring run inside Somnia validator consensus, a self-learning threat
intelligence engine that accumulates exploit knowledge on-chain, and a discoverable ERC-8004
Trustless Agent identity. Every tier is live on Somnia testnet with zero mocks: real validator
consensus, real Reactivity subscriptions, real on-chain data.
```

---

## Challenge Explanation
*(How you are incorporating: "Build the most novel and high-impact agent-driven application on Somnia")*

```
Hajar demonstrates agent-native design across three dimensions:

1. USES agents — All three Somnia agent types are wired into the guardian:
   • LLM Inference (Qwen3-30B): consensus-verified 0–100 risk scoring (inferNumber) and
     autonomous remediation — the AI is offered a pause() tool and decides to act (inferToolsChat).
   • JSON API (fetchUint): external price-oracle sanity checks (Tier-2b) and structured threat
     scores from live feeds (market-stress = 10 learned by consensus from Fear & Greed Index).
   • Parse Website (ExtractANumber): scrapes rekt.news and security advisories for exploit
     threat levels (Tier-2c); self-learning loop rotates sources round-robin per category.

2. IS an agent — HajarAgentRegistry is a minimal ERC-721 identity registry (ERC-8004 Trustless
   Agents standard, live on ETH mainnet since Jan 2026). Hajar is agentId 1 with a portable
   on-chain identity and /.well-known/agent-card.json. Other agents discover it, read its
   capabilities (MCP endpoint, threat-intel feed, x402Support flag), and verify its identity
   via ownerOf() — no trusted intermediary.

3. RUNS autonomously 24/7 — GitHub Actions keeper runs checkTvlDrop every 2 hours and
   deep threat scans + learning daily. The self-learning feedback loop uses all three Somnia
   agent types to build an on-chain knowledge base, then injects the learned threatLandscape()
   into the AI's risk prompt — proven live: learned market-stress=9, AI returned risk=75
   by validator consensus, informed by that learning.
```

---

## Submission Details
*(Detailed explanation of what you built, process, key achievements)*

```
WHAT HAJAR IS
Hajar is a multi-tenant DeFi security layer. Any protocol calls registerProtocol() to get
protected. From that point, nine defense tiers guard every withdrawal:

SYNCHRONOUS TIERS (same block, no waiting):
• Tier 1  — Hard rule: single-tx drain ≥ hardBps OR velocity ≥ rapidBps → instant revert.
• Tier 1c — Spot-price guard: reads vault.spotPrice() inline, reverts on atomic flash-loan
            price deviation. The only tier fast enough to stop a same-tx manipulation.
• Tier 1d — Vault-wide outflow budget (ERC-7265 rate-limiter): blocks once cumulative drain
            across ALL users hits budgetBps — closes the sybil slow-drain gap.

ASYNCHRONOUS AI TIERS (Somnia validator consensus):
• Tier 2  — LLM risk score: grey-zone activity → inferNumber → 0–100 risk score by validator
            subcommittee → latch if score ≥ threshold.
• Tier 2b — Price oracle: JSON API fetchUint checks external price; divergence latches.
• Tier 2c — Threat intel: Parse Website scrapes security feeds for a 0–100 threat score;
            self-updating, rotating sources. High score latches.
• Tier 2d — Autonomous remediation: inferToolsChat offers the AI a pause() tool. The AI
            decides whether to use it. Verified live: correctly declined on healthy vault.

EVENT-DRIVEN:
• Tier 3  — Reactivity: real Somnia Reactivity subscription fires on withdrawal events,
            latches in a separate execution. Verified live: +20 blocks, no keeper required.
• TVL-drop detector: samples totalAssets(), latches when TVL falls more than recorded outflow
  — catches drains that bypass the withdrawal hook entirely.

SELF-LEARNING THREAT INTELLIGENCE
HajarThreatLearner v2 uses all three Somnia agent types with rotating source pools to build
an on-chain knowledge base per exploit category. The feedback loop: assessRisk() injects the
learned threatLandscape() string into an inferNumber prompt so the AI's judgment is shaped by
what Hajar learned from the web. Live-proven on-chain.

STANDARDS COMPOSED
• ERC-7265 (DeFi Circuit Breaker Standard): Tier-1d IS the ERC-7265 rate-limiter, extended
  with validator-consensus AI on the grey zone.
• ERC-8004 (Trustless Agents): Hajar is a first-class on-chain agent with portable identity,
  composable trust model (crypto-economic = Somnia validator consensus), and MCP discovery.
• x402 (agent payments): x402Support in agent card — path to Hajar-as-a-Service.

DEPLOYED — Somnia Shannon testnet (chainId 50312)
• HajarGuardian v4:          0xf47D21Afd23639870c5185462B2F418eF59d6F67
• HajarThreatLearner v2:     0x97BE2B347682D72D98a2965ADa4947EA1B2B8Acc
• HajarAgentRegistry ERC-8004: 0xEa28EDF008A204BFeD65bD093ad5BC219fd35152  (agentId 1)
• HajarReactiveSubscriber:   0xd6Fa24d9e388D12086D430e9F14ff99980E7789b  (subscriptionId 5981959)
• ProtectedVault:            0xe349707D8BAfA05BC7dd2A2dE16638CBE4673043

QUALITY
82 Foundry tests (0 failing), fuzz tests, integration tests, edge cases.
via_ir=true required (contract was 26KB, optimized to 21.6KB under EIP-170 limit).
Zero mocks in production — every value read live on-chain.
GitHub Actions autonomous keeper: checkTvlDrop every 2h, deep scans daily.
```

---

## Link to Code
```
https://github.com/PugarHuda/hajar-somnia-guardian
```

---

## Link to Presentation
```
https://hajar-somnia-guardian.vercel.app/slide
```

---

## Live Demo Link
```
https://hajar-somnia-guardian.vercel.app
```

---

## Link to Demo Video
```
[UPLOAD docs/hajar-full.mp4 to YouTube (Unlisted) first, then paste URL here]

Video file: docs/hajar-full.mp4 (249s = 4m09s)
Contents:
  0:00–2:06  Pitch deck (9 slides with VO narration)
  2:06–4:09  Live interactive demo — real wallet, real on-chain txs:
             /defense  → connect wallet, deposit, drain blocked by Tier-1, AI escalation
             /intelligence → on-chain knowledge base, market-stress=10, feedback loop
             /agents   → 3 Somnia agents, live consensus feed, why connect wallet
             /identity → ERC-8004 agentId 1, verify walkthrough, standards

YouTube upload steps:
1. Go to studio.youtube.com → Upload → select docs/hajar-full.mp4
2. Title: "Hajar — Autonomous DeFi Guardian on Somnia (Agentathon Demo)"
3. Visibility: Unlisted
4. Paste the YouTube URL here
```

---

## Files to Upload (Submission Files section)
- `docs/hajar-full.mp4` — full video (pitch + demo), 249s
- *(optional)* `docs/hajar-pitch.mp4` — pitch deck only, 126s

---

## Checklist before submitting
- [ ] Video uploaded to YouTube (Unlisted) → URL pasted above
- [ ] Vault has STT balance (judges can test live defense page)
- [ ] Guardian has STT for AI escalations (fund() if needed)
- [ ] Form submitted before Wed Jun 11, 2026 23:59 UTC-12
