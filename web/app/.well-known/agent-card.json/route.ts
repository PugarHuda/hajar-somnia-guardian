import { NextResponse } from "next/server";
import { ADDRESSES, REGISTRY } from "../../lib/somnia";

export const dynamic = "force-dynamic";

/**
 * ERC-8004 "Trustless Agents" Agent Registration File (a.k.a. Agent Card), served at the
 * conventional .well-known path so any A2A/MCP-speaking agent can discover Hajar, learn what it
 * does, and verify its on-chain identity — without any pre-existing trust.
 *
 * Schema: https://eips.ethereum.org/EIPS/eip-8004#registration-v1
 * This makes Hajar a first-class autonomous agent on Somnia's Agentic L1, not just a contract:
 * other agents can find it (services), pay it (x402Support), and trust it via Somnia's
 * validator-consensus (supportedTrust: crypto-economic).
 */
export async function GET(request: Request) {
  const base = new URL(request.url).origin;

  // ERC-8004 registrations point at an on-chain Identity Registry: {namespace}:{chainId}:{registry}.
  // Populated once the HajarAgentRegistry is deployed (REGISTRY.address / REGISTRY.agentId).
  const registrations = REGISTRY.address
    ? [{ agentId: REGISTRY.agentId, agentRegistry: `eip155:50312:${REGISTRY.address}` }]
    : [];

  return NextResponse.json({
    type: "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
    name: "hajar-guardian",
    description:
      "Autonomous DeFi security guardian on Somnia's Agentic L1. A multi-tier circuit breaker " +
      "(ERC-7265-aligned) that protects DeFi protocols from drains and exploits, combining " +
      "synchronous deterministic blocks with consensus-verified AI risk scoring, price-oracle and " +
      "threat-intel checks, and validator-triggered reactivity. Other agents can query a protocol's " +
      "live security posture and subscribe it for protection.",
    image: `${base}/icon.png`,
    services: [
      { name: "MCP", endpoint: `${base}/api/mcp`, version: "2025-06-18" },
      { name: "state", endpoint: `${base}/api/state`, version: "1.0.0" },
      { name: "web", endpoint: base },
    ],
    // x402 (Coinbase agent-payments) — vision: agents pay-per-risk-query for Hajar-as-a-Service.
    x402Support: false,
    active: true,
    registrations,
    // Somnia validators reach consensus on every AI verdict => crypto-economic trust. On-chain
    // verdict history (AIVerdict/ThreatVerdict events) is the reputation surface.
    supportedTrust: ["reputation", "crypto-economic"],
    contracts: {
      chain: { namespace: "eip155", id: 50312, name: "Somnia Shannon testnet" },
      guardian: ADDRESSES.guardian,
      vault: ADDRESSES.vault,
      platform: ADDRESSES.platform,
    },
    skills: [
      "defi-circuit-breaker",
      "drain-detection",
      "ai-risk-scoring",
      "oracle-manipulation-detection",
      "threat-intelligence",
      "autonomous-remediation",
    ],
  });
}
