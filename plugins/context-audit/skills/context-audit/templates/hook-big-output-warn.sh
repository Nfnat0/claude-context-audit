#!/usr/bin/env bash
# big-output-warn.sh
#
# PostToolUse hook. Emits a soft warning into the session whenever a tool
# response is larger than the configured threshold. The warning lands in
# context as additionalContext so the model sees it on the next turn and
# considers delegating to a subagent.
#
# Stdin: JSON event from Claude Code.
# Stdout: JSON with hookSpecificOutput.additionalContext, or empty.

set -eu

THRESHOLD="${CONTEXT_AUDIT_OUTPUT_THRESHOLD:-20000}"

input="$(cat)"
size="$(printf '%s' "$input" | jq -r '
  (.tool_response // .) as $r
  | if   ($r | type) == "string" then ($r | length)
    elif ($r | type) == "object" then ($r | tostring | length)
    elif ($r | type) == "array"  then ($r | tostring | length)
    else 0 end
')"

if [ "${size:-0}" -gt "$THRESHOLD" ]; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // "tool"')"
  jq -n \
    --arg t "$tool" \
    --arg s "$size" \
    --arg th "$THRESHOLD" '
    {
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext:
          ("⚠ context-budget: \($t) returned \($s) chars (threshold " +
           "\($th)). Consider routing similar future calls through a " +
           "subagent or a filtered slash command so the bulk stays out " +
           "of main context.")
      }
    }'
fi

exit 0
