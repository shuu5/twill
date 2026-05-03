#!/usr/bin/env bats
# commit-validate-mcp-shadow-path-isolation.bats
#
# SHADOW_LOG パス隔離検証 (Issue #1286)
#
# AC-1: commit-validate-mcp-shadow.bats 内の SHADOW_LOG が /tmp 固定パスを使用していない
#        （$SANDBOX ベースであること）
# AC-2: bats teardown 後、/tmp/mcp-shadow-commit-validate.log に残留しない
#
# 実装: SHADOW_LOG を setup() 内で "$SANDBOX/mcp-shadow-commit-validate.log" に設定済み。
# 全テストは GREEN で通過する。
#

load '../helpers/common'

BATS_FILE=""

setup() {
  common_setup

  local git_root
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"

  BATS_FILE="${git_root}/plugins/twl/tests/bats/scripts/commit-validate-mcp-shadow.bats"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: SHADOW_LOG が /tmp 固定パスを使用していない（$SANDBOX ベースであること）
#
# WHEN commit-validate-mcp-shadow.bats を grep する
# THEN SHADOW_LOG のデフォルト値が /tmp/... ではなく $SANDBOX/... であること
# RED: 現状 L20 が SHADOW_LOG="/tmp/mcp-shadow-commit-validate.log" のため fail する
# ---------------------------------------------------------------------------

@test "ac1: SHADOW_LOG のグローバル代入が /tmp 固定パスを使用していない" {
  # setup() 内で $SANDBOX ベースに設定されているため /tmp 固定パスが存在しないことを検証
  [ -f "$BATS_FILE" ] || {
    echo "テスト対象ファイルが存在しない: $BATS_FILE" >&2
    false
  }
  local tmp_assignments
  tmp_assignments=$(grep -n 'SHADOW_LOG=.*"/tmp/' "$BATS_FILE" || true)
  if [ -n "$tmp_assignments" ]; then
    echo "SHADOW_LOG が /tmp 固定パスで設定されています（\$SANDBOX ベースに変更が必要）:" >&2
    echo "$tmp_assignments" >&2
    false
  fi
}

@test "ac1: SHADOW_LOG が SANDBOX ベースのパスで設定されている" {
  # setup() 内で SHADOW_LOG="$SANDBOX/mcp-shadow-commit-validate.log" が設定されていることを検証
  [ -f "$BATS_FILE" ] || {
    echo "テスト対象ファイルが存在しない: $BATS_FILE" >&2
    false
  }
  local sandbox_assignments
  sandbox_assignments=$(grep -n 'SHADOW_LOG=.*"\$SANDBOX/' "$BATS_FILE" || true)
  if [ -z "$sandbox_assignments" ]; then
    echo "SHADOW_LOG が \$SANDBOX ベースのパスで設定されていません" >&2
    echo "現在の SHADOW_LOG 設定:" >&2
    grep -n 'SHADOW_LOG=' "$BATS_FILE" >&2 || echo "(SHADOW_LOG 設定なし)" >&2
    false
  fi
}

@test "ac1: SHADOW_LOG のグローバルスコープ代入が setup() 内または setup() 後に限定されている" {
  # setup() 内で SANDBOX を参照することでテスト間分離が保証されていることを検証
  [ -f "$BATS_FILE" ] || {
    echo "テスト対象ファイルが存在しない: $BATS_FILE" >&2
    false
  }
  # グローバルスコープ（関数外）での SHADOW_LOG="/tmp/... 代入を検出
  # awk で関数ブロック外の代入行を抽出する
  local global_tmp_assign
  global_tmp_assign=$(awk '
    /^[[:space:]]*(setup|teardown|@test|function)[[:space:]]*\(/ { in_func=1 }
    /^}/ { in_func=0 }
    !in_func && /SHADOW_LOG=.*\/tmp\// { print NR": "$0 }
  ' "$BATS_FILE" || true)
  if [ -n "$global_tmp_assign" ]; then
    echo "SHADOW_LOG が グローバルスコープ（関数外）で /tmp/... に設定されています:" >&2
    echo "$global_tmp_assign" >&2
    false
  fi
}

# ---------------------------------------------------------------------------
# AC-2: teardown 後、/tmp/mcp-shadow-commit-validate.log が残留しない
#
# WHEN commit-validate-mcp-shadow.bats の teardown を確認する
# THEN SHADOW_LOG が $SANDBOX/ ベースであり common_teardown で自動削除される
# ---------------------------------------------------------------------------

@test "ac2: teardown が /tmp/mcp-shadow-commit-validate.log を明示的に削除するか SANDBOX ベースである" {
  # SHADOW_LOG が $SANDBOX/ ベースのため common_teardown で自動クリーンアップされることを検証
  [ -f "$BATS_FILE" ] || {
    echo "テスト対象ファイルが存在しない: $BATS_FILE" >&2
    false
  }

  # 条件 A: SHADOW_LOG が $SANDBOX/ ベース（common_teardown で自動削除される）
  # grep -c はマッチなしで exit 1 + stdout "0" を返す。|| true で exit code を吸収し値のみ取る
  local has_sandbox_shadow_log
  if grep -q 'SHADOW_LOG=.*"\$SANDBOX/' "$BATS_FILE" 2>/dev/null; then
    has_sandbox_shadow_log=1
  else
    has_sandbox_shadow_log=0
  fi

  # 条件 B: teardown() 内で rm -f /tmp/mcp-shadow-commit-validate.log が存在する
  local has_explicit_cleanup
  has_explicit_cleanup=$(awk '
    /teardown[[:space:]]*\(\)/ { in_teardown=1 }
    in_teardown && /rm.*\/tmp\/mcp-shadow-commit-validate\.log/ { found=1 }
    in_teardown && /^}/ { in_teardown=0 }
    END { print (found ? "1" : "0") }
  ' "$BATS_FILE")

  if [ "$has_sandbox_shadow_log" -eq 0 ] && [ "$has_explicit_cleanup" -eq 0 ]; then
    echo "/tmp/mcp-shadow-commit-validate.log が teardown でクリーンアップされません:" >&2
    echo "  - SHADOW_LOG が \$SANDBOX/ ベースでない" >&2
    echo "  - teardown() 内に rm -f /tmp/mcp-shadow-commit-validate.log がない" >&2
    echo "いずれかの対策が必要です（推奨: SHADOW_LOG を \$SANDBOX/ ベースに変更）" >&2
    false
  fi
}

@test "ac2: /tmp/mcp-shadow-commit-validate.log が現在のテスト実行後に残留しない（静的検証）" {
  # SHADOW_LOG が /tmp/... を使用していないことを静的に検証する（副作用なし）
  [ -f "$BATS_FILE" ] || {
    echo "テスト対象ファイルが存在しない: $BATS_FILE" >&2
    false
  }

  local uses_tmp_path
  uses_tmp_path=$(grep -c 'SHADOW_LOG=.*/tmp/' "$BATS_FILE" 2>/dev/null || echo "0")

  if [ "$uses_tmp_path" -gt 0 ]; then
    echo "SHADOW_LOG が /tmp/... を使用しています。並列テスト時に残留リスクがあります。" >&2
    echo "SHADOW_LOG を \"\$SANDBOX/mcp-shadow-commit-validate.log\" に変更してください。" >&2
    false
  fi
}
