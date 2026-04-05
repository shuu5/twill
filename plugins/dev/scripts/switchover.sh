#!/usr/bin/env bash
# switchover.sh - plugin-dev スイッチオーバー管理
# サブコマンド: check / switch / rollback / retire
set -euo pipefail

PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.claude/plugins}"
# パストラバーサル防止: PLUGIN_DIR の検証
if [[ "$PLUGIN_DIR" == *..* ]]; then
  echo "ERROR: PLUGIN_DIR にパストラバーサルが含まれています: $PLUGIN_DIR" >&2
  exit 1
fi
if [[ "$PLUGIN_DIR" != /* ]]; then
  echo "ERROR: PLUGIN_DIR は絶対パスである必要があります: $PLUGIN_DIR" >&2
  exit 1
fi
PLUGIN_LINK="$PLUGIN_DIR/dev"
BACKUP_LINK="$PLUGIN_DIR/dev.bak"

usage() {
  cat <<EOF
使用方法: $(basename "$0") <subcommand> [options]

サブコマンド:
  check              切替前の事前チェック
  switch --new <dir> symlink 切替（check 実行後）
  rollback           バックアップから旧 symlink 復元
  retire             バックアップ削除 + アーカイブ案内

Options:
  -h, --help         このヘルプを表示
EOF
}

# ── check 内部実装（return ベース。switch からも呼ばれる）──
_run_check() {
  local has_error=false

  # 1. twl validate
  echo "=== twl validate ==="
  local validate_out
  if validate_out=$(twl validate 2>&1); then
    echo "$validate_out"
    echo "✓ validate: OK"
  else
    echo "$validate_out"
    echo "✗ 検証失敗: twl validate"
    has_error=true
  fi

  # 2. twl check
  echo "=== twl check ==="
  local check_out
  if check_out=$(twl check 2>&1); then
    echo "$check_out"
    echo "✓ check: OK"
  else
    echo "$check_out"
    echo "✗ 検証失敗: twl check"
    has_error=true
  fi

  # 3. autopilot セッション検出
  echo "=== autopilot セッション確認 ==="
  if command -v tmux &>/dev/null; then
    local sessions
    if sessions=$(tmux list-sessions 2>/dev/null); then
      while IFS=: read -r sess_name _rest; do
        sess_name=$(echo "$sess_name" | xargs)
        if tmux show-environment -t "$sess_name" DEV_AUTOPILOT_SESSION 2>/dev/null | grep -q "DEV_AUTOPILOT_SESSION=1"; then
          echo "✗ in-flight autopilot セッション検出: $sess_name"
          has_error=true
        fi
      done <<< "$sessions"
    fi
  fi

  # 4. 現在の symlink 状態表示
  echo "=== symlink 状態 ==="
  if [ -L "$PLUGIN_LINK" ]; then
    local target
    target=$(readlink "$PLUGIN_LINK")
    echo "現在の symlink: $PLUGIN_LINK → $target"
  else
    echo "⚠ symlink が見つかりません: $PLUGIN_LINK"
  fi

  # 結果判定
  if [ "$has_error" = true ]; then
    echo ""
    echo "=== 結果: FAIL ==="
    return 1
  fi

  echo ""
  echo "✓ 切替可能: 全チェック pass"
  return 0
}

# ── check サブコマンド ──
cmd_check() {
  _run_check
}

# ── switch サブコマンド ──
cmd_switch() {
  local new_dir=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --new)
        shift
        new_dir="${1:-}"
        ;;
      --force)
        force=true
        ;;
      *)
        echo "ERROR: 不明なオプション: $1" >&2
        return 1
        ;;
    esac
    shift
  done

  # --new 必須
  if [ -z "$new_dir" ]; then
    echo "ERROR: --new <dir> を指定してください" >&2
    return 1
  fi

  # 絶対パスチェック
  if [[ "$new_dir" != /* ]]; then
    echo "ERROR: 絶対パスを指定してください: $new_dir" >&2
    return 1
  fi

  # パストラバーサル拒否
  if [[ "$new_dir" == *..* ]]; then
    echo "ERROR: パストラバーサルは禁止されています: $new_dir" >&2
    return 1
  fi

  # 存在チェック
  if [ ! -d "$new_dir" ]; then
    echo "ERROR: ディレクトリが存在しません: $new_dir" >&2
    return 1
  fi

  # 現在の symlink が存在し、symlink であることを確認
  if [ ! -e "$PLUGIN_LINK" ] && [ ! -L "$PLUGIN_LINK" ]; then
    echo "ERROR: 現在の symlink が存在しません: $PLUGIN_LINK" >&2
    return 1
  fi
  if [ ! -L "$PLUGIN_LINK" ]; then
    echo "ERROR: $PLUGIN_LINK は symlink ではありません" >&2
    return 1
  fi

  # check 実行
  if ! _run_check; then
    echo "ERROR: 事前チェックが失敗しました。切替を中止します。" >&2
    return 1
  fi

  # バックアップ先の確認
  if [ -e "$BACKUP_LINK" ] || [ -L "$BACKUP_LINK" ]; then
    if [ "$force" = true ]; then
      rm -f "$BACKUP_LINK"
    else
      echo ""
      echo "⚠ バックアップが既に存在します: $BACKUP_LINK"
      read -r -p "上書きしますか? (y/n): " answer
      if [ "$answer" != "y" ]; then
        echo "中止しました。"
        return 1
      fi
      rm -f "$BACKUP_LINK"
    fi
  fi

  # バックアップ作成 + symlink 差替え
  if ! mv "$PLUGIN_LINK" "$BACKUP_LINK" 2>/dev/null; then
    echo "ERROR: バックアップ作成に失敗しました" >&2
    return 1
  fi

  if ! ln -s "$new_dir" "$PLUGIN_LINK" 2>/dev/null; then
    # 失敗時はバックアップを復元
    if ! mv "$BACKUP_LINK" "$PLUGIN_LINK" 2>/dev/null; then
      echo "CRITICAL: ロールバック復元も失敗しました。手動で確認してください: $PLUGIN_LINK" >&2
    fi
    echo "ERROR: symlink 作成に失敗しました" >&2
    return 1
  fi

  echo ""
  echo "✓ 切替完了: $PLUGIN_LINK → $new_dir"
  echo "  バックアップ: $BACKUP_LINK"
}

# ── rollback サブコマンド ──
cmd_rollback() {
  # 引数チェック
  if [[ $# -gt 0 ]]; then
    echo "ERROR: 不明なオプション: $1" >&2
    return 1
  fi

  # バックアップ存在チェック
  if [ ! -e "$BACKUP_LINK" ] && [ ! -L "$BACKUP_LINK" ]; then
    echo "ERROR: バックアップが見つかりません: $BACKUP_LINK" >&2
    return 1
  fi

  # バックアップ先の有効性チェック（symlink の場合、ターゲットが存在するか）
  if [ -L "$BACKUP_LINK" ]; then
    local bak_target
    bak_target=$(readlink "$BACKUP_LINK")
    if [ ! -e "$bak_target" ]; then
      echo "ERROR: バックアップ先が無効です（ターゲット不在）: $bak_target" >&2
      return 1
    fi
  fi

  # 現在の dev が通常ディレクトリの場合は拒否
  if [ -e "$PLUGIN_LINK" ] && [ ! -L "$PLUGIN_LINK" ]; then
    echo "ERROR: $PLUGIN_LINK は symlink ではありません。手動で確認してください。" >&2
    return 1
  fi

  # 現在の symlink を削除（存在する場合）
  if [ -L "$PLUGIN_LINK" ]; then
    rm -f "$PLUGIN_LINK"
  fi

  # バックアップから復元
  if ! mv "$BACKUP_LINK" "$PLUGIN_LINK" 2>/dev/null; then
    echo "ERROR: 復元に失敗しました" >&2
    return 1
  fi

  echo "✓ ロールバック完了: $PLUGIN_LINK が復元されました"
}

# ── retire サブコマンド ──
cmd_retire() {
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force=true
        ;;
      *)
        echo "ERROR: 不明なオプション: $1" >&2
        return 1
        ;;
    esac
    shift
  done

  # バックアップ存在チェック
  if [ ! -e "$BACKUP_LINK" ] && [ ! -L "$BACKUP_LINK" ]; then
    echo "ERROR: バックアップが見つかりません: $BACKUP_LINK" >&2
    return 1
  fi

  if [ "$force" = false ]; then
    echo "旧プラグインバックアップを削除します。"
    echo "  対象: $BACKUP_LINK"
    echo ""

    local answer=""
    while true; do
      echo -n "確認: 削除してよろしいですか? (y/n): "
      if ! read -r answer; then
        echo "キャンセルしました。"
        return 0
      fi
      case "$answer" in
        y|Y) break ;;
        n|N)
          echo "キャンセルしました。"
          return 0
          ;;
        "")
          echo "キャンセルしました。"
          return 0
          ;;
        *)
          echo "y または n で回答してください。"
          ;;
      esac
    done
  fi

  # バックアップ削除
  rm -f "$BACKUP_LINK"

  echo ""
  echo "✓ 退役完了: バックアップを削除しました"
  echo ""
  echo "旧リポジトリのアーカイブを推奨します:"
  echo "  gh repo archive claude-plugin-dev --yes"
}

# ── メインルーティング ──
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

subcmd="$1"
shift

case "$subcmd" in
  check)    cmd_check "$@" ;;
  switch)   cmd_switch "$@" ;;
  rollback) cmd_rollback "$@" ;;
  retire)   cmd_retire "$@" ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: 不明なサブコマンド: $subcmd" >&2
    usage
    exit 1
    ;;
esac
