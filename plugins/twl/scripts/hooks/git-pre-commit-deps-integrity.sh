#!/usr/bin/env bash
# git-pre-commit-deps-integrity.sh — deps-integrity pre-commit hook
#
# Install: ln -sf "$(git rev-parse --show-toplevel)/plugins/twl/scripts/hooks/git-pre-commit-deps-integrity.sh" \
#                  "$(git rev-parse --git-common-dir)/hooks/pre-commit"
set -euo pipefail

PLUGIN_ROOT="$(git rev-parse --show-toplevel)/plugins/twl"

# Only run when chain-related files are staged
if ! git diff --cached --name-only | grep -qE \
    "cli/twl/src/twl/autopilot/chain\.py|plugins/twl/scripts/chain-steps\.sh|plugins/twl/deps\.yaml"; then
  exit 0
fi

if ! command -v twl &>/dev/null; then
  echo "twl not found — skipping deps-integrity check" >&2
  exit 0
fi

echo "Running twl check --deps-integrity..."
cd "$PLUGIN_ROOT"
if ! twl check --deps-integrity; then
  echo ""
  echo "Commit blocked: chain.py / chain-steps.sh / deps.yaml are out of sync."
  echo "Run: twl chain export --yaml --shell"
  exit 1
fi
echo "deps-integrity OK"
