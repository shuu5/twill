#!/bin/bash
# spawn-controller.sh - su-observer 用の安全な controller 起動 wrapper
#
# Usage:
#   spawn-controller.sh <skill-name> <prompt-file> [cld-spawn extra args...]
#
#   <skill-name>: co-explore / co-issue / co-architect / co-autopilot /
#                 co-project / co-utility / co-self-improve
#                 （"twl:" prefix あり/なし両対応）
#   <prompt-file>: プロンプト本文が入ったファイルパス
#
# 動作:
#   1. skill 名を allow-list でバリデーション
#   2. prompt-file を読み、先頭に "/twl:<skill>\n" を prepend
#   3. --help / -h / --version / -v 等の invalid flag を弾く
#      （cld-spawn は *) break で positional 扱いし prompt に混入する）
#   4. --window-name 未指定時は wt-<skill>-<HHMMSS> を自動設定
#   5. cld-spawn を exec
#
# 背景: 本 wrapper は pitfalls-catalog.md 1.1-1.4 の失敗を防ぐ:
#   - --help 注入ミス
#   - /twl:<skill> 忘れ（skill invocation skip）
#   - window 名衝突
#   - prompt への文脈不足（呼び出し側で自主管理、本 wrapper は信じて prepend のみ）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# spawn-controller.sh は plugins/twl/skills/su-observer/scripts/ に置かれる
# cld-spawn は plugins/session/scripts/cld-spawn
TWILL_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
CLD_SPAWN="$TWILL_ROOT/plugins/session/scripts/cld-spawn"

if [[ ! -x "$CLD_SPAWN" ]]; then
  echo "Error: cld-spawn not executable at $CLD_SPAWN" >&2
  exit 2
fi

VALID_SKILLS=(co-explore co-issue co-architect co-autopilot co-project co-utility co-self-improve)

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <skill-name> <prompt-file> [cld-spawn extra args...]

Valid skills: ${VALID_SKILLS[*]}
(Accepts with or without "twl:" prefix)

Example:
  $(basename "$0") co-explore /tmp/my-prompt.txt
  $(basename "$0") co-issue /tmp/issue-prompt.txt --timeout 90
EOF
  exit 2
}

if [[ $# -lt 2 ]]; then
  usage
fi

SKILL="$1"
PROMPT_FILE="$2"
shift 2

# skill 名 normalize（"twl:" prefix 除去）
SKILL_NORMALIZED="${SKILL#twl:}"

# skill 名バリデーション
SKILL_FOUND=false
for s in "${VALID_SKILLS[@]}"; do
  if [[ "$SKILL_NORMALIZED" == "$s" ]]; then
    SKILL_FOUND=true
    break
  fi
done
if [[ "$SKILL_FOUND" == "false" ]]; then
  echo "Error: invalid skill name '$SKILL'." >&2
  echo "Valid: ${VALID_SKILLS[*]}" >&2
  exit 2
fi

# prompt file 存在確認
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: prompt file not found: $PROMPT_FILE" >&2
  exit 2
fi

# 残り引数に invalid flag が含まれていないか検査
# cld-spawn は *) break で positional として扱うため、誤 flag は prompt に混入する
for arg in "$@"; do
  case "$arg" in
    --help|-h|--version|-v)
      cat >&2 <<EOF
Error: '$arg' は cld-spawn の有効な option ではなく、prompt として誤注入される。
指定しないこと。

有効な cld-spawn option:
  --cd DIR, --env-file PATH, --window-name NAME, --timeout N,
  --model MODEL, --force-new
EOF
      exit 2
      ;;
  esac
done

# /twl:<skill> を prompt 先頭に prepend
PROMPT_BODY="$(cat "$PROMPT_FILE")"
FINAL_PROMPT="/twl:${SKILL_NORMALIZED}
${PROMPT_BODY}"

# --window-name が明示されていなければ自動生成
HAS_WINDOW_NAME=false
for arg in "$@"; do
  if [[ "$arg" == "--window-name" ]]; then
    HAS_WINDOW_NAME=true
    break
  fi
done

WINDOW_NAME_ARG=()
if [[ "$HAS_WINDOW_NAME" == "false" ]]; then
  WINDOW_NAME_ARG=(--window-name "wt-${SKILL_NORMALIZED}-$(date +%H%M%S)")
fi

# cld-spawn 呼び出し（extra args を first, prompt を last に配置する必要あり — cld-spawn の option parse は先に終わり、残りが PROMPT になる）
# 空配列ガード: set -u 環境で "${arr[@]}" が unbound を起こすため ${arr[@]+...} 形式で保護
exec "$CLD_SPAWN" "${WINDOW_NAME_ARG[@]+"${WINDOW_NAME_ARG[@]}"}" "$@" "$FINAL_PROMPT"
