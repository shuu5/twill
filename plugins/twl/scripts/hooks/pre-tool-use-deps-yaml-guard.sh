#!/usr/bin/env bash
# PreToolUse hook: deps.yaml YAML syntax guard
#
# Write/Edit ツールで deps.yaml を変更しようとする際、
# 変更後の内容が有効な YAML かどうかを事前検証する。
# 不正な YAML を disk に書き込む前に exit 2 でブロックする。
#
# Write: tool_input.content を直接 YAML parse
# Edit:  tool_input.file_content（ペイロード内の現在内容）を優先して取得し、
#        なければ file_path のディスク内容にフォールバック。
#        old_string/new_string で simulated apply 後に YAML parse。
#
# 検証コマンド: python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"
# (~0.05s で実行、pyyaml が開発環境で必須依存として保証される)

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# JSON パース失敗時は no-op
if ! echo "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# ファイルパスを取得し、deps.yaml 対象かチェック
file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
  exit 0
fi

# deps.yaml 以外は no-op（basename で末尾一致）
if [[ "$(basename "$file_path")" != "deps.yaml" ]]; then
  exit 0
fi

# --- YAML 検証関数 ---
validate_yaml() {
  local content="$1"
  local err
  err=$(echo "$content" | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" 2>&1)
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "deps.yaml YAML syntax error: $err" >&2
    return 1
  fi
  return 0
}

if [[ "$tool_name" == "Write" ]]; then
  # content が null または存在しない場合は no-op
  content=$(echo "$payload" | jq -r '.tool_input.content // empty')
  if [[ -z "$content" ]]; then
    exit 0
  fi
  validate_yaml "$content" || exit 2

elif [[ "$tool_name" == "Edit" ]]; then
  old_string=$(echo "$payload" | jq -r '.tool_input.old_string // empty')
  new_string=$(echo "$payload" | jq -r '.tool_input.new_string // empty')

  # old_string が空の場合は no-op（old_string 必須の Edit ツール仕様に従い）
  if [[ -z "$old_string" ]]; then
    exit 0
  fi

  # ペイロード内の file_content を優先して取得（テスト・互換性対応）
  # なければ file_path のディスク内容にフォールバック
  current=$(echo "$payload" | jq -r '.tool_input.file_content // empty')
  if [[ -z "$current" ]]; then
    # path traversal 防御: realpath 正規化 + リポジトリルート配下確認
    # python3 を使用して realpath 不在環境（macOS BSD 等）にも対応
    canonical_path=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$file_path" 2>/dev/null) || {
      echo "ERROR: file_path を解決できません: $file_path" >&2
      exit 1
    }
    repo_root=$(git -C "$(dirname "$canonical_path")" rev-parse --show-toplevel 2>/dev/null) || {
      echo "ERROR: git リポジトリが見つかりません: $canonical_path" >&2
      exit 1
    }
    case "$canonical_path" in
      "$repo_root"/*)
        ;;
      *)
        echo "ERROR: リポジトリ外のパスは guard 対象外: $canonical_path (root: $repo_root)" >&2
        exit 1
        ;;
    esac
    if [[ ! -f "$canonical_path" ]]; then
      exit 0
    fi
    current=$(cat "$canonical_path")
  fi

  # old_string が存在しない場合は exit 2（apply 失敗 = YAML 未検証 = ブロック）
  if [[ "$current" != *"$old_string"* ]]; then
    echo "deps.yaml YAML guard: old_string not found in current content — ブロック" >&2
    exit 2
  fi

  applied="${current//"$old_string"/"$new_string"}"

  validate_yaml "$applied" || exit 2
fi

exit 0
