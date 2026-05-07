# Token Cost Table (rough estimates)

Approximate token costs Claude Code pays per kind of content. Use these to
size savings in the audit's stage 4 proposal. Numbers are heuristics, not
contractual — rely on order-of-magnitude reasoning, not a third decimal.

## Text

Rule of thumb: **`tokens ≈ chars / 3.5`** for English. Code and JSON often
sit closer to `chars / 3.0`. Stick with `3.5` unless the bulk of the
analyzed content is clearly source code.

| Content shape | Typical lines | Typical chars | Approx. tokens |
|---------------|---------------|---------------|----------------|
| Single function (well-trimmed) | 30 | 1,200 | 350 |
| Average source file | 200 | 8,000 | 2,300 |
| Long doc / skill markdown | 400 | 16,000 | 4,500 |
| Generated build log (filtered) | 20 | 1,000 | 300 |
| Generated build log (raw) | 200 | 12,000 | 3,500 |

## Images

Anthropic's vision pricing is roughly **~1,500 tokens per attached image** at
common screenshot resolutions, regardless of how small the image looks in
the conversation. Multiple frames in one verification pass add up fast.

| Verification pattern | Cost |
|----------------------|------|
| 1 PNG read | ~1,500 |
| 3 PNGs (start / mid / end) | ~4,500 |
| 10-frame manual sweep | ~15,000 |

→ Always prefer one frame plus a text-only verdict from a frame-checker
subagent.

## Tool schemas

Each deferred tool schema fetched via `ToolSearch` is ~500–1,500 tokens of
JSON, depending on the tool. Loading 6 tools "just in case" is ~6,000
tokens of schema. Fetch on demand only.

## Streamed Bash output

Rough mapping for a few common commands when run *unfiltered*:

| Command | Typical raw output | Typical filtered output |
|---------|--------------------|-------------------------|
| `npm install` | 200–600 lines | 5–10 lines (status only) |
| `cargo build` | 50–200 lines | 5 lines |
| `pytest` (failing) | 100–500 lines | tracebacks only, ~30 lines |
| Build with engine warnings | 50–300 lines | 5–15 lines |

The savings from a filtered slash command are usually 70–95 % of the raw
output's tokens.

## Long jobs and `TaskOutput block=true`

A blocking background-task readout returns the entire stdout buffer into
context. If the buffer is large (verbose CI, training logs, frame dumps),
that single tool result can dwarf an entire prior conversation. Always
prefer `Bash run_in_background` followed by `Read` on the tail of the
output file.
