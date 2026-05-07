---
description: {{DESCRIPTION}}
allowed-tools: Bash
---

!`cd "${CLAUDE_PROJECT_DIR:-$PWD}" && timeout {{TIMEOUT}} {{COMMAND}} 2>&1 | grep -E "{{FILTER_REGEX}}" | head -20`
