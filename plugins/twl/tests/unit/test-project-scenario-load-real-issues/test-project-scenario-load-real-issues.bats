#!/usr/bin/env bats
# test-project-scenario-load-real-issues.bats
# Requirement: test-project-scenario-load --real-issues フラグ対応
# Spec: deltaspec/changes/issue-480/specs/real-issues-mode/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# test-project-scenario-load.md の --real-issues フラグ追加を検証するテスト群。
# 実装は Markdown ベース LLM コマンドのため、コマンドロジックを
# シェルスクリプトとして本ファイル内に再現し検証する。
#
# テスト構造:
#   - setup()    : 一時ディレクトリ、モック gh コマンド、テスト対象ロジックを配置
#   - teardown() : 一時ディレクトリを全削除
#
# テスト double 方針:
#   - gh CLI (ネットワーク呼び出し) はスタブで差し替える
#   - git コマンドはスタブで差し替える
#   - config.json はテスト内で直接生成する

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  GH_STATE_DIR="$SANDBOX/gh-state"
  GH_MOCK_DIR="$SANDBOX/gh-bin"
  GIT_MOCK_DIR="$SANDBOX/git-bin"
  mkdir -p "$GH_STATE_DIR" "$GH_MOCK_DIR" "$GIT_MOCK_DIR"

  export GH_STATE_DIR

  # モック gh を PATH 先頭に配置
  _write_gh_mock
  export PATH="$GH_MOCK_DIR:$GIT_MOCK_DIR:$PATH"

  # テスト対象ロジックスクリプトを配置
  _write_issue_create_script
  _write_loaded_issues_record_script
  _write_dedup_guard_script
  _write_backward_compat_script
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# ヘルパー: モック gh を書き出す
# ---------------------------------------------------------------------------

_write_gh_mock() {
  cat > "$GH_MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
# stub gh — GH_STATE_DIR 内のファイルで振る舞いを制御
set -uo pipefail

case "${1:-}" in
  issue)
    case "${2:-}" in
      create)
        # 引数: gh issue create --repo <owner/repo> --title <title> --body <body> --label <labels>
        repo=""
        title=""
        i=1
        while [[ $i -le $# ]]; do
          arg="${!i}"
          case "$arg" in
            --repo)  i=$((i+1)); repo="${!i}" ;;
            --title) i=$((i+1)); title="${!i}" ;;
          esac
          i=$((i+1))
        done
        repo_safe="${repo//\//_}"
        fail_file="$GH_STATE_DIR/${repo_safe}.issue-create-fail"
        if [[ -f "$fail_file" ]]; then
          echo "gh: issue creation failed for repo: ${repo}" >&2
          exit 1
        fi
        # 成功: 連番 issue number を返す
        counter_file="$GH_STATE_DIR/${repo_safe}.counter"
        if [[ -f "$counter_file" ]]; then
          n=$(cat "$counter_file")
        else
          n=0
        fi
        n=$((n+1))
        echo "$n" > "$counter_file"
        echo "https://github.com/${repo}/issues/${n}"
        exit 0
        ;;
      close)
        # 引数: gh issue close <number> --repo <owner/repo>
        exit 0
        ;;
    esac
    ;;
  *)
    echo "gh stub: unmatched args: $*" >&2
    exit 0
    ;;
esac
MOCK_EOF
  chmod +x "$GH_MOCK_DIR/gh"
}

# ---------------------------------------------------------------------------
# ヘルパー: --real-issues フラグで gh issue create を実行するスクリプト
# ---------------------------------------------------------------------------

_write_issue_create_script() {
  cat > "$SANDBOX/scripts/real-issues-create.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# real-issues-create.sh — --real-issues モードの Issue 起票ロジックを再現
# Usage: real-issues-create.sh --scenario <name> --config <path> --catalog <path>
# Exit code: 0 on success
# Output: JSON {"status":"loaded","scenario":"<name>","repo":"<repo>","issues":[...]}

set -euo pipefail

SCENARIO=""
CONFIG_PATH=""
CATALOG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="${2:-}"; shift 2 ;;
    --config)   CONFIG_PATH="${2:-}"; shift 2 ;;
    --catalog)  CATALOG_PATH="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SCENARIO" || -z "$CONFIG_PATH" ]]; then
  echo '{"error": "引数不足"}' >&2
  exit 1
fi

# config.json 読み込み
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo '{"error": "config.json が見つかりません"}' >&2
  exit 1
fi

MODE=$(jq -r '.mode' "$CONFIG_PATH")
REPO=$(jq -r '.repo // empty' "$CONFIG_PATH")

# モードチェック
if [[ "$MODE" != "real-issues" ]]; then
  echo '{"error": "--real-issues を使うには test-project-init --mode real-issues で初期化してください"}' >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  echo '{"error": "config.json に repo フィールドがありません"}' >&2
  exit 1
fi

# カタログ読み込み（簡易 stub: --catalog で YAML 代わりに JSON を受け取る）
if [[ -z "$CATALOG_PATH" || ! -f "$CATALOG_PATH" ]]; then
  echo '{"error": "catalog ファイルが見つかりません"}' >&2
  exit 1
fi

# シナリオの issue_templates を取得
TEMPLATES=$(jq -e --arg s "$SCENARIO" '.[$s].issue_templates // empty' "$CATALOG_PATH" 2>/dev/null || true)
if [[ -z "$TEMPLATES" ]]; then
  echo "{\"error\": \"シナリオ '${SCENARIO}' が見つかりません\"}" >&2
  exit 1
fi

# 各 issue_template を起票
CREATED_ISSUES="[]"
while IFS= read -r tmpl; do
  id=$(echo "$tmpl" | jq -r '.id')
  title=$(echo "$tmpl" | jq -r '.title')
  body=$(echo "$tmpl" | jq -r '.body')
  labels=$(echo "$tmpl" | jq -r '(.labels // []) | join(",")')

  url=$(gh issue create \
    --repo "$REPO" \
    --title "$title" \
    --body "$body" \
    --label "$labels" 2>/dev/null)

  # URL から番号を抽出
  number="${url##*/}"

  CREATED_ISSUES=$(echo "$CREATED_ISSUES" | jq \
    --arg id "$id" \
    --arg url "$url" \
    --argjson n "$number" \
    '. + [{"id": $id, "number": $n, "url": $url}]')
done < <(echo "$TEMPLATES" | jq -c '.[]')

# loaded-issues.json を生成
LOADED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OUT_DIR="$(dirname "$CONFIG_PATH")"
jq -n \
  --arg scenario "$SCENARIO" \
  --arg repo "$REPO" \
  --arg loaded_at "$LOADED_AT" \
  --argjson issues "$CREATED_ISSUES" \
  '{"scenario":$scenario,"repo":$repo,"loaded_at":$loaded_at,"issues":$issues}' \
  > "$OUT_DIR/loaded-issues.json"

echo "{\"status\":\"loaded\",\"scenario\":\"$SCENARIO\",\"repo\":\"$REPO\",\"issue_count\":$(echo "$CREATED_ISSUES" | jq 'length')}"
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/real-issues-create.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: loaded-issues.json 記録スクリプト（構造検証用）
# ---------------------------------------------------------------------------

_write_loaded_issues_record_script() {
  cat > "$SANDBOX/scripts/validate-loaded-issues.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# validate-loaded-issues.sh — loaded-issues.json の構造を検証する
# Usage: validate-loaded-issues.sh <path>
# Exit code: 0 if valid

set -euo pipefail

FILE="${1:-}"
if [[ ! -f "$FILE" ]]; then
  echo "not found: $FILE" >&2
  exit 1
fi

# 必須フィールドの存在確認
jq -e '.scenario | length > 0' "$FILE" > /dev/null || { echo "missing: scenario" >&2; exit 1; }
jq -e '.repo | length > 0' "$FILE" > /dev/null || { echo "missing: repo" >&2; exit 1; }
jq -e '.loaded_at | length > 0' "$FILE" > /dev/null || { echo "missing: loaded_at" >&2; exit 1; }
jq -e '.issues | type == "array"' "$FILE" > /dev/null || { echo "missing: issues array" >&2; exit 1; }

# issues 配列の各要素: id, number, url
issue_count=$(jq '.issues | length' "$FILE")
if [[ "$issue_count" -gt 0 ]]; then
  jq -e '.issues[0] | has("id") and has("number") and has("url")' "$FILE" > /dev/null \
    || { echo "invalid issue structure" >&2; exit 1; }
fi

echo "valid"
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/validate-loaded-issues.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: 二重起票ガードスクリプト
# ---------------------------------------------------------------------------

_write_dedup_guard_script() {
  cat > "$SANDBOX/scripts/dedup-guard.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# dedup-guard.sh — 二重起票ガードロジックを再現
# Usage: dedup-guard.sh --scenario <name> --loaded-issues <path> [--force]
# Exit code: 0 = proceed, 2 = skip (already loaded)

set -euo pipefail

SCENARIO=""
LOADED_PATH=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)      SCENARIO="${2:-}"; shift 2 ;;
    --loaded-issues) LOADED_PATH="${2:-}"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

# loaded-issues.json が存在しない → 起票可能
if [[ ! -f "$LOADED_PATH" ]]; then
  echo '{"status":"proceed"}'
  exit 0
fi

# 同一シナリオの記録が存在するか確認
existing_scenario=$(jq -r '.scenario // empty' "$LOADED_PATH" 2>/dev/null || echo "")

if [[ "$existing_scenario" == "$SCENARIO" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    # --force: 既存 Issue を close して再起票可能にする
    existing_repo=$(jq -r '.repo // empty' "$LOADED_PATH")
    existing_issues=$(jq -r '.issues[].number' "$LOADED_PATH" 2>/dev/null || echo "")
    while IFS= read -r num; do
      [[ -z "$num" ]] && continue
      gh issue close "$num" --repo "$existing_repo" 2>/dev/null || true
    done <<< "$existing_issues"
    echo '{"status":"proceed","action":"force-recreate"}'
    exit 0
  else
    # スキップ
    echo '{"status":"skipped","reason":"already loaded","scenario":"'"$SCENARIO"'"}'
    exit 2
  fi
fi

echo '{"status":"proceed"}'
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/dedup-guard.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: 後退互換検証スクリプト（--real-issues フラグなし時の動作）
# ---------------------------------------------------------------------------

_write_backward_compat_script() {
  cat > "$SANDBOX/scripts/local-scenario-load.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# local-scenario-load.sh — --real-issues フラグなし時のローカルファイル生成ロジックを再現
# Usage: local-scenario-load.sh --scenario <name> --issues-dir <path> --catalog <path>

set -euo pipefail

SCENARIO=""
ISSUES_DIR=""
CATALOG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)   SCENARIO="${2:-}"; shift 2 ;;
    --issues-dir) ISSUES_DIR="${2:-}"; shift 2 ;;
    --catalog)    CATALOG_PATH="${2:-}"; shift 2 ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$CATALOG_PATH" ]]; then
  echo '{"error": "catalog not found"}' >&2
  exit 1
fi

TEMPLATES=$(jq -e --arg s "$SCENARIO" '.[$s].issue_templates // empty' "$CATALOG_PATH" 2>/dev/null || true)
if [[ -z "$TEMPLATES" ]]; then
  echo "{\"error\": \"シナリオ '${SCENARIO}' が見つかりません\"}" >&2
  exit 1
fi

mkdir -p "$ISSUES_DIR"
rm -f "$ISSUES_DIR"/*.md 2>/dev/null || true

CREATED_IDS="[]"
while IFS= read -r tmpl; do
  id=$(echo "$tmpl" | jq -r '.id')
  title=$(echo "$tmpl" | jq -r '.title')
  body=$(echo "$tmpl" | jq -r '.body')
  labels=$(echo "$tmpl" | jq -r '(.labels // []) | join(",")')

  cat > "$ISSUES_DIR/${id}.md" << EOF
---
id: ${id}
title: ${title}
labels: [${labels}]
status: open
---

${body}
EOF
  CREATED_IDS=$(echo "$CREATED_IDS" | jq --arg id "$id" '. + [$id]')
done < <(echo "$TEMPLATES" | jq -c '.[]')

echo "{\"status\":\"loaded\",\"scenario\":\"$SCENARIO\",\"issues\":$CREATED_IDS}"
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/local-scenario-load.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: テスト用カタログ JSON を生成する
# ---------------------------------------------------------------------------

_write_catalog_json() {
  local path="${1:-$SANDBOX/catalog.json}"
  cat > "$path" << 'CATALOG_EOF'
{
  "smoke-001": {
    "level": "smoke",
    "issue_templates": [
      {
        "id": "TEST-001",
        "title": "[Test] add hello world function",
        "body": "scripts/helper.sh に hello_world 関数を追加する。",
        "labels": ["test", "scope/test-target"]
      }
    ]
  },
  "smoke-002": {
    "level": "smoke",
    "issue_templates": [
      {
        "id": "TEST-001",
        "title": "[Test] add greeting function",
        "body": "scripts/helper.sh に greet 関数を追加する。",
        "labels": ["test", "scope/test-target"]
      },
      {
        "id": "TEST-002",
        "title": "[Test] add version command",
        "body": "scripts/helper.sh に version 関数を追加する。",
        "labels": ["test", "scope/test-target"]
      }
    ]
  }
}
CATALOG_EOF
}

# ---------------------------------------------------------------------------
# ヘルパー: real-issues モード用 config.json を生成する
# ---------------------------------------------------------------------------

_write_real_issues_config() {
  local path="${1:-$SANDBOX/.test-target/config.json}"
  local repo="${2:-owner/test-repo}"
  mkdir -p "$(dirname "$path")"
  jq -n \
    --arg repo "$repo" \
    '{"mode":"real-issues","repo":$repo,"initialized_at":"2025-01-01T00:00:00Z","worktree_path":"/tmp/test","branch":"test-target/main"}' \
    > "$path"
}

# ---------------------------------------------------------------------------
# ヘルパー: local モード用 config.json を生成する
# ---------------------------------------------------------------------------

_write_local_config() {
  local path="${1:-$SANDBOX/.test-target/config.json}"
  mkdir -p "$(dirname "$path")"
  jq -n \
    '{"mode":"local","repo":null,"initialized_at":"2025-01-01T00:00:00Z","worktree_path":"/tmp/test","branch":"test-target/main"}' \
    > "$path"
}

# ===========================================================================
# Requirement: --real-issues フラグ対応
# ===========================================================================

# Scenario: smoke-001 シナリオで実 Issue が起票される
# WHEN test-project-scenario-load --scenario smoke-001 --real-issues を実行する
# THEN config.json の repo フィールドが示す専用テストリポに smoke-001 の
#      issue_templates 全件が gh issue create で起票される
@test "real-issues: smoke-001 シナリオで gh issue create が起票される" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local repo="owner/test-repo"
  _write_real_issues_config "$config" "$repo"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog"
  [ "$status" -eq 0 ]

  # ステータスが loaded であること
  echo "$output" | jq -e '.status == "loaded"' > /dev/null
  # repo が設定値と一致すること
  echo "$output" | jq -e '.repo == "owner/test-repo"' > /dev/null
  # issue_count が 1（smoke-001 は 1 件）
  echo "$output" | jq -e '.issue_count == 1' > /dev/null
}

# Scenario: --mode local で init した後に --real-issues を指定した場合にエラーになる
# WHEN .test-target/config.json の mode が local の状態で --real-issues を実行する
# THEN {"error": "--real-issues を使うには test-project-init --mode real-issues で初期化してください"} を出力してエラー終了する
@test "real-issues: mode=local の config.json で --real-issues 実行時にエラー終了する" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  _write_local_config "$config"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.error | test("--real-issues")' > /dev/null
  echo "$output" | jq -e '.error | test("real-issues で初期化")' > /dev/null
}

# エッジケース: smoke-002 (2件テンプレート) で2件起票される
@test "real-issues: smoke-002 で issue_templates 2件が全件起票される" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local repo="owner/test-repo"
  _write_real_issues_config "$config" "$repo"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-002 \
    --config "$config" \
    --catalog "$catalog"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.issue_count == 2' > /dev/null
}

# エッジケース: 存在しないシナリオを指定した場合はエラー終了する
@test "real-issues: 存在しないシナリオ指定でエラー終了する" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  _write_real_issues_config "$config"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario nonexistent-999 \
    --config "$config" \
    --catalog "$catalog"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.error | test("見つかりません")' > /dev/null
}

# エッジケース: config.json が存在しない場合はエラー終了する
@test "real-issues: config.json が存在しない場合はエラー終了する" {
  local catalog="$SANDBOX/catalog.json"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$SANDBOX/.test-target/nonexistent-config.json" \
    --catalog "$catalog"
  [ "$status" -ne 0 ]
}

# ===========================================================================
# Requirement: loaded-issues.json への記録
# ===========================================================================

# Scenario: 起票後に loaded-issues.json が生成される
# WHEN --real-issues モードで Issue 起票に成功する
# THEN .test-target/loaded-issues.json に
#      {"scenario":"<name>","repo":"<repo>","loaded_at":"<ISO8601>","issues":[...]} 形式で記録される
@test "loaded-issues: 起票後に loaded-issues.json が生成される" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  _write_real_issues_config "$config"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog"
  [ "$status" -eq 0 ]

  # ファイルが存在すること
  [ -f "$loaded_issues" ]
}

# Scenario: loaded-issues.json のスキーマが仕様通りである
# WHEN --real-issues モードで Issue 起票に成功する
# THEN loaded-issues.json の全必須フィールドが存在する
@test "loaded-issues: loaded-issues.json に全必須フィールドが存在する" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  _write_real_issues_config "$config" "owner/test-repo"
  _write_catalog_json "$catalog"

  bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog" > /dev/null

  run bash "$SANDBOX/scripts/validate-loaded-issues.sh" "$loaded_issues"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

# Scenario: loaded-issues.json の scenario フィールドが一致する
@test "loaded-issues: loaded-issues.json の scenario フィールドが指定値と一致する" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  _write_real_issues_config "$config" "owner/test-repo"
  _write_catalog_json "$catalog"

  bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog" > /dev/null

  jq -e '.scenario == "smoke-001"' "$loaded_issues" > /dev/null
  jq -e '.repo == "owner/test-repo"' "$loaded_issues" > /dev/null
}

# エッジケース: loaded-issues.json の issues 配列に id/number/url が含まれる
@test "loaded-issues: issues 配列の各要素に id/number/url が含まれる" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  _write_real_issues_config "$config" "owner/test-repo"
  _write_catalog_json "$catalog"

  bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog" > /dev/null

  jq -e '.issues | length > 0' "$loaded_issues" > /dev/null
  jq -e '.issues[0] | has("id") and has("number") and has("url")' "$loaded_issues" > /dev/null
}

# エッジケース: loaded_at が ISO8601 形式の文字列である
@test "loaded-issues: loaded_at が ISO8601 形式の文字列である" {
  local config="$SANDBOX/.test-target/config.json"
  local catalog="$SANDBOX/catalog.json"
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  _write_real_issues_config "$config" "owner/test-repo"
  _write_catalog_json "$catalog"

  bash "$SANDBOX/scripts/real-issues-create.sh" \
    --scenario smoke-001 \
    --config "$config" \
    --catalog "$catalog" > /dev/null

  # ISO8601 パターン: YYYY-MM-DDTHH:MM:SSZ
  local loaded_at
  loaded_at=$(jq -r '.loaded_at' "$loaded_issues")
  [[ "$loaded_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# ===========================================================================
# Requirement: 二重起票ガード
# ===========================================================================

# Scenario: 既存の loaded-issues.json がある場合は skip する
# WHEN .test-target/loaded-issues.json が存在し scenario フィールドが一致する状態で --real-issues を実行する
# THEN 起票をスキップし {"status": "skipped", "reason": "already loaded", ...} を出力する
@test "dedup-guard: 同一シナリオの loaded-issues.json が存在する場合は skip する" {
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  mkdir -p "$(dirname "$loaded_issues")"

  # 事前に loaded-issues.json を配置（同一シナリオ）
  jq -n '{"scenario":"smoke-001","repo":"owner/test-repo","loaded_at":"2025-01-01T00:00:00Z","issues":[{"id":"TEST-001","number":1,"url":"https://github.com/owner/test-repo/issues/1"}]}' \
    > "$loaded_issues"

  run bash "$SANDBOX/scripts/dedup-guard.sh" \
    --scenario smoke-001 \
    --loaded-issues "$loaded_issues"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.status == "skipped"' > /dev/null
  echo "$output" | jq -e '.reason == "already loaded"' > /dev/null
}

# Scenario: --force フラグで強制再起票できる
# WHEN loaded-issues.json が存在する状態で --real-issues --force を実行する
# THEN 既存 Issue を gh issue close してから新たに gh issue create し loaded-issues.json を上書きする
@test "dedup-guard: --force フラグで既存 loaded-issues.json を上書き可能にする" {
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  mkdir -p "$(dirname "$loaded_issues")"

  jq -n '{"scenario":"smoke-001","repo":"owner/test-repo","loaded_at":"2025-01-01T00:00:00Z","issues":[{"id":"TEST-001","number":1,"url":"https://github.com/owner/test-repo/issues/1"}]}' \
    > "$loaded_issues"

  run bash "$SANDBOX/scripts/dedup-guard.sh" \
    --scenario smoke-001 \
    --loaded-issues "$loaded_issues" \
    --force
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "proceed"' > /dev/null
  echo "$output" | jq -e '.action == "force-recreate"' > /dev/null
}

# エッジケース: loaded-issues.json が存在しない場合は proceed する
@test "dedup-guard: loaded-issues.json が存在しない場合は proceed する" {
  run bash "$SANDBOX/scripts/dedup-guard.sh" \
    --scenario smoke-001 \
    --loaded-issues "$SANDBOX/.test-target/nonexistent-loaded-issues.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "proceed"' > /dev/null
}

# エッジケース: 異なるシナリオの loaded-issues.json が存在する場合は proceed する
@test "dedup-guard: 異なるシナリオの loaded-issues.json が存在する場合は proceed する" {
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  mkdir -p "$(dirname "$loaded_issues")"

  # 別シナリオの loaded-issues.json を配置
  jq -n '{"scenario":"smoke-002","repo":"owner/test-repo","loaded_at":"2025-01-01T00:00:00Z","issues":[]}' \
    > "$loaded_issues"

  run bash "$SANDBOX/scripts/dedup-guard.sh" \
    --scenario smoke-001 \
    --loaded-issues "$loaded_issues"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "proceed"' > /dev/null
}

# エッジケース: --force なしで同一シナリオの場合 status が 2 でかつ scenario フィールドが出力に含まれる
@test "dedup-guard: skip 時の出力に scenario フィールドが含まれる" {
  local loaded_issues="$SANDBOX/.test-target/loaded-issues.json"
  mkdir -p "$(dirname "$loaded_issues")"

  jq -n '{"scenario":"smoke-001","repo":"owner/test-repo","loaded_at":"2025-01-01T00:00:00Z","issues":[]}' \
    > "$loaded_issues"

  run bash "$SANDBOX/scripts/dedup-guard.sh" \
    --scenario smoke-001 \
    --loaded-issues "$loaded_issues"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.scenario == "smoke-001"' > /dev/null
}

# ===========================================================================
# Requirement: --local-only（未指定）の後退互換保証
# ===========================================================================

# Scenario: フラグ未指定時は既存のローカルファイル生成動作を維持する
# WHEN test-project-scenario-load --scenario smoke-001（--real-issues フラグなし）を実行する
# THEN 従来通り .test-target/issues/<id>.md にローカルファイルが生成され
#      loaded-issues.json は作成されない
@test "backward-compat: --real-issues なしの場合はローカル .md ファイルが生成される" {
  local issues_dir="$SANDBOX/.test-target/issues"
  local catalog="$SANDBOX/catalog.json"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/local-scenario-load.sh" \
    --scenario smoke-001 \
    --issues-dir "$issues_dir" \
    --catalog "$catalog"
  [ "$status" -eq 0 ]

  # .md ファイルが生成されていること
  [ -f "$issues_dir/TEST-001.md" ]
}

# Scenario: --real-issues なしの場合は loaded-issues.json が生成されない
@test "backward-compat: --real-issues なしの場合は loaded-issues.json が生成されない" {
  local issues_dir="$SANDBOX/.test-target/issues"
  local catalog="$SANDBOX/catalog.json"
  _write_catalog_json "$catalog"

  bash "$SANDBOX/scripts/local-scenario-load.sh" \
    --scenario smoke-001 \
    --issues-dir "$issues_dir" \
    --catalog "$catalog" > /dev/null

  # loaded-issues.json が存在しないこと
  [ ! -f "$SANDBOX/.test-target/loaded-issues.json" ]
}

# エッジケース: ローカルファイルの frontmatter に必須フィールドが含まれる
@test "backward-compat: 生成された .md ファイルに id/title/labels/status frontmatter が含まれる" {
  local issues_dir="$SANDBOX/.test-target/issues"
  local catalog="$SANDBOX/catalog.json"
  _write_catalog_json "$catalog"

  bash "$SANDBOX/scripts/local-scenario-load.sh" \
    --scenario smoke-001 \
    --issues-dir "$issues_dir" \
    --catalog "$catalog" > /dev/null

  # frontmatter 必須フィールドの確認
  grep -q "^id:" "$issues_dir/TEST-001.md"
  grep -q "^title:" "$issues_dir/TEST-001.md"
  grep -q "^labels:" "$issues_dir/TEST-001.md"
  grep -q "^status: open" "$issues_dir/TEST-001.md"
}

# エッジケース: smoke-002（2件）でローカルファイルが2件生成される
@test "backward-compat: smoke-002 で 2 件の .md ファイルが生成される" {
  local issues_dir="$SANDBOX/.test-target/issues"
  local catalog="$SANDBOX/catalog.json"
  _write_catalog_json "$catalog"

  run bash "$SANDBOX/scripts/local-scenario-load.sh" \
    --scenario smoke-002 \
    --issues-dir "$issues_dir" \
    --catalog "$catalog"
  [ "$status" -eq 0 ]

  [ -f "$issues_dir/TEST-001.md" ]
  [ -f "$issues_dir/TEST-002.md" ]
}

# エッジケース: 既存 .md ファイルがクリアされてから新規生成される
@test "backward-compat: 既存 .md ファイルがクリアされてから新規生成される" {
  local issues_dir="$SANDBOX/.test-target/issues"
  local catalog="$SANDBOX/catalog.json"
  _write_catalog_json "$catalog"

  # 事前に残留ファイルを配置
  mkdir -p "$issues_dir"
  touch "$issues_dir/STALE-001.md"
  touch "$issues_dir/STALE-002.md"

  bash "$SANDBOX/scripts/local-scenario-load.sh" \
    --scenario smoke-001 \
    --issues-dir "$issues_dir" \
    --catalog "$catalog" > /dev/null

  # 残留ファイルが削除されていること
  [ ! -f "$issues_dir/STALE-001.md" ]
  [ ! -f "$issues_dir/STALE-002.md" ]
  # 新規ファイルが存在すること
  [ -f "$issues_dir/TEST-001.md" ]
}
