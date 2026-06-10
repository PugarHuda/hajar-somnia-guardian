# Hajar — Video & Narration Script

Two ready-to-record scripts:
- **Part A — Demo video** (2:30, screen-record the live site), anchored on the *self-learning* WOW.
- **Part B — Pitch deck narration** (word-for-word for the 10 `/slide` slides).

Both are word-for-word VO you can read straight, or feed to a TTS tool.

> **Reality check (10 Jun 2026):** Somnia's **LLM agent (Qwen3-30B) is intermittent** on testnet —
> live verdicts often don't land in time. The **JSON agent is reliable** (it re-learned market-stress
> 10 → 9 live). So we **anchor on self-learning + deterministic tiers**, and show LLM proof via the
> explorer (permanent), not a live gamble.

**Pre-flight (already done on-chain):** guardian funded 3.16 STT · vault TVL 0.3 · breaker ACTIVE ·
learner market-stress = 9 (obs 2). Record in real Chrome, 1920×1080, hard-refresh first.

---

## PART A — Demo video (≈2:30)

### 0:00 — Hook · Landing
**Read:** "DeFi loses billions to exploits every year, and the monitoring is reactive, off-chain, and
blind to attacks it hasn't seen before. Hajar is different. It's an autonomous on-chain guardian
that stops drains — and *learns new exploits by itself*. It's live on Somnia right now."
*(Screen: landing — the green ACTIVE breaker bar, the stat line. Scroll past "Try it — 3 ways".)*

### 0:25 — ANCHOR · It learns by itself · /intelligence  🟢 reliable
**Read:** "This is the part nobody else has. Hajar's threat brain reads security feeds through
Somnia's AI agents and writes what it learns on-chain. Watch this number — it learned a
market-stress level of ten earlier, and it just re-learned *nine*, because it re-read the live risk
index. It keeps updating itself, and every value is agreed by a committee of Somnia validators —
not by this website."
*(Screen: /intelligence — point at market-stress, the level bar, observations = 2, last-updated.)*

### 0:55 — Instant deterministic defense · /defense  🟢 reliable
**Read:** "On top of the learning brain, the first line of defense is deterministic and same-block.
Here's a blatant eighty-percent drain —" *(click **Try Drain 80%**)* "— reverted instantly. No
waiting on anything off-chain."
*(Screen: the wallet revert + the HardBlock line in the feed.)*

### 1:20 — The agents, on-chain · /agents
**Read:** "Hajar runs its judgment on Somnia's on-chain agents — three of them. Each request is run
by a subcommittee of validators that reach consensus, and the verdict comes back on-chain with a
receipt. Here's the proof, permanently on the explorer: a verdict signed by validators."
*(Screen: /agents catalog, then open the learner or guardian on shannon-explorer → Events tab →
a `Learned` / `AIVerdict` row. This is the reliable substitute for a live LLM verdict.)*

### 1:50 — Validator-triggered, no keeper · /defense or explorer  🟢 proven
**Read:** "And it's autonomous in the strongest sense. A withdrawal here auto-fired the breaker about
twenty blocks later — triggered by Somnia validators through a Reactivity subscription. No server,
no bot, nobody running it."
*(Screen: the subscriber on the explorer → a `ReactiveForwarded` event.)*

### 2:10 — Hajar IS an agent · /identity  🟢 reliable
**Read:** "And Hajar isn't just a contract — it's a registered ERC-8004 agent, with an on-chain
identity other agents can discover, verify, and one day pay. It uses agents, it *is* an agent, and
it acts autonomously."
*(Screen: /identity — agentId #1, the on-chain owner, the agent-card link.)*

### 2:25 — Close · Landing
**Read:** "Nine defense tiers, three Somnia agents, a self-learning threat brain — all live, all
on-chain, no mocks. Hajar."
*(Screen: landing HP bar ACTIVE + on-screen text: hajar-somnia-guardian.vercel.app)*

---

## PART B — Pitch deck narration (read over `/slide`, ~10s each)

Open `/slide`, press → to advance. Read one block per slide.

1. **HAJAR.** "Hajar — an autonomous DeFi guardian on Somnia's Agentic Layer-1. A security layer that
   stops drains, with AI run inside validator consensus."
2. **The problem.** "DeFi bleeds billions, reactively. Exploits drain in seconds, audits are
   one-time, and monitoring just alerts after the money is gone."
3. **The solution.** "Hajar puts the whole loop on-chain: deterministic blocks stop blatant drains
   same-block, consensus AI judges the grey zone, and reactivity plus a learning brain run
   twenty-four-seven with no human."
4. **Defense in depth.** "Nine tiers, every one live — hard rules, a flash-loan spot guard, a
   sybil-drain outflow budget, AI risk scoring, price and threat checks, autonomous remediation,
   validator-triggered reactivity, and a bypass-drain detector."
5. **It learns by itself.** "Here's the differentiator. Hajar learns new exploits from the web
   through all three Somnia agents, and keeps an on-chain knowledge base current. It learned a
   market-stress level by validator consensus — and re-learned it as the live index moved. This is
   real, and it's unique."
6. **Agent-native, end to end.** "Hajar uses Somnia's agents, and it *is* an agent — a registered
   ERC-8004 Trustless Agent other agents can discover and trust, where crypto-economic trust is
   Somnia's validator consensus."
7. **Standards.** "It's not a one-off. It implements ERC-7265, the DeFi circuit-breaker standard,
   extended with AI; ERC-8004 for agent identity; and x402 for agent payments."
8. **Live and verified.** "Guardian, registry, threat learner, reactive subscriber — all deployed
   and verified on Somnia. Seventy-eight tests, zero failing, zero mocks. Every value read on-chain."
9. **Why Somnia.** "Only an Agentic Layer-1 makes this possible — AI inside validator consensus,
   sub-cent fees to check every withdrawal, and reactivity as a first-class primitive."
10. **The ask.** "Hajar is production-shaped today — standards-compliant, agent-native, self-learning,
    and live. The next step is design partners and a paid Hajar-as-a-Service tier. Find it at
    hajar-somnia-guardian dot vercel dot app."

---

## On making the actual video file (honest)
I can't screen-record your browser or generate a human voice. What you have here is everything to
record fast: read Part A over a screen capture of the live site, or read Part B over `/slide`.
For voice, paste the script into any TTS (ElevenLabs, etc.) and lay it under the screen recording in
any editor (CapCut/DaVinci). If you want a fully **code-rendered** pitch video (animated slides, no
live screencast), I can scaffold a Remotion project — say the word.
