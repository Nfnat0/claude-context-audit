# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **plugin** (not a runtime app, not a library). It diagnoses
context-window bloat in prior Claude Code sessions and applies remediations
(subagents, slash commands, hooks, settings patches) under `~/.claude/`.

The repo itself is small — most of the "code" is markdown that Claude
Code reads as instructions. The only executable artifacts are bash + jq
scripts that aggregate JSONL transcripts.

## Layout (load-bearing parts)

```
.claude-plugin/marketplace.json          # marketplace manifest
plugins/context-audit/
  .claude-plugin/plugin.json             # plugin manifest
  skills/context-audit/
    SKILL.md                             # orchestrator — read by main thread
    transcript-parser.sh                 # bash + jq reducer (called by subagent only)
    token-cost-table.md                  # savings reference for stage-4 proposals
    templates/                           # boilerplate the audit installs into ~/.claude/
  agents/transcript-analyzer.md          # subagent that runs the parser off-thread
  commands/context-audit.md              # /context-audit slash command
```

The plugin's runtime contract is split across three Claude-Code-loaded files:
- `commands/context-audit.md` — entry point (slash command).
- `skills/context-audit/SKILL.md` — the actual workflow (analyze → propose → apply → verify).
- `agents/transcript-analyzer.md` — the heavy reader; main thread must
  never read raw `*.jsonl` itself.

The `templates/` directory is **not** loaded by Claude Code at runtime;
it is data the SKILL copies into `~/.claude/` during stage 6.

## Architectural invariants

These are non-obvious and must hold across edits:

1. **Main thread never reads raw transcripts.** All `*.jsonl` parsing
   goes through the `transcript-analyzer` subagent, which shells out to
   `transcript-parser.sh`. The parser emits only counts/paths/estimates —
   never raw content. Breaking this defeats the plugin's purpose.
2. **Single-pass jq aggregation in `transcript-parser.sh`.** The script
   header explains why bash `IFS=$'\t' read` would lose empty
   `file_path` fields and misclassify entries. Don't refactor the
   aggregation back into a bash loop.
3. **Templates are copies, not symlinks.** When the audit installs a
   subagent/hook into `~/.claude/`, it writes a real file the user can
   edit. Edits to `templates/*` only affect future installs.
4. **`settings.json` patches merge, never replace.** Stage 6 backs up
   `~/.claude/settings.json` to a timestamped `.bak` before merging
   hook/permission entries.
5. **Each new hook is smoke-tested with synthetic JSON** (stage 7) before
   the audit reports success. The README's "Manual smoke tests" section
   shows the exact stdin shape; preserve compatibility.
6. **Token estimates are heuristics**: text = `chars / 3.5`, image =
   `1500 tokens`, tunable via `CONTEXT_AUDIT_CPT` and
   `CONTEXT_AUDIT_IMAGE_TOKENS`. Don't promise precision the parser
   can't deliver.

## Editing rules of thumb

- Touching `SKILL.md` or `transcript-analyzer.md`: keep the
  `description:` frontmatter trigger phrases intact ("audit my context",
  "session is heavy", etc.). Removing them silently disables auto-fire.
- Adding a new fix template under `templates/`: also extend the rule
  table in `SKILL.md` (the bloat-pattern → template mapping) and the
  installer step that copies it.
- Changing a hook's stdin contract: update both the hook itself and
  the corresponding `echo '{...}' | bash …` example in `README.md`.
- The `transcript-parser.sh` env vars (`CONTEXT_AUDIT_*`) are documented
  in `README.md`. New knobs go there too.

## Smoke tests (no Claude Code needed)

```bash
# Hook denies PNG read:
echo '{"tool_input":{"file_path":"/tmp/x.png"}}' \
  | bash plugins/context-audit/skills/context-audit/templates/hook-context-guard.sh

# Hook denies oversized doc read:
echo '{"tool_input":{"file_path":"'"$PWD"'/plugins/context-audit/skills/context-audit/SKILL.md"}}' \
  | CONTEXT_AUDIT_DOCS_GLOBS='*/skills/context-audit/SKILL.md' \
    bash plugins/context-audit/skills/context-audit/templates/hook-context-guard.sh

# Big-output hook warns:
echo "{\"tool_name\":\"Bash\",\"tool_response\":\"$(printf 'a%.0s' $(seq 25000))\"}" \
  | bash plugins/context-audit/skills/context-audit/templates/hook-big-output-warn.sh

# Parser end-to-end on a real session JSONL:
plugins/context-audit/skills/context-audit/transcript-parser.sh \
  ~/.claude/projects/<encoded-cwd>/<session>.jsonl
```

There is no `npm`/`cargo`/`make` build. `jq` is the only hard runtime
dependency for the parser.

## Working in this repo via Claude Code itself

This project's own SKILL.md is over 200 lines and the user-scope
`context-guard.sh` hook will block direct `Read` of it. Use the
`skill-reader` subagent (or grep for the section first) when you need
SKILL.md content. PNG/JPG verification likewise routes through
`frame-checker`. These are the same hygiene rules the plugin installs —
treat dogfooding failures as bugs.
