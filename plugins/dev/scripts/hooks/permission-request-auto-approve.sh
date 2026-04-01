#!/usr/bin/env bash
# PermissionRequest hook: autopilot Worker の permission ダイアログを自動承認
# AUTOPILOT_DIR 未設定時は何も出力しない（通常セッションの permission フローに影響しない）
set -uo pipefail

# stdin を消費
cat > /dev/null 2>&1 || true

# AUTOPILOT_DIR 未設定 or 空 → 何も出力せず終了
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# AUTOPILOT_DIR が実在するディレクトリでなければ無視（不正な値を拒否）
if [[ ! -d "${AUTOPILOT_DIR}" ]]; then
  exit 0
fi

# autopilot 配下 → allow を返す
cat <<'EOF'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF

exit 0
