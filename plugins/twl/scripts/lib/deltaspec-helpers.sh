#!/usr/bin/env bash
# deltaspec-helpers.sh - DeltaSpec 共通ヘルパー関数
#
# chain-runner.sh と autopilot-orchestrator.sh の両方から source される共有ライブラリ。
# DRY 違反解消のため Issue #460 で導入。

# git/project root を返す（git rev-parse 失敗時は pwd）
# 注: chain-runner.sh にも同名関数が定義されているが、本ライブラリを単独 source した
# 場合（autopilot-orchestrator.sh 等）のための自己完結な実装として保持する。
_deltaspec_helpers_resolve_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# config.yaml を持つ deltaspec root を返す（walk-down fallback 付き）
# 引数: $1 = git/project root（省略時は git rev-parse --show-toplevel）
# maxdepth=5: Python の max_depth=3 と等価（config.yaml は deltaspec/ 配下のため +2）
resolve_deltaspec_root() {
  local root="${1:-$(_deltaspec_helpers_resolve_project_root)}"
  # 空文字ガード: root が空のときは失敗として終了
  [[ -z "$root" ]] && return 1
  if [[ -f "$root/deltaspec/config.yaml" ]]; then
    echo "$root"
    return 0
  fi
  # walk-down fallback: repo 内で deltaspec/config.yaml を探索（maxdepth=5 は Python max_depth=3 と等価）
  local found_config
  found_config="$(find "$root" -maxdepth 5 -name config.yaml -path '*/deltaspec/*' \
    -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' \
    2>/dev/null | head -1)"
  if [[ -n "$found_config" ]]; then
    dirname "$(dirname "$found_config")"
    return 0
  fi
  # 見つからない場合は root を返す（呼び出し側で判定）
  echo "$root"
  return 1
}
