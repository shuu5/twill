#!/usr/bin/env bash
# state-write.sh - issue-{N}.json / session.json の書き込み（遷移バリデーション付き）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --type <issue|session> [--issue N] [--set key=value]... [--role <pilot|worker>] [--init]

状態ファイルにフィールドを書き込む。status 更新時は遷移バリデーションを実行。

Options:
  --type <issue|session>  対象ファイルタイプ（必須）
  --issue N               Issue番号（type=issue 時必須）
  --set key=value         設定するフィールド（複数指定可）
  --role <pilot|worker>   実行ロール（必須）
  --init                  新規作成（type=issue: status=running で初期化）
  -h, --help              このヘルプを表示

状態遷移ルール:
  (init) → running
  running → merge-ready | failed
  merge-ready → done | failed
  failed → running (retry_count < 1 の場合のみ)
  done → (終端状態、遷移不可)
EOF
}

type=""
issue=""
role=""
init=false
declare -a sets=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) type="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --set) sets+=("$2"); shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --init) init=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# ── バリデーション ──

if [[ -z "$type" ]]; then
  echo "ERROR: --type は必須です" >&2
  exit 1
fi

if [[ "$type" != "issue" && "$type" != "session" ]]; then
  echo "ERROR: --type は issue または session を指定してください" >&2
  exit 1
fi

if [[ -z "$role" ]]; then
  echo "ERROR: --role は必須です" >&2
  exit 1
fi

if [[ "$role" != "pilot" && "$role" != "worker" ]]; then
  echo "ERROR: --role は pilot または worker を指定してください" >&2
  exit 1
fi

if [[ "$type" == "issue" && -z "$issue" ]]; then
  echo "ERROR: type=issue の場合 --issue は必須です" >&2
  exit 1
fi

# issue番号の数値バリデーション
if [[ "$type" == "issue" && -n "$issue" && ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --issue は正の整数を指定してください: $issue" >&2
  exit 1
fi

# ── ロールベースアクセス制御 ──

if [[ "$role" == "worker" && "$type" == "session" ]]; then
  echo "ERROR: Worker は session.json への書き込み権限がありません" >&2
  exit 1
fi

# Pilot の issue-{N}.json アクセス制限: status と merged_at のみ許可
if [[ "$role" == "pilot" && "$type" == "issue" ]]; then
  for kv in "${sets[@]}"; do
    key="${kv%%=*}"
    if [[ "$key" != "status" && "$key" != "merged_at" && "$key" != "failure" ]]; then
      echo "ERROR: Pilot は issue-{N}.json の $key フィールドへの書き込み権限がありません（status, merged_at, failure のみ許可）" >&2
      exit 1
    fi
  done
fi

# ── ファイルパスの決定 ──

if [[ "$type" == "issue" ]]; then
  file="$AUTOPILOT_DIR/issues/issue-${issue}.json"
elif [[ "$type" == "session" ]]; then
  file="$AUTOPILOT_DIR/session.json"
fi

# ── 新規作成（--init） ──

if [[ "$init" == "true" ]]; then
  # --init 時のロールチェック: issue は worker のみ
  if [[ "$type" == "issue" && "$role" != "worker" ]]; then
    echo "ERROR: issue-{N}.json の --init は worker ロールのみ許可されています" >&2
    exit 1
  fi
  if [[ "$type" == "issue" ]]; then
    if [[ -f "$file" ]]; then
      echo "ERROR: issue-${issue}.json は既に存在します" >&2
      exit 1
    fi
    # ディレクトリ確保
    mkdir -p "$(dirname "$file")"
    # デフォルト値で作成
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n \
      --argjson issue "$issue" \
      --arg started_at "$now" \
      '{
        issue: $issue,
        status: "running",
        branch: "",
        pr: null,
        window: "",
        started_at: $started_at,
        current_step: "",
        retry_count: 0,
        fix_instructions: null,
        merged_at: null,
        files_changed: [],
        failure: null
      }' > "$file"
    echo "OK: issue-${issue}.json を作成しました (status=running)"
    exit 0
  elif [[ "$type" == "session" ]]; then
    # session.json の新規作成は autopilot-init.sh + session-create で行う
    echo "ERROR: session.json の --init は state-write.sh ではサポートしていません。session-create.sh を使用してください" >&2
    exit 1
  fi
fi

# ── 既存ファイルの更新 ──

if [[ ! -f "$file" ]]; then
  echo "ERROR: ファイルが存在しません: $file" >&2
  exit 1
fi

if [[ ${#sets[@]} -eq 0 ]]; then
  echo "ERROR: --set が指定されていません" >&2
  exit 1
fi

# 現在のJSONを読み込み
current_json=$(cat "$file")

for kv in "${sets[@]}"; do
  key="${kv%%=*}"
  value="${kv#*=}"

  # ── key ホワイトリスト検証（jq インジェクション防止） ──
  if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "ERROR: 不正なフィールド名: $key（英数字とアンダースコアのみ許可）" >&2
    exit 1
  fi

  # ── status 更新時の遷移バリデーション ──
  if [[ "$key" == "status" && "$type" == "issue" ]]; then
    current_status=$(echo "$current_json" | jq -r '.status')

    # done 終端状態の保護
    if [[ "$current_status" == "done" ]]; then
      echo "ERROR: done は終端状態です。status を変更できません" >&2
      exit 1
    fi

    # 許可される遷移テーブル
    valid=false
    case "${current_status}:${value}" in
      running:merge-ready) valid=true ;;
      running:failed)      valid=true ;;
      merge-ready:done)    valid=true ;;
      merge-ready:failed)  valid=true ;;
      failed:running)
        # retry_count < 1 の場合のみ許可
        retry_count=$(echo "$current_json" | jq -r '.retry_count // 0')
        if (( retry_count < 1 )); then
          valid=true
        else
          echo "ERROR: リトライ上限に達しています (retry_count=$retry_count >= 1)。failed → running への遷移は不可" >&2
          exit 1
        fi
        ;;
    esac

    if [[ "$valid" != "true" ]]; then
      echo "ERROR: 不正な状態遷移: $current_status → $value" >&2
      exit 1
    fi

    # failed → running リトライ時に retry_count をインクリメント
    if [[ "$current_status" == "failed" && "$value" == "running" ]]; then
      current_json=$(echo "$current_json" | jq '.retry_count += 1')
    fi
  fi

  # JSON にフィールドを設定
  # 値が JSON（配列/オブジェクト/null/数値/ブール）かどうか判定
  if echo "$value" | jq '.' &>/dev/null 2>&1; then
    current_json=$(echo "$current_json" | jq --argjson v "$value" ".$key = \$v")
  else
    current_json=$(echo "$current_json" | jq --arg v "$value" ".$key = \$v")
  fi
done

# アトミック書き込み（.tmp + mv パターン）
echo "$current_json" | jq '.' > "${file}.tmp" && mv "${file}.tmp" "$file"
echo "OK: $file を更新しました"
