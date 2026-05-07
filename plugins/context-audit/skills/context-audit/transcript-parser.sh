#!/usr/bin/env bash
# transcript-parser.sh
#
# Reduce one or more Claude Code session JSONL files to a compact
# context-bloat report. Designed to be called by the `transcript-analyzer`
# subagent, never by the main conversation thread.
#
# Usage:
#   transcript-parser.sh <session.jsonl> [more.jsonl ...]
#
# Output is plain text on stdout. No raw transcript content is ever printed —
# only counts, paths, and approximate token estimates.
#
# Token estimate: chars / 3.5 (rough English heuristic; conservative for code
# and JSON, slightly generous for prose). Image content is estimated separately
# at ~1500 tokens per attached image regardless of size.
#
# Implementation note: all aggregation happens inside jq to avoid bash's
# IFS=$'\t' read collapsing consecutive tabs (which would lose empty path
# fields and misclassify commandless tool uses).

set -eu

if [ "$#" -eq 0 ]; then
  echo "usage: transcript-parser.sh <session.jsonl> [more.jsonl ...]" >&2
  exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 69
fi

CHARS_PER_TOKEN="${CONTEXT_AUDIT_CPT:-3.5}"
TOP_N="${CONTEXT_AUDIT_TOP_N:-15}"
IMAGE_TOKENS="${CONTEXT_AUDIT_IMAGE_TOKENS:-1500}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

merged="$tmp_dir/merged.jsonl"
: >"$merged"

total_files=0
total_lines=0

for f in "$@"; do
  if [ ! -r "$f" ]; then
    echo "warning: cannot read $f, skipping" >&2
    continue
  fi
  total_files=$((total_files + 1))
  lines_here=$(wc -l <"$f" 2>/dev/null || echo 0)
  total_lines=$((total_lines + lines_here))
  cat "$f" >>"$merged"
done

if [ "$total_files" -eq 0 ]; then
  echo "error: no readable input files" >&2
  exit 66
fi

# All aggregation in one jq pass. Slurp the file, walk every nested object,
# bucket tool_use entries by name / file_path / command prefix, sum tool_result
# content sizes and image counts. Emit a single JSON summary on stdout.

summary="$tmp_dir/summary.json"

jq -s --arg top "$TOP_N" '
  def text_len:
    ( . // "" ) as $v
    | if   ($v | type) == "string" then ($v | length)
      elif ($v | type) == "object" or ($v | type) == "array"
        then ($v | tostring | length)
      else 0 end;

  def tool_uses:
    [ .[] | .. | objects | select(.type? == "tool_use") ];
  def tool_results:
    [ .[] | .. | objects | select(.type? == "tool_result") ];

  ( tool_uses ) as $uses
  | ( tool_results ) as $results

  # Per-tool use counts
  | ( $uses
      | group_by(.name // "unknown")
      | map({ tool: (.[0].name // "unknown"), uses: length })
      | sort_by(-.uses)
    ) as $by_tool

  # Per (tool, path) counts — only when input.file_path or notebook_path set
  | ( $uses
      | map(
          ( .input.file_path // .input.notebook_path // null ) as $p
          | select($p != null and ($p | tostring) != "")
          | { tool: (.name // "unknown"), path: ($p | tostring) }
        )
      | group_by([.tool, .path])
      | map({ uses: length, tool: .[0].tool, path: .[0].path })
      | sort_by(-.uses)
    ) as $by_path

  # Per (tool, command_prefix) counts — only when input.command set
  | ( $uses
      | map(
          ( .input.command // null ) as $c
          | select($c != null and ($c | tostring) != "")
          | { tool: (.name // "unknown"),
              cmd:  ( $c | tostring | gsub("[\\n\\r]+"; " ") | .[0:80] ) }
        )
      | group_by([.tool, .cmd])
      | map({ uses: length, tool: .[0].tool, cmd: .[0].cmd })
      | sort_by(-.uses)
    ) as $by_cmd

  # Aggregate result sizes + image counts
  | ( $results
      | map(
          ( .content // .output // "" ) as $c
          | { chars:
                ( if ($c | type) == "array"
                    then ( $c | map(select(.type? != "image")
                                   | .text // (. | tostring))
                              | join("")
                              | length )
                    else ($c | text_len)
                  end ),
              imgs:
                ( if ($c | type) == "array"
                    then ( $c | map(select(.type? == "image")) | length )
                    else 0
                  end )
            }
        )
      | reduce .[] as $r ({ chars: 0, imgs: 0 };
          .chars += $r.chars
          | .imgs  += $r.imgs)
    ) as $totals

  | {
      uses_total: ($uses | length),
      results_total: ($results | length),
      total_chars: $totals.chars,
      total_imgs:  $totals.imgs,
      by_tool: ($by_tool | .[0:($top | tonumber)]),
      by_path: ($by_path | .[0:($top | tonumber)]),
      by_cmd:  ($by_cmd  | .[0:($top | tonumber)])
    }
' "$merged" >"$summary"

# --- format ------------------------------------------------------------------

total_chars=$(jq -r '.total_chars' "$summary")
total_imgs=$(jq -r '.total_imgs' "$summary")
uses_total=$(jq -r '.uses_total' "$summary")
results_total=$(jq -r '.results_total' "$summary")

est_text_tokens=$(awk -v c="$total_chars" -v cpt="$CHARS_PER_TOKEN" \
  'BEGIN{printf "%d", c/cpt}')
est_image_tokens=$((total_imgs * IMAGE_TOKENS))
est_total=$((est_text_tokens + est_image_tokens))

cat <<EOF
# Context-Bloat Report

Files analyzed   : $total_files
JSONL lines      : $total_lines
tool_use entries : $uses_total
tool_result entries: $results_total
Result chars     : $total_chars  (est. ${est_text_tokens} tokens at $CHARS_PER_TOKEN chars/token)
Image attachments: $total_imgs   (est. ${est_image_tokens} tokens at ${IMAGE_TOKENS}/image)
Estimated total  : ${est_total} tokens of tool output content

## Tool-use counts (top $TOP_N)

EOF

jq -r --arg fmt '%-20s  %s' '
  if (.by_tool | length) == 0 then
    "(no tool_use entries detected)"
  else
    ([ "tool", "uses" ] | @tsv),
    ([ "----", "----" ] | @tsv),
    (.by_tool[] | [ .tool, (.uses | tostring) ] | @tsv)
  end
' "$summary" | column -t -s $'\t'

cat <<EOF

## Top read paths (top $TOP_N)

EOF

jq -r '
  if (.by_path | length) == 0 then
    "(no file_path inputs recorded)"
  else
    ([ "uses", "tool", "path" ] | @tsv),
    ([ "------", "------------", "----" ] | @tsv),
    (.by_path[] | [ (.uses | tostring), .tool, .path ] | @tsv)
  end
' "$summary" | column -t -s $'\t'

cat <<EOF

## Top short commands (top $TOP_N)

EOF

jq -r '
  if (.by_cmd | length) == 0 then
    "(no command inputs recorded)"
  else
    ([ "uses", "tool", "command (truncated to 80 chars)" ] | @tsv),
    ([ "------", "------------", "-------------------------------" ] | @tsv),
    (.by_cmd[] | [ (.uses | tostring), .tool, .cmd ] | @tsv)
  end
' "$summary" | column -t -s $'\t'

cat <<EOF

## Hints

- A single "Read" use that returned > 5000 chars is a strong subagent
  candidate — wire a domain-specific reader.
- Image attachments at ~${IMAGE_TOKENS} tokens each dominate fast: every
  PNG / JPG read should run through a frame-checker subagent.
- A tool that appears many times with similar inputs is often a candidate
  for a slash command with a pre-canned filter.
EOF
