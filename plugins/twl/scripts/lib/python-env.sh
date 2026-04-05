#!/usr/bin/env bash
# python-env.sh - Python モジュールパスを設定する共通ヘルパー
# 使用方法: source "${SCRIPT_DIR}/lib/python-env.sh"
# 効果: PYTHONPATH に cli/twl/src を追加し、twl.autopilot.* モジュールを使用可能にする

_PE_GIT_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$_PE_GIT_ROOT" ]]; then
  _PE_TWL_SRC="${_PE_GIT_ROOT}/cli/twl/src"
  export PYTHONPATH="${_PE_TWL_SRC}${PYTHONPATH:+:${PYTHONPATH}}"
fi
unset _PE_GIT_ROOT _PE_TWL_SRC
