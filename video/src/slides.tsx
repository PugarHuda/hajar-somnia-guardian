export type Slide = {
  seconds: number;
  audio: string; // VO wav under public/vo/
  kicker?: string;
  title: string;
  bullets: string[];
  caption: string; // burned-in subtitle (the narration line)
  accentTitle?: boolean; // big hero title
};

// 8bitcn pitch — anchored on self-learning. Captions == VIDEO_SCRIPT.md Part B (word-for-word VO).
export const SLIDES: Slide[] = [
  {
    seconds: 8.5,
    audio: "vo/slide-1.wav",
    kicker: "SOMNIA AGENTATHON · AGENTIC L1",
    title: "HAJAR",
    bullets: ["Autonomous DeFi Guardian", "AI run inside validator consensus"],
    caption:
      "Hajar — an autonomous DeFi guardian on Somnia's Agentic Layer-1. AI run inside validator consensus.",
    accentTitle: true,
  },
  {
    seconds: 9.4,
    audio: "vo/slide-2.wav",
    kicker: "The problem",
    title: "DeFi bleeds billions, reactively",
    bullets: [
      "Exploits drain protocols in seconds",
      "Audits are one-time; monitoring alerts too late",
      "No autonomous, on-chain breaker that learns",
    ],
    caption:
      "DeFi bleeds billions, reactively. Exploits drain in seconds, audits are one-time, monitoring alerts after the money is gone.",
  },
  {
    seconds: 13.4,
    audio: "vo/slide-3.wav",
    kicker: "The solution",
    title: "A breaker that thinks and acts",
    bullets: [
      "Synchronous deterministic blocks — same block",
      "Consensus AI judges the grey zone",
      "Reactivity + a self-learning brain run 24/7, no human",
    ],
    caption:
      "Hajar puts the whole loop on-chain: deterministic blocks, consensus AI for the grey zone, reactivity and a learning brain running twenty-four-seven.",
  },
  {
    seconds: 15.3,
    audio: "vo/slide-4.wav",
    kicker: "Defense in depth",
    title: "Nine tiers — every one live",
    bullets: [
      "Hard rule · spot guard · outflow budget (sync)",
      "AI risk · price oracle · threat intel · AI remediation",
      "Validator-triggered reactivity · TVL-drop detector",
    ],
    caption:
      "Nine tiers, every one live — hard rules, a flash-loan spot guard, a sybil-drain outflow budget, AI scoring, price and threat checks, autonomous remediation, reactivity, and a bypass-drain detector.",
  },
  {
    seconds: 16.9,
    audio: "vo/slide-5.wav",
    kicker: "The differentiator",
    title: "It learns exploits — by itself",
    bullets: [
      "Reads security feeds via all 3 Somnia agents",
      "Writes what it learns into an on-chain knowledge base",
      "Learned market-stress by consensus — re-learned 10 → 9 live",
    ],
    caption:
      "Here's what nobody else has. Hajar learns new exploits through all three Somnia agents and keeps an on-chain knowledge base current. It learned a market-stress level by validator consensus, and re-learned it as the live index moved. Real, and unique.",
  },
  {
    seconds: 12.1,
    audio: "vo/slide-6.wav",
    kicker: "Agent-native, end to end",
    title: "Uses agents — and IS an agent",
    bullets: [
      "Uses Somnia's LLM, JSON and Parse agents",
      "Registered ERC-8004 Trustless Agent (agentId 1)",
      "Trust = Somnia validator consensus",
    ],
    caption:
      "Hajar uses Somnia's agents, and it is an agent — a registered ERC-8004 Trustless Agent other agents can discover and trust, where trust is Somnia's validator consensus.",
  },
  {
    seconds: 14.2,
    audio: "vo/slide-7.wav",
    kicker: "Standards, not a one-off",
    title: "ERC-7265 · ERC-8004 · x402",
    bullets: [
      "ERC-7265 — DeFi circuit-breaker, extended with AI",
      "ERC-8004 — on-chain agent identity",
      "x402 — agent payments (Hajar-as-a-Service)",
    ],
    caption:
      "It's not a one-off. ERC-7265 the circuit-breaker standard extended with AI, ERC-8004 for agent identity, and x402 for agent payments.",
  },
  {
    seconds: 11.7,
    audio: "vo/slide-8.wav",
    kicker: "Proof",
    title: "Live & verified on Somnia",
    bullets: [
      "Guardian · registry · learner · reactive subscriber — deployed",
      "78 tests · 0 failing · 0 mocks",
      "Every value read on-chain",
    ],
    caption:
      "Guardian, registry, threat learner, reactive subscriber — all deployed and verified. Seventy-eight tests, zero failing, zero mocks.",
  },
  {
    seconds: 10.9,
    audio: "vo/slide-9.wav",
    kicker: "Why Somnia",
    title: "Only possible on an Agentic L1",
    bullets: [
      "AI inside validator consensus — auditable receipts",
      "Sub-cent fees — check every withdrawal",
      "Reactivity is a first-class primitive",
    ],
    caption:
      "Only an Agentic Layer-1 makes this possible — AI inside validator consensus, sub-cent fees to check every withdrawal, and reactivity as a first-class primitive.",
  },
  {
    seconds: 8.7,
    audio: "vo/slide-10.wav",
    kicker: "The ask",
    title: "Protect every protocol",
    bullets: ["Standards-compliant · agent-native · self-learning · live", "hajar-somnia-guardian.vercel.app"],
    caption:
      "Hajar is production-shaped today — standards-compliant, agent-native, self-learning, and live on Somnia. Hajar.",
  },
];
