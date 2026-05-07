#!/usr/bin/env bash
# context-guard.sh
#
# PreToolUse hook for the `Read` tool. Blocks two patterns that consistently
# bloat the main context:
#   1. PNG / JPG image files                     -> use a frame-checker subagent
#   2. Skill / docs markdown over the threshold  -> use a skill-reader subagent
#
# Stdin: JSON tool input from Claude Code.
# Stdout: JSON decision (allow / deny).
# Reference: https://docs.claude.com/en/docs/claude-code/hooks

set -eu

LINE_THRESHOLD="${CONTEXT_AUDIT_LINE_THRESHOLD:-200}"
FRAME_AGENT="${CONTEXT_AUDIT_FRAME_AGENT:-frame-checker}"
SKILL_AGENT="${CONTEXT_AUDIT_SKILL_AGENT:-skill-reader}"

# Globs treated as "skill / docs" markdown candidates. Override with
# CONTEXT_AUDIT_DOCS_GLOBS as a colon-separated list.
DOCS_GLOBS_DEFAULT='*.claude/skills/*.md:*/skills/*/SKILL.md:*/docs/**/*.md:*/wiki/**/*.md'
IFS=':' read -r -a DOCS_GLOBS <<<"${CONTEXT_AUDIT_DOCS_GLOBS:-$DOCS_GLOBS_DEFAULT}"

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

if [ -z "$file" ]; then
  exit 0
fi

# 1. images ------------------------------------------------------------------
case "$file" in
  *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP)
    jq -n \
      --arg f "$file" \
      --arg agent "$FRAME_AGENT" '
      {
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason:
            ("Image file (\($f)) — open it via the `\($agent)` subagent " +
             "(Agent tool, subagent_type=\($agent)) so the image data does " +
             "not flood the main context. Tell the agent which elements " +
             "to verify.")
        }
      }'
    exit 0
    ;;
esac

# 2. large skill / docs markdown --------------------------------------------
matches_doc_glob=0
for g in "${DOCS_GLOBS[@]}"; do
  case "$file" in
    $g) matches_doc_glob=1; break ;;
  esac
done

if [ "$matches_doc_glob" -eq 1 ] && [ -f "$file" ]; then
  lines="$(wc -l <"$file" 2>/dev/null || echo 0)"
  if [ "$lines" -gt "$LINE_THRESHOLD" ]; then
    jq -n \
      --arg f "$file" \
      --arg n "$lines" \
      --arg threshold "$LINE_THRESHOLD" \
      --arg agent "$SKILL_AGENT" '
      {
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason:
            ("Documentation file \($f) is \($n) lines (threshold " +
             "\($threshold)). Open it via the `\($agent)` subagent " +
             "(Agent tool, subagent_type=\($agent)) with a specific " +
             "question, instead of pulling the whole file into the main " +
             "context.")
        }
      }'
    exit 0
  fi
fi

exit 0
