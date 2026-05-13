#!/usr/bin/env bash
# twl-audit-registry.sh — Section 12 (Registry Integrity) audit wrapper
#
# `twl audit --section 12` を plugin_root = plugins/twl で実行する薄い wrapper。
# 参照仕様:
#   - cli/twl/src/twl/validation/audit.py audit_registry()
#   - architecture/spec/twill-plugin-rebuild/registry-schema.html §6.2
#   - plugins/twl/registry.yaml §5 integrity_rules (audit_section: 12)
#
# Usage:
#   bash plugins/twl/scripts/lib/twl-audit-registry.sh [--format json|text]
#
# Exit codes:
#   0 — no critical findings (or registry.yaml absent → audit-side skip)
#   1 — critical findings detected (Section 12 core 2 rule: prefix_role_match /
#       no_duplicate_concern violation)
#   2 — wrapper-level error (cwd resolution failed, registry.yaml not found)

set -euo pipefail

# resolve twill main/ from this script location
# script path: plugins/twl/scripts/lib/twl-audit-registry.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TWILL_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

PLUGIN_ROOT="${TWILL_ROOT}/plugins/twl"
if [[ ! -f "${PLUGIN_ROOT}/registry.yaml" ]]; then
  echo "ERROR: registry.yaml not found at ${PLUGIN_ROOT}/registry.yaml" >&2
  exit 2
fi

cd "${PLUGIN_ROOT}"
exec uv --project "${TWILL_ROOT}/cli/twl" run twl --audit --section 12 "$@"
