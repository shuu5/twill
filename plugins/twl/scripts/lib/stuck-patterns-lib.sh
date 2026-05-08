#!/usr/bin/env bash
# stuck-patterns-lib.sh — stuck-patterns.yaml SSoT ローダー (#1582)
#
# 使い方:
#   source /path/to/stuck-patterns-lib.sh
#   _load_stuck_patterns           # YAML から pattern arrays をロード
#
# 出力グローバル変数（_load_stuck_patterns 呼び出し後）:
#   STUCK_PATTERN_MENU_ARR[]     — "regex:id" 形式の menu patterns
#   STUCK_PATTERN_FREEFORM_ARR[] — "regex:id" 形式の freeform patterns
#   STUCK_PATTERN_RECOVERY_ARR[] — "regex:id" 形式の recovery patterns
#   STUCK_PATTERNS_YAML          — ロード元 YAML のパス（デバッグ用）
#
# 環境変数:
#   STUCK_PATTERNS_YAML_OVERRIDE  — YAML パスの上書き（テスト用）

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_STUCK_PATTERNS_YAML_DEFAULT="${_LIB_DIR}/../../refs/stuck-patterns.yaml"

# 配列をグローバルで宣言（source 前に初期化）
declare -ga STUCK_PATTERN_MENU_ARR=()
declare -ga STUCK_PATTERN_FREEFORM_ARR=()
declare -ga STUCK_PATTERN_RECOVERY_ARR=()
STUCK_PATTERNS_YAML=""

_load_stuck_patterns() {
  local yaml_file="${STUCK_PATTERNS_YAML_OVERRIDE:-${_STUCK_PATTERNS_YAML_DEFAULT}}"

  if [[ ! -f "$yaml_file" ]]; then
    echo "[stuck-patterns-lib] WARN: stuck-patterns.yaml not found: ${yaml_file}" >&2
    return 0
  fi

  STUCK_PATTERNS_YAML="$yaml_file"
  STUCK_PATTERN_MENU_ARR=()
  STUCK_PATTERN_FREEFORM_ARR=()
  STUCK_PATTERN_RECOVERY_ARR=()

  # Python で YAML をパースしてシェル配列エントリを生成
  local parsed
  parsed=$(python3 - "$yaml_file" << 'PYEOF'
import sys, re

entries = []
current_id = None
current_regex = None
current_owner = None

with open(sys.argv[1]) as f:
    for raw in f:
        line = raw.rstrip()
        m = re.match(r'\s*-\s*id:\s*(\S+)', line)
        if m:
            if current_id and current_regex:
                entries.append((current_id, current_regex, current_owner or ''))
            current_id = m.group(1)
            current_regex = None
            current_owner = None
            continue
        m2 = re.match(r'\s+regex:\s*"?(.*?)"?\s*$', line)
        if m2 and current_id:
            current_regex = m2.group(1).strip('"')
            continue
        m3 = re.match(r'\s+owner_layer:\s*"?(.*?)"?\s*$', line)
        if m3 and current_id:
            current_owner = m3.group(1).strip('"')

if current_id and current_regex:
    entries.append((current_id, current_regex, current_owner or ''))

for pid, regex, owner in entries:
    if 'menu' in pid or (owner and 'observer' in owner and 'menu' in pid):
        cat = 'menu'
    elif 'freeform' in pid:
        cat = 'freeform'
    elif 'recovery' in pid or 'queued' in pid:
        cat = 'recovery'
    elif 'menu' in pid or ('observer' in owner and 'orchestrator' not in owner):
        cat = 'menu'
    else:
        cat = 'menu'
    print(f"{cat}\t{regex}:{pid}")
PYEOF
) || {
    echo "[stuck-patterns-lib] WARN: YAML parse failed, falling back to empty arrays" >&2
    return 0
  }

  while IFS=$'\t' read -r category entry; do
    [[ -z "$category" ]] && continue
    case "$category" in
      menu)     STUCK_PATTERN_MENU_ARR+=("$entry") ;;
      freeform) STUCK_PATTERN_FREEFORM_ARR+=("$entry") ;;
      recovery) STUCK_PATTERN_RECOVERY_ARR+=("$entry") ;;
    esac
  done <<< "$parsed"
}
