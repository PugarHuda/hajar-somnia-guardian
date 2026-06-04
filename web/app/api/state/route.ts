import { NextResponse } from "next/server";
import { formatEther } from "viem";
import { client, ADDRESSES, guardianAbi, vaultAbi } from "../../lib/somnia";

export const dynamic = "force-dynamic";
export const revalidate = 0;

/**
 * Machine-readable live state of the Hajar guardian + the demo vault, read straight from the
 * Somnia Shannon testnet. Designed to be consumed by other agents (see /api/mcp).
 */
export async function GET() {
  try {
    const g = { address: ADDRESSES.guardian as `0x${string}`, abi: guardianAbi };
    const vault = ADDRESSES.vault as `0x${string}`;
    const [paused, proto, llmId, jsonId, parseId, tvl] = await Promise.all([
      client.readContract({ ...g, functionName: "paused", args: [vault] }),
      client.readContract({ ...g, functionName: "protocols", args: [vault] }),
      client.readContract({ ...g, functionName: "llmAgentId" }),
      client.readContract({ ...g, functionName: "jsonAgentId" }),
      client.readContract({ ...g, functionName: "parseAgentId" }),
      client.readContract({ address: vault, abi: vaultAbi, functionName: "totalAssets" }),
    ]);
    // protocols() is a multi-output getter -> viem returns an array.
    const p = proto as unknown as [boolean, boolean, string, string, bigint, bigint, bigint, bigint];

    return NextResponse.json({
      chain: { id: 50312, name: "Somnia Shannon testnet" },
      guardian: ADDRESSES.guardian,
      vault: ADDRESSES.vault,
      paused: paused as boolean,
      registered: p[0],
      admin: p[2],
      monitor: p[3],
      thresholds: {
        hardBps: Number(p[4]),
        rapidBps: Number(p[5]),
        greyBps: Number(p[6]),
        riskScore: Number(p[7]),
      },
      protectedTvlStt: formatEther(tvl as bigint),
      agents: {
        llmInference: (llmId as bigint).toString(),
        jsonApi: (jsonId as bigint).toString(),
        parseWebsite: (parseId as bigint).toString(),
      },
      ts: new Date().toISOString(),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "read failed";
    return NextResponse.json({ error: msg }, { status: 502 });
  }
}
