#!/usr/bin/env bash
# deltaspec-helpers.sh - DeltaSpec 共通ヘルパー関数
#
# chain-runner.sh と autopilot-orchestrator.sh の両方から source される共有ライブラリ。
# DRY 違反解消のため Issue #460 で導入。

# config.yaml を持つ deltaspec root を返す（walk-down fallback 付き）
# 引数: $1 = git/project root（省略時は resolve_project_root）
# maxdepth=5: Python の max_depth=3 と等価（config.yaml は deltaspec/ 配下のため +2）
resolve_deltaspec_root() {
  local root="${1:-$(resolve_project_root)}"
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
