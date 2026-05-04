#!/bin/bash
# supervisor-dir-validate.sh - SUPERVISOR_DIR パス検証共有ライブラリ
#
# Issue #1346: spawn-controller.sh の SUPERVISOR_DIR パス検証が未適用
# record-detection-gap.sh (PR #1345) で確立した最厳格パターンを共有化。
#
# Usage:
#   source supervisor-dir-validate.sh
#   validate_supervisor_dir "${SUPERVISOR_DIR:-.supervisor}" || exit 1

# validate_supervisor_dir: SUPERVISOR_DIR の安全性を検証する
#
# 検証内容 (record-detection-gap.sh L59-69 パターン準拠):
#   1. '..' パストラバーサルを含む場合は拒否
#   2. '/' で始まる絶対パスは拒否
#   3. 禁止文字 ($;|\`&()<>) を含む場合は拒否
#
# 引数:
#   $1: 検証対象のパス文字列
# 戻り値:
#   0: 検証通過
#   1: 検証失敗（エラーメッセージを stderr に出力）
validate_supervisor_dir() {
  local _dir="$1"
  local _errmsg="ERROR: SUPERVISOR_DIR must only contain allowed characters (alphanumeric, dot, hyphen, underscore, slash)"

  if [[ "$_dir" == *..* ]]; then
    echo "ERROR: SUPERVISOR_DIR must not contain '..'" >&2
    return 1
  fi

  if [[ "$_dir" =~ ^/ ]]; then
    echo "ERROR: SUPERVISOR_DIR must not be an absolute path (got: ${_dir})" >&2
    return 1
  fi

  # 禁止文字チェック: $ ; | ` & ( ) < > \ (バックスラッシュは printf でリテラル化)
  local _backslash
  printf -v _backslash '\\'
  if [[ "$_dir" == *'$'* ]] || [[ "$_dir" == *';'* ]] || [[ "$_dir" == *'|'* ]] || \
     [[ "$_dir" == *'`'* ]] || [[ "$_dir" == *'&'* ]] || [[ "$_dir" == *'('* ]] || \
     [[ "$_dir" == *')'* ]] || [[ "$_dir" == *'<'* ]] || [[ "$_dir" == *'>'* ]] || \
     [[ "$_dir" == *"${_backslash}"* ]]; then
    echo "$_errmsg" >&2
    return 1
  fi

  return 0
}
