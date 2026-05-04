#!/bin/bash
# supervisor-dir-validate.sh - SUPERVISOR_DIR パス検証共有ライブラリ
#
# Issue #1346: spawn-controller.sh の SUPERVISOR_DIR パス検証が未適用
# record-detection-gap.sh (PR #1345) の検証パターンを基にホワイトリスト方式で共有化。
#
# Usage:
#   source supervisor-dir-validate.sh
#   validate_supervisor_dir "${SUPERVISOR_DIR:-.supervisor}" || exit 1

# validate_supervisor_dir: SUPERVISOR_DIR の安全性を検証する
#
# 検証内容:
#   1. '..' パストラバーサルを含む場合は拒否
#   2. '/' で始まる絶対パスは拒否
#   3. ホワイトリスト方式: 許可文字 (英数字・ドット・ハイフン・アンダースコア・スラッシュ) 以外を拒否
#      ブラックリスト方式より包括的（改行・制御文字・NUL 等も自動排除）
#
# 引数:
#   $1: 検証対象のパス文字列
# 戻り値:
#   0: 検証通過
#   1: 検証失敗（エラーメッセージを stderr に出力）
validate_supervisor_dir() {
  local _dir="$1"

  if [[ "$_dir" == *..* ]]; then
    echo "ERROR: SUPERVISOR_DIR must not contain '..'" >&2
    return 1
  fi

  if [[ "$_dir" =~ ^/ ]]; then
    echo "ERROR: SUPERVISOR_DIR must not be an absolute path" >&2
    return 1
  fi

  if [[ ! "$_dir" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    echo "ERROR: SUPERVISOR_DIR must only contain allowed characters (alphanumeric, dot, hyphen, underscore, slash)" >&2
    return 1
  fi

  return 0
}
