#!/usr/bin/env bats
# poll-phase-entry-key-migration.bats
# Requirement: poll_phase() entry-key 形式統一
#
# Spec: openspec/changes/poll-phase-entry-key-migration/specs/poll-phase-entry-key.md
#
# テスト戦略:
#   autopilot-orchestrator.sh の poll_phase() は直接呼び出しが難しい大きな関数のため、
#   テストダブルスクリプト (poll-phase-double.sh) を生成して各 Requirement を検証する。
#
#   poll-phase-double.sh は以下を抽出・再現する:
#   - issue_to_entry の構築ロジック（キー形式の検証）
#   - cleaned_up の設定ロジック（キー形式の検証）
#   - state-read.sh の --repo 引数付与ロジック
#   - window_name 生成ロジック

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup: サンドボックスとテストダブルを初期化
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # state-read/state-write 呼び出しをログに記録するスタブ
  STATE_READ_LOG="$SANDBOX/state-read-calls.txt"
  STATE_WRITE_LOG="$SANDBOX/state-write-calls.txt"
  CLEANUP_WORKER_LOG="$SANDBOX/cleanup-worker-calls.txt"
  export STATE_READ_LOG STATE_WRITE_LOG CLEANUP_WORKER_LOG

  # state-read.sh スタブ: 引数を記録し、status を返す
  cat > "$SANDBOX/scripts/state-read.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STATE_READ_LOG:-/dev/null}"
# --field status に対して issue ファイルから status を返す
AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
issue=""
field=""
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    --issue) j=$((i+1)); issue="${!j}" ;;
    --field) j=$((i+1)); field="${!j}" ;;
  esac
done
if [[ "$field" == "status" && -n "$issue" && -n "$AUTOPILOT_DIR" ]]; then
  f="$AUTOPILOT_DIR/issues/issue-${issue}.json"
  if [[ -f "$f" ]]; then
    jq -r '.status' "$f"
    exit 0
  fi
fi
echo ""
exit 0
STUB
  chmod +x "$SANDBOX/scripts/state-read.sh"

  # state-write.sh スタブ: 引数を記録し、issue JSON を更新
  cat > "$SANDBOX/scripts/state-write.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STATE_WRITE_LOG:-/dev/null}"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
issue=""
status_val=""
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    --issue) j=$((i+1)); issue="${!j}" ;;
    --set)   j=$((i+1)); val="${!j}"
             [[ "$val" == status=* ]] && status_val="${val#status=}" ;;
  esac
done
if [[ -n "$AUTOPILOT_DIR" && -n "$issue" && -n "$status_val" ]]; then
  f="$AUTOPILOT_DIR/issues/issue-${issue}.json"
  if [[ -f "$f" ]]; then
    tmp=$(mktemp)
    jq --arg s "$status_val" '.status = $s' "$f" > "$tmp" && mv "$tmp" "$f"
  fi
fi
STUB
  chmod +x "$SANDBOX/scripts/state-write.sh"

  # tmux スタブ
  stub_command "tmux" 'exit 0'

  # crash-detect.sh スタブ（デフォルト: exit 0 = クラッシュなし）
  stub_command "bash" 'exit 0'
  # スタブ化した bash は使わず、scripts 内のスタブを直接使う
  cat > "$SANDBOX/scripts/crash-detect.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$SANDBOX/scripts/crash-detect.sh"

  # health-check.sh スタブ（デフォルト: exit 0 = 正常）
  cat > "$SANDBOX/scripts/health-check.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  # check_and_nudge / cleanup_worker を含む poll-phase-double.sh を生成
  # このスクリプトは poll_phase() の構造を最小再現した test double
  _generate_poll_phase_double
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# _generate_poll_phase_double: poll_phase() の構造を再現したテストダブルを生成
#
# 引数:
#   --entries "e1 e2 ..."   スペース区切りの entry リスト
#   --max-poll N            最大ポーリング数（デフォルト: 1）
#
# 出力ファイル:
#   $SANDBOX/issue_list.txt          issue_list 配列の内容（改行区切り）
#   $SANDBOX/issue_to_entry.txt      "key=value" 形式のマッピング（改行区切り）
#   $SANDBOX/cleaned_up.txt          cleaned_up されたキー（改行区切り）
#   $SANDBOX/window_names.txt        各 issue の window_name（改行区切り）
#   $STATE_READ_LOG                  state-read.sh 呼び出し引数
# ---------------------------------------------------------------------------

_generate_poll_phase_double() {
  cat > "$SANDBOX/scripts/poll-phase-double.sh" <<'DOUBLE_EOF'
#!/usr/bin/env bash
# poll-phase-double.sh — poll_phase() の構造を再現したテストダブル
# issue_to_entry・cleaned_up・state-read 引数・window_name を検証する
set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
MAX_POLL="${MAX_POLL:-1}"

# 出力先ファイル（環境変数で注入）
ISSUE_LIST_FILE="${ISSUE_LIST_FILE:-/dev/null}"
ISSUE_TO_ENTRY_FILE="${ISSUE_TO_ENTRY_FILE:-/dev/null}"
CLEANED_UP_FILE="${CLEANED_UP_FILE:-/dev/null}"
WINDOW_NAMES_FILE="${WINDOW_NAMES_FILE:-/dev/null}"

# 引数: entries（スペース区切り）
entries=("$@")

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "Error: entries required" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# Requirement: issue_to_entry キーのentry形式統一
# issue_to_entry は entry 形式（repo_id:issue_num）をキーとする
# -----------------------------------------------------------------------
declare -a issue_list=()
declare -A issue_to_entry=()

for e in "${entries[@]}"; do
  # 実装後: キーは entry 全体（repo_id:issue_num）
  issue_list+=("$e")
  issue_to_entry["$e"]="$e"
done

# issue_list を出力
printf '%s\n' "${issue_list[@]}" > "$ISSUE_LIST_FILE"

# issue_to_entry マッピングを出力
for key in "${!issue_to_entry[@]}"; do
  printf '%s=%s\n' "$key" "${issue_to_entry[$key]}" >> "$ISSUE_TO_ENTRY_FILE"
done

# -----------------------------------------------------------------------
# Requirement: cleaned_up キーのentry形式統一
# cleaned_up は entry 形式（repo_id:issue_num）をキーとする
# -----------------------------------------------------------------------
declare -A cleaned_up=()

poll_count=0
while true; do
  all_resolved=1  # 1=true（整数フラグ; set -e 安全）

  for entry in "${issue_list[@]}"; do
    # entry から repo_id と issue_num を分解
    repo_id="${entry%%:*}"
    issue_num="${entry#*:}"

    # state-read.sh 呼び出し: --repo は _default 以外に付与
    status=""
    if [[ "$repo_id" == "_default" ]]; then
      status=$(python3 -m twl.autopilot.state read \
        --type issue --issue "$issue_num" --field status 2>/dev/null) || status=""
    else
      status=$(python3 -m twl.autopilot.state read \
        --type issue --repo "$repo_id" --issue "$issue_num" --field status 2>/dev/null) || status=""
    fi

    case "$status" in
      done|failed)
        # Requirement: cleaned_up キーはentry形式
        if [[ -z "${cleaned_up[$entry]:-}" ]]; then
          printf '%s\n' "$entry" >> "$CLEANED_UP_FILE"
          cleaned_up["$entry"]=1
        fi
        ;;
      merge-ready)
        ;;
      running)
        all_resolved=0  # 未解決あり

        # Requirement: window_name のクロスリポ対応
        if [[ "$repo_id" == "_default" ]]; then
          window_name="ap-#${issue_num}"
        else
          window_name="ap-${repo_id}-#${issue_num}"
        fi
        printf '%s=%s\n' "$entry" "$window_name" >> "$WINDOW_NAMES_FILE"
        ;;
      *)
        all_resolved=0  # 未解決あり
        ;;
    esac
  done

  [[ "$all_resolved" -eq 1 ]] && break

  poll_count=$((poll_count + 1))
  [[ "$poll_count" -ge "$MAX_POLL" ]] && break
done
DOUBLE_EOF
  chmod +x "$SANDBOX/scripts/poll-phase-double.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: issue JSON を作成（状態指定）
# create_entry_issue_json <entry> <status>
#   entry: "repo_id:issue_num" 形式
# ---------------------------------------------------------------------------

create_entry_issue_json() {
  local entry="$1"
  local status="$2"
  local issue_num="${entry#*:}"
  create_issue_json "$issue_num" "$status"
}

# ---------------------------------------------------------------------------
# ヘルパー: ISSUE_TO_ENTRY_FILE から特定キーの値を取得
# ---------------------------------------------------------------------------
_get_entry_for_key() {
  local key="$1"
  local file="${ISSUE_TO_ENTRY_FILE:-}"
  if [[ -f "$file" ]]; then
    grep "^${key}=" "$file" | cut -d= -f2- | head -1
  fi
}

# ===========================================================================
# Requirement: issue_to_entry キーのentry形式統一
# Spec: specs/poll-phase-entry-key.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 単一リポで poll_phase を実行する
# WHEN entries が ["_default:42"] の形式で渡された場合
# THEN issue_list に "_default:42" が格納され、
#      issue_to_entry["_default:42"] が "_default:42" を返す
# ---------------------------------------------------------------------------

@test "issue_to_entry: 単一リポ _default:42 — issue_list に entry 形式で格納される" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # issue_list に "_default:42" が含まれること（issue番号 "42" のみではない）
  assert [ -f "$ISSUE_LIST_FILE" ]
  grep -qx "_default:42" "$ISSUE_LIST_FILE"
}

@test "issue_to_entry: 単一リポ _default:42 — issue_to_entry のキーが entry 形式" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # issue_to_entry["_default:42"] = "_default:42" であること
  assert [ -f "$ISSUE_TO_ENTRY_FILE" ]
  grep -qx "_default:42=_default:42" "$ISSUE_TO_ENTRY_FILE"
}

@test "issue_to_entry: 単一リポ — issue_list に issue番号のみ（42）が格納されない（regression）" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # issue番号だけ（"42"）がキーになっていないこと
  assert [ -f "$ISSUE_LIST_FILE" ]
  ! grep -qx "42" "$ISSUE_LIST_FILE"
}

# ---------------------------------------------------------------------------
# Scenario: クロスリポで同一番号の Issue が同一 Phase に存在する
# WHEN entries が ["loom:42", "loom-plugin-dev:42"] の形式で渡された場合
# THEN issue_list に両エントリが格納され、どちらも上書きなく保持される
# ---------------------------------------------------------------------------

@test "issue_to_entry: クロスリポ同一番号 — 両 entry が issue_list に格納される" {
  create_entry_issue_json "loom:42" "done"
  create_issue_json 42 "done"  # loom-plugin-dev:42 も同じ issue ファイルを共用

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42" "loom-plugin-dev:42"
  assert_success

  # 両エントリが issue_list に存在すること
  assert [ -f "$ISSUE_LIST_FILE" ]
  grep -qx "loom:42" "$ISSUE_LIST_FILE"
  grep -qx "loom-plugin-dev:42" "$ISSUE_LIST_FILE"
}

@test "issue_to_entry: クロスリポ同一番号 — issue_to_entry に両マッピングが保持される（上書きなし）" {
  create_issue_json 42 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42" "loom-plugin-dev:42"
  assert_success

  # 両方のキーでマッピングが存在すること（一方が他方を上書きしていない）
  assert [ -f "$ISSUE_TO_ENTRY_FILE" ]
  local line_count
  line_count=$(wc -l < "$ISSUE_TO_ENTRY_FILE")
  [ "$line_count" -ge 2 ]

  grep -qx "loom:42=loom:42" "$ISSUE_TO_ENTRY_FILE"
  grep -qx "loom-plugin-dev:42=loom-plugin-dev:42" "$ISSUE_TO_ENTRY_FILE"
}

@test "issue_to_entry: クロスリポ — issue番号のみ（42）のキーが存在しない（regression）" {
  create_issue_json 42 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42" "loom-plugin-dev:42"
  assert_success

  # "42=..." というキーが存在しないこと（上書きバグの regression）
  assert [ -f "$ISSUE_TO_ENTRY_FILE" ]
  ! grep -qx "42=.*" "$ISSUE_TO_ENTRY_FILE"
}

# ===========================================================================
# Requirement: cleaned_up キーのentry形式統一
# Spec: specs/poll-phase-entry-key.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Issue が done/failed になった後の二重クリーンアップ防止
# WHEN entry "_default:42" の status が done になった場合
# THEN cleaned_up["_default:42"] が設定され、
#      同 entry に対する cleanup_worker の二重呼び出しが防止される
# ---------------------------------------------------------------------------

@test "cleaned_up: status=done の entry に cleaned_up が entry 形式で設定される" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # cleaned_up に "_default:42" が設定されること
  assert [ -f "$CLEANED_UP_FILE" ]
  grep -qx "_default:42" "$CLEANED_UP_FILE"
}

@test "cleaned_up: status=failed の entry でも cleaned_up が entry 形式で設定される" {
  create_entry_issue_json "_default:42" "failed"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  assert [ -f "$CLEANED_UP_FILE" ]
  grep -qx "_default:42" "$CLEANED_UP_FILE"
}

@test "cleaned_up: 二重クリーンアップ防止 — 同一 entry は1回だけ cleaned_up に記録される" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  MAX_POLL=3
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE MAX_POLL

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # "_default:42" が2回以上記録されていないこと
  local count
  count=$(grep -cx "_default:42" "$CLEANED_UP_FILE" || echo 0)
  [ "$count" -eq 1 ]
}

@test "cleaned_up: クロスリポ entry も entry 形式（loom:42）で cleaned_up に設定される" {
  create_issue_json 42 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42"
  assert_success

  assert [ -f "$CLEANED_UP_FILE" ]
  grep -qx "loom:42" "$CLEANED_UP_FILE"
}

@test "cleaned_up: issue番号のみ（42）は cleaned_up のキーに使われない（regression）" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # "42" だけのキーは存在しないこと
  ! grep -qx "42" "$CLEANED_UP_FILE"
}

# ===========================================================================
# Requirement: state-read/state-write への --repo 引数付与
# Spec: specs/poll-phase-entry-key.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: クロスリポ Issue の状態読み込み
# WHEN entry の repo_id が "loom" で issue_num が 42 の場合
# THEN state-read.sh --type issue --repo loom --issue 42 --field status が呼ばれる
# ---------------------------------------------------------------------------

@test "state-read --repo: クロスリポ entry — --repo <repo_id> 引数が渡される" {
  create_issue_json 42 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42"
  assert_success

  # state-read.sh に --repo loom が渡されること
  assert [ -f "$STATE_READ_LOG" ]
  grep -q -- "--repo loom" "$STATE_READ_LOG"
}

@test "state-read --repo: クロスリポ entry — --issue 42 と --repo loom が同一呼び出しに含まれる" {
  create_issue_json 42 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42"
  assert_success

  # --type issue --repo loom --issue 42 --field status の完全形式で呼ばれること
  grep -q -- "--type issue" "$STATE_READ_LOG"
  grep -q -- "--repo loom" "$STATE_READ_LOG"
  grep -q -- "--issue 42" "$STATE_READ_LOG"
  grep -q -- "--field status" "$STATE_READ_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: 単一リポ Issue の状態読み込み
# WHEN entry の repo_id が "_default" で issue_num が 42 の場合
# THEN state-read.sh --type issue --issue 42 --field status が呼ばれる（--repo 引数なし）
# ---------------------------------------------------------------------------

@test "state-read --repo: 単一リポ _default — --repo 引数が渡されない" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # state-read.sh に --repo が渡されていないこと
  assert [ -f "$STATE_READ_LOG" ]
  ! grep -q -- "--repo" "$STATE_READ_LOG"
}

@test "state-read --repo: 単一リポ _default — --issue 42 と --field status は渡される" {
  create_entry_issue_json "_default:42" "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # --issue 42 と --field status は渡されていること
  grep -q -- "--issue 42" "$STATE_READ_LOG"
  grep -q -- "--field status" "$STATE_READ_LOG"
}

@test "state-read --repo: 混在エントリ — _default は --repo なし、loom は --repo loom あり" {
  create_entry_issue_json "_default:10" "done"
  create_issue_json 20 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:10" "loom:20"
  assert_success

  assert [ -f "$STATE_READ_LOG" ]
  # loom:20 用の呼び出しに --repo loom が含まれること
  grep -q -- "--repo loom" "$STATE_READ_LOG"
  # _default:10 用の呼び出しには --repo が含まれないこと
  # （少なくとも1行は --repo なしで --issue 10 を含むこと）
  grep -- "--issue 10" "$STATE_READ_LOG" | grep -qv -- "--repo"
}

# ===========================================================================
# Requirement: window_name のクロスリポ対応
# Spec: specs/poll-phase-entry-key.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 単一リポでのウィンドウ名生成
# WHEN entry の repo_id が "_default" の場合
# THEN window_name が "ap-#42" 形式で生成される
# ---------------------------------------------------------------------------

@test "window_name: _default エントリ — ap-#42 形式で生成される" {
  create_entry_issue_json "_default:42" "running"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  MAX_POLL=1
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE MAX_POLL

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  assert [ -f "$WINDOW_NAMES_FILE" ]
  grep -qx "_default:42=ap-#42" "$WINDOW_NAMES_FILE"
}

@test "window_name: _default エントリ — repo_id をウィンドウ名に含まない" {
  create_entry_issue_json "_default:42" "running"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  MAX_POLL=1
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE MAX_POLL

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # "ap-_default-#42" のような形式ではないこと
  ! grep -q "ap-_default" "$WINDOW_NAMES_FILE"
}

# ---------------------------------------------------------------------------
# Scenario: クロスリポでのウィンドウ名生成
# WHEN entry の repo_id が "loom-plugin-dev" の場合
# THEN window_name が "ap-loom-plugin-dev-#42" 形式で生成される
# ---------------------------------------------------------------------------

@test "window_name: loom-plugin-dev エントリ — ap-loom-plugin-dev-#42 形式で生成される" {
  create_issue_json 42 "running"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  MAX_POLL=1
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE MAX_POLL

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom-plugin-dev:42"
  assert_success

  assert [ -f "$WINDOW_NAMES_FILE" ]
  grep -qx "loom-plugin-dev:42=ap-loom-plugin-dev-#42" "$WINDOW_NAMES_FILE"
}

@test "window_name: loom エントリ — ap-loom-#42 形式で生成される" {
  create_issue_json 42 "running"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  MAX_POLL=1
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE MAX_POLL

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42"
  assert_success

  assert [ -f "$WINDOW_NAMES_FILE" ]
  grep -qx "loom:42=ap-loom-#42" "$WINDOW_NAMES_FILE"
}

@test "window_name: クロスリポと単一リポの混在 — それぞれ正しい形式で生成される" {
  create_entry_issue_json "_default:10" "running"
  create_issue_json 20 "running"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  MAX_POLL=1
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE MAX_POLL

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:10" "loom:20"
  assert_success

  assert [ -f "$WINDOW_NAMES_FILE" ]
  # _default は ap-#N 形式
  grep -qx "_default:10=ap-#10" "$WINDOW_NAMES_FILE"
  # クロスリポは ap-{repo_id}-#N 形式
  grep -qx "loom:20=ap-loom-#20" "$WINDOW_NAMES_FILE"
}

# ===========================================================================
# Edge cases: 境界値・複合シナリオ
# ===========================================================================

@test "edge: entries なしの場合はエラーで失敗する" {
  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh"
  assert_failure
}

@test "edge: merge-ready ステータスの entry は issue_list に格納されるが cleaned_up されない" {
  create_entry_issue_json "_default:42" "merge-ready"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:42"
  assert_success

  # issue_list には含まれる
  assert [ -f "$ISSUE_LIST_FILE" ]
  grep -qx "_default:42" "$ISSUE_LIST_FILE"

  # cleaned_up には含まれない（merge-ready は cleanup 対象外）
  [ ! -f "$CLEANED_UP_FILE" ] || ! grep -qx "_default:42" "$CLEANED_UP_FILE"
}

@test "edge: 複数の done/failed エントリが混在する場合、全て entry 形式で cleaned_up される" {
  create_entry_issue_json "_default:10" "done"
  create_issue_json 20 "failed"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "_default:10" "loom:20"
  assert_success

  assert [ -f "$CLEANED_UP_FILE" ]
  grep -qx "_default:10" "$CLEANED_UP_FILE"
  grep -qx "loom:20" "$CLEANED_UP_FILE"
}

@test "edge: issue_num が同じクロスリポ entry は独立して管理される（衝突なし）" {
  create_issue_json 42 "done"

  ISSUE_LIST_FILE="$SANDBOX/issue_list.txt"
  ISSUE_TO_ENTRY_FILE="$SANDBOX/issue_to_entry.txt"
  CLEANED_UP_FILE="$SANDBOX/cleaned_up.txt"
  WINDOW_NAMES_FILE="$SANDBOX/window_names.txt"
  export ISSUE_LIST_FILE ISSUE_TO_ENTRY_FILE CLEANED_UP_FILE WINDOW_NAMES_FILE

  run bash "$SANDBOX/scripts/poll-phase-double.sh" "loom:42" "loom-plugin-dev:42"
  assert_success

  # 両エントリとも独立して cleaned_up される
  assert [ -f "$CLEANED_UP_FILE" ]
  grep -qx "loom:42" "$CLEANED_UP_FILE"
  grep -qx "loom-plugin-dev:42" "$CLEANED_UP_FILE"

  # cleaned_up に "42"（issue番号のみ）は存在しない
  ! grep -qx "42" "$CLEANED_UP_FILE"
}
