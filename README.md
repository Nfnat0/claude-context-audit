# claude-context-audit

A Claude Code plugin that **diagnoses what is consuming your context window
and applies targeted configuration** (subagents, slash commands, hooks,
permission allowlists) to prevent the same bloat from happening again.

> One-line idea: turn a heavy session into a permanent set of guardrails.

## What it does

1. **Analyze** — reads your recent session transcripts (delegated to a
   subagent so the main thread never loads megabytes of JSONL) and ranks
   the largest sources of context bloat: oversized file reads, image
   reads, noisy build output, repeated tool calls, and so on.
2. **Propose** — matches each bloat source to a fix template and shows
   you a checklist with a per-item token-savings estimate.
3. **Apply** — on confirmation, writes user-scope (`~/.claude/`)
   subagents, slash commands, and hooks, and patches
   `~/.claude/settings.json` (with a timestamped backup).
4. **Verify** — smoke-tests every new hook with synthetic JSON input
   and updates `~/.claude/CLAUDE.md` with the new hygiene rules.

The result: the next time you open a similar project, the same patterns
that bloated yesterday's context get blocked or compressed automatically.

## Why a plugin?

Audit + propose + apply is a multi-step workflow that benefits from:

- A skill (`context-audit`) that the main thread reads as instructions.
- A subagent (`transcript-analyzer`) that handles the heavy file reading.
- A slash command (`/context-audit`) for one-key invocation.
- Reusable templates for the subagents, commands, and hooks the audit
  installs.

A plugin bundles all four into a single, distributable unit.

## Install

### Via the bundled marketplace

```bash
# In Claude Code:
/plugin marketplace add <github-owner>/claude-context-audit
/plugin install context-audit
```

### Manually (for development)

```bash
git clone https://github.com/<github-owner>/claude-context-audit.git
ln -s "$(pwd)/claude-context-audit/plugins/context-audit" \
      ~/.claude/plugins/context-audit
```

After install, restart Claude Code so the skill, subagent, and slash
command are picked up.

## Use

Invoke once:

```
/context-audit
```

…or trigger by natural language: "audit my context", "this session is
heavy", "reduce token usage for this project". The skill auto-fires
when those phrases appear because of its `description` matcher.

The skill will:

1. Find the most recent session transcripts for the current project.
2. Hand them to the `transcript-analyzer` subagent and receive a compact
   report.
3. Show you the proposed fixes, grouped by category, with savings
   estimates.
4. Ask exactly one set of follow-up questions (apply all / apply top-N
   / per item, user-scope vs project-scope, strict vs warn-only hooks).
5. Apply your selection and report back.

## What the audit can install

| Kind | File written | Role |
|------|--------------|------|
| Subagent | `~/.claude/agents/<reader>.md` | Read large markdown / docs and return ≤ 250 tokens |
| Subagent | `~/.claude/agents/<frame>.md` | Open images and return text-only verdicts |
| Subagent | `~/.claude/agents/<runner>.md` | Run noisy build commands with output filtered |
| Slash command | `~/.claude/commands/<name>.md` | One-key entry to a filtered command |
| Hook | `~/.claude/hooks/context-guard.sh` | PreToolUse: deny image and oversized doc reads |
| Hook | `~/.claude/hooks/big-output-warn.sh` | PostToolUse: warn when a tool returns > 20 KB |
| Settings | `~/.claude/settings.json` | Wires the hooks in and adds permission allowlist |
| CLAUDE.md | `~/.claude/CLAUDE.md` | `## Context hygiene (enforced)` section |

Templates for every item live under
`plugins/context-audit/skills/context-audit/templates/` so you can adapt
them by hand if you prefer.

## Configuration knobs

The hooks honour a handful of environment variables so you can tune
without editing scripts:

| Variable | Default | Used by |
|----------|---------|---------|
| `CONTEXT_AUDIT_LINE_THRESHOLD` | `200` | `context-guard.sh` |
| `CONTEXT_AUDIT_OUTPUT_THRESHOLD` | `20000` | `big-output-warn.sh` |
| `CONTEXT_AUDIT_DOCS_GLOBS` | (see script) | `context-guard.sh` |
| `CONTEXT_AUDIT_FRAME_AGENT` | `frame-checker` | `context-guard.sh` |
| `CONTEXT_AUDIT_SKILL_AGENT` | `skill-reader` | `context-guard.sh` |
| `CONTEXT_AUDIT_CPT` | `3.5` | `transcript-parser.sh` |
| `CONTEXT_AUDIT_TOP_N` | `15` | `transcript-parser.sh` |
| `CONTEXT_AUDIT_IMAGE_TOKENS` | `1500` | `transcript-parser.sh` |

## Manual smoke tests

The hook templates are designed to be testable without launching Claude
Code:

```bash
# PNG read should be denied:
echo '{"tool_input":{"file_path":"/tmp/x.png"}}' \
  | bash plugins/context-audit/skills/context-audit/templates/hook-context-guard.sh

# Large skill md read should be denied:
echo '{"tool_input":{"file_path":"'"$PWD"'/plugins/context-audit/skills/context-audit/SKILL.md"}}' \
  | CONTEXT_AUDIT_DOCS_GLOBS='*/skills/context-audit/SKILL.md' \
    bash plugins/context-audit/skills/context-audit/templates/hook-context-guard.sh

# Oversized tool response should warn:
echo "{\"tool_name\":\"Bash\",\"tool_response\":\"$(printf 'a%.0s' $(seq 25000))\"}" \
  | bash plugins/context-audit/skills/context-audit/templates/hook-big-output-warn.sh
```

## Layout

```
.
├── .claude-plugin/marketplace.json
├── plugins/
│   └── context-audit/
│       ├── .claude-plugin/plugin.json
│       ├── skills/context-audit/
│       │   ├── SKILL.md                  # orchestrator
│       │   ├── transcript-parser.sh      # bash + jq reducer
│       │   ├── token-cost-table.md       # savings reference
│       │   └── templates/                # boilerplate the audit installs
│       ├── agents/
│       │   └── transcript-analyzer.md
│       └── commands/
│           └── context-audit.md
├── LICENSE
└── README.md
```

## Status

Alpha. The pipeline runs end-to-end in development; format compatibility
across Claude Code session-JSONL versions is best-effort and conservative
(the parser only counts what it can confidently identify).

## License

MIT — see [LICENSE](LICENSE).
