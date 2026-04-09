#!/usr/bin/env bash
# python-env.sh - Python モジュールパスを設定する共通ヘルパー
# 使用方法: source "${SCRIPT_DIR}/lib/python-env.sh"
# 効果: PYTHONPATH に cli/twl/src を追加し、twl.autopilot.* モジュールを使用可能にする
#
# フォールバックチェーン（Issue #227）:
#   Priority 1: 既存 PYTHONPATH に twl パスが含まれていれば何もしない
#   Priority 2: git rev-parse --show-toplevel からの解決
#   Priority 3: BASH_SOURCE[0] からの相対パス計算（git 不要）
#   Priority 4: ハードコードパスのフォールバック（警告付き）

# Priority 1: 既に PYTHONPATH に twl/src が含まれていれば何もしない
if [[ "${PYTHONPATH:-}" == *"/cli/twl/src"* ]]; then
  return 0 2>/dev/null || exit 0
fi

_PE_TWL_SRC=""

# Priority 2: git rev-parse（従来方式）
_PE_GIT_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$_PE_GIT_ROOT" && -d "${_PE_GIT_ROOT}/cli/twl/src/twl" ]]; then
  _PE_TWL_SRC="${_PE_GIT_ROOT}/cli/twl/src"
fi

# Priority 3: BASH_SOURCE からの相対パス計算（git 不要）
# python-env.sh は plugins/twl/scripts/lib/ にあるので ../../../../cli/twl/src で到達
if [[ -z "$_PE_TWL_SRC" ]]; then
  _PE_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _PE_RELATIVE="${_PE_SELF_DIR}/../../../../cli/twl/src"
  if [[ -d "$_PE_RELATIVE/twl" ]]; then
    _PE_TWL_SRC="$(cd "$_PE_RELATIVE" && pwd)"
  fi
  unset _PE_SELF_DIR _PE_RELATIVE
fi

# Priority 4: ハードコードフォールバック（bare repo worktree 対応）
if [[ -z "$_PE_TWL_SRC" ]]; then
  for _PE_CANDIDATE in \
    "${HOME}/projects/local-projects/twill/main/cli/twl/src" \
    "${HOME}/projects/local-projects/twill/cli/twl/src"; do
    if [[ -d "${_PE_CANDIDATE}/twl" ]]; then
      _PE_TWL_SRC="$_PE_CANDIDATE"
      echo "[python-env.sh] WARN: git/相対パス解決失敗。ハードコードパス使用: ${_PE_TWL_SRC}" >&2
      break
    fi
  done
  unset _PE_CANDIDATE
fi

if [[ -n "$_PE_TWL_SRC" ]]; then
  export PYTHONPATH="${_PE_TWL_SRC}${PYTHONPATH:+:${PYTHONPATH}}"
else
  echo "[python-env.sh] ERROR: cli/twl/src が見つかりません。python3 -m twl.* は失敗します。" >&2
fi
unset _PE_GIT_ROOT _PE_TWL_SRC
