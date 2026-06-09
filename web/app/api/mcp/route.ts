import { NextResponse } from "next/server";
import { ADDRESSES } from "../../lib/somnia";

export const dynamic = "force-dynamic";

/**
 * A lite, MCP-flavoured discovery manifest so other autonomous agents (the Somnia thesis:
 * the main users are AIs) can find Hajar and read a protocol's live security posture.
 * Not a full stdio/JSON-RPC MCP server — a read-only HTTP tool catalog.
 */
export async function GET() {
  // Pin to a canonical origin — this manifest is consumed by other agents as a discovery anchor,
  // so it must not reflect an attacker-controllable Host header.
  const base = process.env.HAJAR_PUBLIC_ORIGIN ?? "https://hajar-somnia-guardian.vercel.app";
  return NextResponse.json({
    name: "hajar-guardian",
    version: "1.0.0",
    description:
      "Autonomous DeFi guardian on Somnia. Multi-tier defense: synchronous hard/velocity/outflow- " +
      "budget/spot-price blocks, async AI risk + price-oracle + threat-intel + tools-chat " +
      "remediation, validator-triggered reactivity, and a TVL-drop detector for bypass-hook " +
      "drains. Query a protocol's live circuit-breaker status, thresholds, protected TVL, and the " +
      "Somnia AI agents wired to it.",
    chain: { id: 50312, name: "Somnia Shannon testnet" },
    contracts: {
      guardian: ADDRESSES.guardian,
      vault: ADDRESSES.vault,
      platform: ADDRESSES.platform,
    },
    tools: [
      {
        name: "get_guardian_state",
        description:
          "Returns the demo protocol's live state: paused (circuit-breaker), per-protocol " +
          "thresholds (hard/rapid/grey bps + AI risk score), protected TVL, and the three " +
          "Somnia agent ids (LLM Inference, JSON API, Parse Website).",
        method: "GET",
        url: `${base}/api/state`,
        parameters: {},
        returns: "application/json",
      },
      {
        name: "get_threat_intelligence",
        description:
          "Returns Hajar's self-learned threat knowledge base: per exploit category (reentrancy, " +
          "oracle-manipulation, flash-loan, …) the latest learned threat level (0..100), when it " +
          "was last updated, and how many observations — learned autonomously from external " +
          "security feeds via the Somnia Parse Website + JSON API + LLM agents.",
        method: "GET",
        url: `${base}/api/learn`,
        parameters: {},
        returns: "application/json",
      },
    ],
    docs: "https://github.com/PugarHuda/hajar-somnia-guardian",
  });
}
