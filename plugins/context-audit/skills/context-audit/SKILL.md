---
name: context-audit
description: Diagnose what is consuming the Claude Code context window in the current project, then propose and apply targeted Claude Code configuration (subagents, slash commands, hooks, permission allowlists) at user scope to prevent recurrence. Use when the user says "context audit", "audit my context", "token efficiency", "session is heavy", "context is bloated", "reduce token usage", or invokes /context-audit.
---

# Context Audit

A guided pipeline that turns a heavy session into a permanent set of guardrails.

## When this skill applies

Invoke when the user wants to:

- Understand which tool calls or files have been bloating the context window.
- Get concrete Claude Code configuration changes (subagents / commands / hooks)
  that prevent the same bloat next time.
- Apply those changes at user scope so the benefit persists across projects.

Do NOT invoke for one-off "make this response shorter" requests — that is an
output-style problem, not a configuration audit.

## Pipeline

```
1. Locate transcripts
     |
2. Analyze (delegate heavy lift to transcript-analyzer subagent)
     |
3. Detect domain heuristically
     |
4. Propose tailored fixes (checklist with savings estimate)
     |
5. Confirm scope with the user (AskUserQuestion)
     |
6. Apply: write files under ~/.claude/, patch settings.json (with backup)
     |
7. Smoke test each new hook with synthetic input
     |
8. Update ~/.claude/CLAUDE.md hygiene section
     |
9. Report what was written and how to verify next session
```

## Stage 1 — Locate transcripts

Project session transcripts live under:

```
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
```

The encoded directory replaces `/` with `-` in the absolute project path. Find
the most relevant ones with:

```bash
ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -5
```

Pick the latest 1–3 transcripts associated with the current `$PWD`. If the
user names a different project, filter by encoded path.

## Stage 2 — Analyze (delegate)

**Always delegate this stage to the `transcript-analyzer` subagent.** Session
JSONL files can be tens of megabytes; reading them on the main thread defeats
the purpose of the audit.

Pass the subagent:

- The exact path(s) of the JSONL file(s).
- A request shaped like: "Return the top sources of context bloat with
  estimated token cost. Group by tool, then by file path or command. No raw
  excerpts — counts and paths only."

The subagent will run `transcript-parser.sh` (sibling file) and return a
compact report.

## Stage 3 — Detect domain heuristically

Read up to 3 small files only (each must be under 200 lines):

- `<project>/CLAUDE.md` if present
- `<project>/package.json`, `pyproject.toml`, `Cargo.toml`, `*.csproj`,
  `go.mod`, etc. — whichever exists
- A short directory listing of the project root

Map the signal to a domain bucket:

| Bucket | Signals |
|--------|---------|
| `web-frontend` | `package.json` with `react`, `vue`, `next`, `vite`, `svelte` |
| `python-ml` | `pyproject.toml` / `requirements.txt` with `torch`, `tensorflow`, `numpy`, `pandas`, `jupyter` |
| `python-web` | `pyproject.toml` with `django`, `flask`, `fastapi` |
| `rust` | `Cargo.toml` |
| `go` | `go.mod` |
| `dotnet` | `*.csproj`, `*.sln` |
| `data` | `.ipynb`, `.parquet`, `.csv` heavy directories |
| `generic` | none of the above clearly dominant |

The domain only changes the wording of suggestions and which command
templates get filled in. The pipeline is the same.

## Stage 4 — Propose tailored fixes

For each top bloat source the analyzer reported, match it against the rule
table below and assemble a checklist:

| Bloat pattern | Fix template | Savings shape |
|---------------|--------------|---------------|
| Large markdown / doc Read (≥ 200 lines) | `templates/subagent-skill-reader.md` + PreToolUse guard | ~80–95 % per offending Read |
| Image Read (PNG / JPG) for visual verification | `templates/subagent-frame-checker.md` + PreToolUse guard | ~100 % of image tokens (~1500/img) |
| Noisy build / runtime command output | `templates/subagent-cmd-runner.md` + filtered slash command from `templates/command-filtered-cmd.md` | ~70 % of output tokens |
| Long-running stdout captured via blocking task | CLAUDE.md rule: `Bash run_in_background` + tail Read | varies; prevents worst-case blowups |
| Same permission prompt repeated | Add to `permissions.allow` in `~/.claude/settings.json` | removes prompt round-trips |
| Repeated `ToolSearch` for the same tool | CLAUDE.md rule: fetch on demand only | avoids duplicate schema reloads |

Render the proposal as a markdown checklist. Each row carries:

- A one-line problem statement (what was bloating).
- The fix file that will be created or patched.
- An estimated token saving for the *next* comparable session.

Show the total estimate at the bottom. Do not understate uncertainty — use
ranges, not single numbers.

## Stage 5 — Confirm scope

Use `AskUserQuestion` once with at most 4 questions:

1. Apply all suggestions, only the top N, or pick individually?
2. Scope: user (`~/.claude/`) or project (`<cwd>/.claude/`)? Default user.
3. Hooks: enable PreToolUse blocking (strict) or warn-only (PostToolUse)?
4. Existing files: overwrite, skip, or keep both with `.new` suffix?

Skip questions whose answer is forced (e.g. only one suggestion, or no hooks
proposed).

## Stage 6 — Apply

For each accepted item:

1. Resolve the destination path (`~/.claude/agents/<name>.md`,
   `~/.claude/commands/<name>.md`, `~/.claude/hooks/<name>.sh`).
2. Read the matching `templates/*.md` or `templates/*.sh`.
3. Substitute placeholder tokens. Standard placeholders the templates use:
   - `{{NAME}}` — short, kebab-case identifier.
   - `{{DESCRIPTION}}` — one-line discoverability hint.
   - `{{COMMAND}}` — concrete bash command (for runner / filtered command).
   - `{{FILTER_REGEX}}` — extended-regex passed to `grep -E`.
   - `{{TIMEOUT}}` — seconds; default `60`.
   - `{{DOMAIN_NOTES}}` — domain-specific tips, may be empty.
4. Write the file. If it already exists and the user did not pick
   "overwrite", honour their choice (skip or `.new`).
5. Make hook scripts executable: `chmod +x`.

For `~/.claude/settings.json`:

1. Back up to `settings.json.bak.<timestamp>` first.
2. Read existing JSON, parse with `jq`.
3. Merge `hooks` and `permissions.allow` in. Never replace whole sections —
   always merge so unrelated user config survives.
4. Validate with `jq . settings.json > /dev/null`.

## Stage 7 — Smoke test hooks

For each newly written hook script, pipe a representative synthetic JSON
input through it and check the exit code + JSON shape.

Examples:

```bash
echo '{"tool_input":{"file_path":"/tmp/x.png"}}' | \
  ~/.claude/hooks/context-guard.sh
# expect: JSON with hookSpecificOutput.permissionDecision == "deny"

echo '{"tool_name":"Bash","tool_response":"'"$(printf 'a%.0s' $(seq 25000))"'"}' | \
  ~/.claude/hooks/big-output-warn.sh
# expect: JSON with hookSpecificOutput.additionalContext present
```

If a hook returns invalid JSON or non-zero, fix it before moving on.

## Stage 8 — Update CLAUDE.md hygiene section

Append (do not replace) a section to `~/.claude/CLAUDE.md`:

```markdown
## Context hygiene (enforced)

Hooks in `~/.claude/settings.json` enforce these rules. Do not work around
them — fix the underlying call pattern instead.

- Markdown / docs over ~200 lines must go through the `skill-reader`
  subagent.
- PNG / JPG / JPEG must go through the `frame-checker` subagent.
- Noisy build commands must go through `<runner-name>` subagent or the
  filtered slash command.
- Long-running jobs use `Bash run_in_background`, then `Read` the tail of the
  output file.
- Before reading any file over ~300 lines, `grep` first and pass `offset` +
  `limit` to `Read`.
```

If a "Context hygiene" section already exists, merge new bullets in;
never duplicate.

## Stage 9 — Report

Final user-facing report (terse):

- Files written (paths only, grouped by kind).
- Settings sections patched + backup path.
- Smoke-test results (one line each).
- Estimated savings range for the next comparable session.
- Activation note: hooks take effect from the next Claude Code session.

## Files in this skill

- `SKILL.md` — this orchestrator (you are reading it).
- `transcript-parser.sh` — bash + jq reducer over a session JSONL file.
  Emits a compact bloat report. Called by the `transcript-analyzer`
  subagent, not by the main thread.
- `token-cost-table.md` — rough per-content-type token cost table used to
  estimate savings.
- `templates/` — boilerplate for the subagents, slash commands, and hooks
  written during stage 6.

## Failure modes

- **No transcripts found.** Tell the user the audit needs at least one prior
  session to analyze. Offer to install templates blind based on a generic
  domain bucket.
- **Settings.json corrupt.** Refuse to write. Show the parse error and ask
  the user to fix the file first.
- **Templates produce duplicates.** Detect existing `~/.claude/agents/<name>.md`
  with the same content and skip. If different content, honour the
  overwrite-policy chosen in stage 5.
