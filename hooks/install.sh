#!/usr/bin/env bash
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
DAEMON_URL="http://localhost:6767/events"

# --- Preflight ---

if ! command -v jq &>/dev/null; then
  echo "error: jq is required but not installed. Run: brew install jq"
  exit 1
fi

if [ ! -f "$SETTINGS" ]; then
  echo "error: $SETTINGS not found. Is Claude Code installed?"
  exit 1
fi

# --- Backup ---

cp "$SETTINGS" "${SETTINGS}.bak"
echo "backed up $SETTINGS → ${SETTINGS}.bak"

# --- Build the hooks block ---

HOOKS=$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "SessionEnd": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "PreToolUse": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "PostToolUse": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "PostToolUseFailure": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "PermissionDenied": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]
      }
    ],
    "Stop": [
      {"hooks": [{"type": "http", "url": "$DAEMON_URL", "timeout": 5}]}
    ]
  }
}
EOF
)

# --- Merge into existing settings ---
# jq's * operator does a deep merge: existing keys are kept, new keys are added.
# If a "hooks" key already exists, it gets replaced entirely.

UPDATED=$(jq --argjson hooks "$HOOKS" '. * $hooks' "$SETTINGS")

echo "$UPDATED" > "$SETTINGS"
echo "hooks installed into $SETTINGS"

# --- Verify ---

echo ""
echo "configured hooks:"
jq '.hooks | keys' "$SETTINGS"
