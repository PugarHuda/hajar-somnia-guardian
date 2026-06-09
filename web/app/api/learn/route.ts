import { NextResponse } from "next/server";
import { client, ADDRESSES, learnerAbi } from "../../lib/somnia";

export const dynamic = "force-dynamic";
export const revalidate = 0;

/**
 * Hajar's live, self-learned threat knowledge base — read straight from the on-chain
 * HajarThreatLearner. Each category's `level` is what Hajar last learned (0..100) by scraping a
 * security feed via the Somnia Parse Website / JSON API agents; `observations` counts how many
 * times it has been scanned or classified. Exposed so other agents can consume Hajar's intel.
 */
export async function GET() {
  try {
    const learner = { address: ADDRESSES.learner as `0x${string}`, abi: learnerAbi };
    const count = (await client.readContract({ ...learner, functionName: "categoryCount" })) as bigint;

    const ids = (await Promise.all(
      Array.from({ length: Number(count) }, (_, i) =>
        client.readContract({ ...learner, functionName: "categoryIds", args: [BigInt(i)] })
      )
    )) as `0x${string}`[];

    const records = await Promise.all(
      ids.map((id) => client.readContract({ ...learner, functionName: "knowledge", args: [id] }))
    );

    const categories = records.map((r) => {
      const k = r as unknown as [boolean, number, bigint, number, string];
      return {
        name: k[4],
        threatLevel: k[1],
        lastUpdated: Number(k[2]) ? new Date(Number(k[2]) * 1000).toISOString() : null,
        observations: k[3],
      };
    });

    const [topName, topLevel] = (await client.readContract({
      ...learner,
      functionName: "highestThreat",
    })) as [string, number];

    return NextResponse.json({
      learner: ADDRESSES.learner,
      chain: { id: 50312, name: "Somnia Shannon testnet" },
      agents: { parseWebsite: "12875401142070969085", jsonApi: "13174292974160097713", llmInference: "12847293847561029384" },
      categories,
      highestThreat: { name: topName, level: topLevel },
      note: "Knowledge accumulates from external security feeds via Somnia agents (scrape + classify), not model training.",
      ts: new Date().toISOString(),
    }, { headers: { "Cache-Control": "no-store" } });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "read failed";
    return NextResponse.json({ error: msg }, { status: 502 });
  }
}
