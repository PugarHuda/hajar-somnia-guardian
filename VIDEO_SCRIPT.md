# Hajar — Demo Video Storyboard (2:40)

The video is what most judges actually watch. Goal: open with the **unique, reliable** beats
(self-learning, instant block), build to the **agent-native climax** (AI takes action). Record the
AI-verdict beats from a take where the verdict actually landed — don't live-gamble the LLM.

- **Live site:** https://hajar-somnia-guardian.vercel.app
- **Record at:** 1920×1080, real Chrome (the pixel fonts + borders render best there), hard-refresh first.
- **Voice:** calm, confident, fast. ~150 words/min. Total ≈ 2:40.
- **Pre-flight:** vault funded + seeded so flows work; guardian funded (≥0.3 STT) for AI calls;
  breaker reset to ACTIVE; do 2–3 rehearsal triggers and screen-record a clean AIVerdict + a
  RemediationVerdict to splice into beats 4–5.

---

## 0:00 — Hook  ·  Landing page
**On screen:** the landing — crest, HAJAR, the green ACTIVE breaker HP bar, the stat line.
**VO:** "DeFi loses billions to exploits every year — and the monitoring is reactive, off-chain,
and blind to new attacks. Hajar is an autonomous on-chain guardian that stops drains *and learns
new exploits by itself*. It's live on Somnia right now."
**Action:** slow scroll past the "Try it — 3 ways" cards.

## 0:25 — WOW #1: it learns by itself  ·  /intelligence  🟢 reliable
**On screen:** the knowledge-base bars; cursor lands on **market-stress = 10**.
**VO:** "This is Hajar's threat brain. It scrapes security feeds through Somnia's AI agents and
records what it learns on-chain. Right now it has learned a market-stress level of 10 — pulled from
a live risk index and **agreed on by a committee of Somnia validators**, not by this website."
**Action:** hover a row; point at the "obs" + last-updated; read the honest "knowledge accumulation"
callout for half a second.

## 0:55 — WOW #2: instant deterministic block  ·  /defense  🟢 reliable
**On screen:** the demo console; connect wallet (or pre-connected).
**VO:** "The first line of defense is deterministic and same-block. Watch a blatant 80%-of-TVL
drain —" *(click **Try Drain 80%**)* "— reverted instantly. No waiting on anything off-chain."
**Action:** the wallet shows the revert; the feed logs `HardBlock`. Cut fast.

## 1:20 — The agents working  ·  /agents  🟡 use a pre-recorded clean take
**On screen:** the 3-agent catalog (wired · ids · costs), then the AgentLab.
**VO:** "Hajar runs its judgment on Somnia's on-chain agents. I'll fire one —" *(click **Make an AI
agent run**)* "— a grey-zone withdrawal escalates to the LLM agent, a subcommittee of validators
runs the model, and the consensus verdict comes back **on-chain**."
**Action:** the feed streams `request → verdict` with a score and validator count; click a row to
open the tx on the explorer for a beat. *(Splice the take where the verdict landed.)*

## 1:50 — WOW #3 (climax): the AI takes action  🟡 pre-recorded
**On screen:** a `RemediationVerdict` line in the feed.
**VO:** "And this is the endgame for an agentic chain. We don't just *ask* the AI for a score — we
give it an on-chain `pause()` tool and let it **decide whether to act**. Here it reasoned on-chain
and chose correctly. The AI is taking autonomous action, verified by consensus — safe by design,
because the worst it can do is pause."

## 2:15 — Hajar IS an agent  ·  /identity  🟢 reliable
**On screen:** agentId #1, the on-chain owner, the agent-card link.
**VO:** "Hajar isn't just a contract — it's a registered ERC-8004 agent other agents can discover,
verify, and one day pay. It uses agents, it *is* an agent, and it acts autonomously."

## 2:30 — Close
**On screen:** back to the landing HP bar (ACTIVE) + the GitHub / live URL.
**VO:** "Nine defense tiers, three Somnia agents, a self-learning threat brain — all live on Somnia,
all on-chain, no mocks. Hajar."
**On screen text:** `hajar-somnia-guardian.vercel.app · github.com/PugarHuda/hajar-somnia-guardian`

---

## B-roll / cutaways (optional, 1–2s each)
- The pixel HP bar flipping ACTIVE → PAUSED → ACTIVE (trip + reset).
- A tx open on shannon-explorer showing the `AIVerdict` event.
- `/api/learn` raw JSON (proves machine-readable, agent-discoverable).
- The autonomous-guardian GitHub Action run (24/7 keeper, no human).

## Reliability cheatsheet
| Beat | Reliable? | Mitigation |
|------|-----------|------------|
| Self-learning (market-stress) | 🟢 always on-chain | — |
| Tier-1 80% drain block | 🟢 deterministic | — |
| ERC-8004 identity | 🟢 on-chain | — |
| AIVerdict (LLM score) | 🟡 intermittent on testnet | pre-record a landed take |
| Tier-2d remediation | 🟡 intermittent | pre-record a landed take |
| Tier-3 reactivity (~20 blocks) | 🟢 proven, slow | time-lapse or pre-record |
