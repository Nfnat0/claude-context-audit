---
description: Run the context-audit skill — analyze recent session transcripts and propose Claude Code config that reduces token bloat
---

Run the `context-audit` skill on the current project.

Steps to follow (these mirror the skill's pipeline; consult the SKILL.md
for the full version):

1. Locate the latest session transcripts under
   `~/.claude/projects/<encoded-cwd>/*.jsonl`.
2. Delegate analysis to the `transcript-analyzer` subagent (do not read
   raw transcripts on this thread).
3. Detect the project's domain heuristically (web / python-ml / rust / go
   / dotnet / data / generic).
4. Propose a tailored set of subagents, slash commands, and hooks with a
   per-item savings estimate.
5. Confirm scope with the user via `AskUserQuestion`.
6. Apply accepted items under `~/.claude/`, backing up
   `~/.claude/settings.json` first.
7. Smoke-test each new hook with synthetic JSON input.
8. Append a `## Context hygiene (enforced)` section to `~/.claude/CLAUDE.md`.
9. Report the files written, settings patched, and the activation note.
