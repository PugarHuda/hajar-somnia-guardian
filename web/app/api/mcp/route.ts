import { NextResponse } from "next/server";
import { ADDRESSES } from "../../lib/somnia";

export const dynamic = "force-dynamic";

/**
 * A lite, MCP-flavoured discovery manifest so other autonomous agents (the Somnia thesis:
 * the main users are AIs) can find Hajar and read a protocol's live security posture.
 * Not a full stdio/JSON-RPC MCP server — a read-only HTTP tool catalog.
 */
export async function GET(request: Request) {
  const base = new URL(request.url).origin;
  return NextResponse.json({
    name: "hajar-guardian",
    version: "1.0.0",
    description:
      "Autonomous DeFi guardian on Somnia. Query a protocol's live circuit-breaker status, " +
      "thresholds, protected TVL, and the Somnia AI agents wired to it.",
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
    ],
    docs: "https://github.com/PugarHuda/hajar-somnia-guardian",
  });
}
