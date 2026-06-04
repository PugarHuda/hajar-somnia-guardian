# Discord message — #technical-questions (Somnia Agentathon)

## ✅ ANSWERED by the Somnia team (emrey.somi)

The `onchainTools` tuple is:

```solidity
struct OnchainTool {
    string signature;    // e.g. "pause()"
    string description;  // hint for the LLM
}
```

Canonical signature → selector:
`inferToolsChat(string[],string[],string[],(string,string)[],uint256,bool)` → **`0xd0683905`**

The LLM returns `(finishReason, response, updatedRoles[], updatedMessages[],
pendingToolCallIds[], pendingToolCalls[])`; `pendingToolCalls[]` holds ABI-encoded calldata
per tool. Loop: execute the calldata, append the result as a `"tool"` role message, call again
until `finishReason == "stop"`.

**Wired in Hajar as Tier-2d** (`requestAutonomousRemediation`): the guardian offers the LLM one
safe tool (`pause()`) and latches the breaker when the agent returns a tool call. Selector locked
by a unit test (`test_InferToolsChat_SelectorMatchesLiveABI`). The exact on-chain delivery format
of the return tuple in `Response[].result` is still to be confirmed against a live response
sample — the callback decodes only the leading `finishReason` string, inside a try/catch.

---

## Original question (kept for reference)

Copy-paste this into the Somnia Discord `#❓technical-questions` channel:

---

Hey team 👋 Building an Agentathon project (an autonomous DeFi guardian) that already uses
the **LLM Inference** (`inferNumber`), **JSON API** (`fetchUint`), and **LLM Parse Website**
(`ExtractANumber`) agents successfully on Shannon testnet 🙏

I want to wire **`inferToolsChat`** so the agent can return on-chain tool calls (autonomous
remediation), but the agent page / SDK doesn't expose the **internal components of the
`onchainTools` tuple** — the ABI shows `{"type":"tuple[]","name":"onchainTools"}` with no
`components`, and the Solidity snippet uses `tuple[] memory` (not a valid Solidity type).

Because `inferToolsChat`'s 4-byte selector depends on the full canonical signature
`inferToolsChat(string[],string[],string[],(<TUPLE COMPONENTS>)[],uint256,bool)`, I can't
encode a correct `abi.encodeWithSelector(...)` payload without the exact `onchainTools`
struct definition.

**Could you share the exact Solidity struct for `onchainTools`** (field names + types), or a
canonical signature for `inferToolsChat`? Even a minimal example of encoding one on-chain tool
would unblock it. Thanks! 🙏

(For reference — what I have working today, all consensus-verified on testnet: LLM Inference
risk scoring, JSON API price/oracle cross-check, and the Parse Website threat-intel path.)

---

**Two-question version (if you also want to flag the Parse Website reliability):**

> Also: is there a recommended pattern for getting `ExtractANumber` (Parse Website) to reach
> consensus reliably? My subcommittee returns `Failed` on both dynamic (live price) and static
> (httpbin.org/json) pages — I assume validators' scrapes/extractions diverge. Any guidance on
> `confidenceThreshold` / page types that consistently reach consensus?
