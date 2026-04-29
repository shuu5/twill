#!/usr/bin/env bats
# su-postcompact-path-validation.bats
#
# Issue #1073: tech-debt(security): su-precompact.sh / su-postcompact.sh に
#              SUPERVISOR_DIR のパス境界チェックを追加する
#
# AC2: plugins/twl/scripts/su-postcompact.sh で同様の SUPERVISOR_DIR 境界チェックを
#      Python ブロック内に実装する（json.dump を含む write 操作のため必須）。
#      CLAUDE_PROJECT_ROOT はシェル環境から継承されるため
#      （既存の env var injection パターンと同様）、
#      os.environ.get("CLAUDE_PROJECT_ROOT", os.getcwd()) で参照する
# AC3: シェル層の前方一致チェック追加（実行順序: SUPERVISOR_DIR デフォルト設定の直後・
#      [ -d "$SUPERVISOR_DIR" ] || exit 0 の前に配置）:
#      realpath -m "$SUPERVISOR_DIR" の結果が realpath "$CLAUDE_PROJECT_ROOT" (fallback pwd) で
#      始まることを case 文で検証。境界外時 stderr に
#      "SUPERVISOR_DIR outside project root: <resolved-path>" を出力して exit 1
# AC4: 既存挙動の保持: SUPERVISOR_DIR 未指定時のデフォルト .supervisor 使用継続、
#      .supervisor ディレクトリ不在時の [ -d "$SUPERVISOR_DIR" ] || exit 0
#      graceful degradation 維持（AC3 のパス検証通過後に実行）
#
# 全 AC2/AC3 テストは現在の実装では FAIL（RED）状態であること

load '../helpers/common'

setup() {
  common_setup
  export CLAUDE_PROJECT_ROOT="$SANDBOX"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC2: Python ブロック内の pathlib.Path.is_relative_to() 境界チェック
#      （json.dump を含む write 操作のため必須）
#
# RED: 現在の su-postcompact.sh に Python 層のパス境界チェックが存在しないため fail する
# ===========================================================================

@test "ac2: SUPERVISOR_DIR が絶対パスで project root 外の場合 exit 1 する（Python layer）" {
  # RED: 現在の実装には Python 層のパス境界チェックが存在しないため fail する
  # PASS 条件（実装後）: project root 外の絶対パスで exit 1 + stderr 出力
  local evil_dir
  evil_dir="$(mktemp -d)"

  run env SUPERVISOR_DIR="$evil_dir" CLAUDE_PROJECT_ROOT="$SANDBOX" \
    bash "$SANDBOX/scripts/su-postcompact.sh"

  assert_failure
  assert_output --partial "SUPERVISOR_DIR outside project root"

  rm -rf "$evil_dir"
}

@test "ac2: SUPERVISOR_DIR=/etc で exit 1 する（Python layer 絶対パス traversal）" {
  # RED: 現在の実装には Python 層のパス境界チェックが存在しないため fail する
  # PASS 条件（実装後）: /etc 相当の絶対パスで exit 1 + stderr 出力
  run env SUPERVISOR_DIR="/etc" CLAUDE_PROJECT_ROOT="$SANDBOX" \
    bash "$SANDBOX/scripts/su-postcompact.sh"

  assert_failure
  assert_output --partial "SUPERVISOR_DIR outside project root"
}

@test "ac2: su-postcompact.sh の Python ブロックに Path.is_relative_to() が存在する（static grep）" {
  # RED: 現在の実装に is_relative_to が存在しないため fail する
  # PASS 条件（実装後）: Python ブロック内に is_relative_to() 呼び出しが存在する
  run grep -E 'is_relative_to' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh の Python ブロックに is_relative_to() が存在しない"
    return 1
  }
}

@test "ac2: su-postcompact.sh の Python ブロックに pathlib.Path.resolve() が存在する（static grep）" {
  # RED: 現在の実装に .resolve() によるパス正規化が存在しないため fail する
  # PASS 条件（実装後）: Python ブロック内に .resolve() 呼び出しが存在する
  run grep -E '\.resolve\(\)' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh の Python ブロックに .resolve() によるパス正規化が存在しない"
    return 1
  }
}

@test "ac2: su-postcompact.sh の Python ブロックに sys.exit(1) が存在する（static grep）" {
  # RED: 現在の実装に境界外時の sys.exit(1) が存在しないため fail する
  # PASS 条件（実装後）: Python ブロック内に sys.exit(1) が存在する
  run grep -E 'sys\.exit\(1\)' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh の Python ブロックに sys.exit(1) が存在しない"
    return 1
  }
}

@test "ac2: su-postcompact.sh の Python ブロックが os.environ.get で CLAUDE_PROJECT_ROOT を参照する（static grep）" {
  # RED: 現在の実装に os.environ.get("CLAUDE_PROJECT_ROOT", ...) が存在しないため fail する
  # PASS 条件（実装後）: os.environ.get("CLAUDE_PROJECT_ROOT", ...) パターンが存在する
  run grep -E 'os\.environ\.get.*CLAUDE_PROJECT_ROOT' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh の Python ブロックに os.environ.get('CLAUDE_PROJECT_ROOT', ...) が存在しない"
    return 1
  }
}

# ===========================================================================
# AC3: シェル層の前方一致チェック（realpath + case 文）
#
# RED: 現在の su-postcompact.sh にシェル層の境界チェックが存在しないため fail する
# ===========================================================================

@test "ac3: SUPERVISOR_DIR=../../../etc （相対パス traversal）で exit 1 する（shell layer）" {
  # RED: 現在の実装にシェル層のパス境界チェックが存在しないため fail する
  # PASS 条件（実装後）: CWD=SANDBOX 状態で ../../../etc が project root 外として exit 1
  run bash -c "cd '$SANDBOX' && env SUPERVISOR_DIR='../../../etc' CLAUDE_PROJECT_ROOT='$SANDBOX' bash '$SANDBOX/scripts/su-postcompact.sh'"

  assert_failure
  assert_output --partial "SUPERVISOR_DIR outside project root"
}

@test "ac3: SUPERVISOR_DIR 境界外時に stderr に解決済みパスが含まれる（shell layer）" {
  # RED: 現在の実装にシェル層の stderr 出力が存在しないため fail する
  # PASS 条件（実装後）: stderr に "SUPERVISOR_DIR outside project root: <resolved-path>" が含まれる
  local evil_dir
  evil_dir="$(mktemp -d)"

  run env SUPERVISOR_DIR="$evil_dir" CLAUDE_PROJECT_ROOT="$SANDBOX" \
    bash "$SANDBOX/scripts/su-postcompact.sh"

  assert_failure
  assert_output --partial "SUPERVISOR_DIR outside project root: $evil_dir"

  rm -rf "$evil_dir"
}

@test "ac3: su-postcompact.sh に realpath -m コマンドが存在する（static grep）" {
  # RED: 現在の実装に realpath -m によるパス正規化が存在しないため fail する
  # PASS 条件（実装後）: シェル層に realpath -m 呼び出しが存在する
  run grep -E 'realpath\s+-m' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh に realpath -m によるパス正規化が存在しない"
    return 1
  }
}

@test "ac3: su-postcompact.sh に case 文でのパス前方一致チェックが存在する（static grep）" {
  # RED: 現在の実装に case 文での前方一致チェックが存在しないため fail する
  # PASS 条件（実装後）: シェル層に case 文の境界チェックが存在する
  run grep -E 'case\s+' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh に case 文での前方一致チェックが存在しない"
    return 1
  }
}

@test "ac3: シェル層チェックが SUPERVISOR_DIR デフォルト設定の直後に配置されている（static grep 順序確認）" {
  # RED: 現在の実装に境界チェックが存在しないため fail する
  # PASS 条件（実装後）: SUPERVISOR_DIR:=.supervisor の行より後、[ -d "$SUPERVISOR_DIR" ] の行より前に
  #      realpath -m 呼び出しが存在する
  local script="$REPO_ROOT/scripts/su-postcompact.sh"
  local line_default line_check line_dir_exist
  line_default=$(grep -n 'SUPERVISOR_DIR.*:-.*supervisor' "$script" | head -1 | cut -d: -f1)
  line_check=$(grep -n 'realpath\s*-m' "$script" | head -1 | cut -d: -f1)
  line_dir_exist=$(grep -n '\[\s*-d.*SUPERVISOR_DIR.*\]\s*||' "$script" | head -1 | cut -d: -f1)

  [[ -n "$line_check" ]] || {
    echo "FAIL: su-postcompact.sh に realpath -m 境界チェックが存在しない"
    return 1
  }
  [[ "$line_default" -lt "$line_check" ]] || {
    echo "FAIL: realpath -m チェック (line $line_check) が SUPERVISOR_DIR デフォルト設定 (line $line_default) より前に存在する"
    return 1
  }
  [[ "$line_check" -lt "$line_dir_exist" ]] || {
    echo "FAIL: realpath -m チェック (line $line_check) が [ -d SUPERVISOR_DIR ] (line $line_dir_exist) より後に存在する"
    return 1
  }
}

# ===========================================================================
# AC4: 既存挙動の保持
#
# SUPERVISOR_DIR 未指定時のデフォルト .supervisor 使用継続
# .supervisor ディレクトリ不在時の graceful degradation 維持
# ===========================================================================

@test "ac4: SUPERVISOR_DIR 未指定時に .supervisor が存在しなければ exit 0（graceful degradation）" {
  # PASS 条件: .supervisor なしで exit 0（既存動作）
  # AC3 のパス検証通過後に [ -d "$SUPERVISOR_DIR" ] || exit 0 が実行される
  run env CLAUDE_PROJECT_ROOT="$SANDBOX" \
    bash "$SANDBOX/scripts/su-postcompact.sh"

  assert_success
}

@test "ac4: SUPERVISOR_DIR をプロジェクトルート内の正常パスに設定した場合に exit 0（従来挙動維持）" {
  # PASS 条件: project root 内の存在しない supervisor dir でも exit 0（graceful degradation）
  local safe_dir="$SANDBOX/.supervisor"
  # ディレクトリを作成しない → [ -d "$SUPERVISOR_DIR" ] || exit 0 で正常終了するはず

  run env SUPERVISOR_DIR="$safe_dir" CLAUDE_PROJECT_ROOT="$SANDBOX" \
    bash "$SANDBOX/scripts/su-postcompact.sh"

  assert_success
}

@test "ac4: SUPERVISOR_DIR 未指定時のデフォルト値が .supervisor である（static grep）" {
  # PASS 条件（実装前後ともに）: SUPERVISOR_DIR のデフォルト値として .supervisor が設定されている
  run grep -E 'SUPERVISOR_DIR.*:-.*\.supervisor' "$REPO_ROOT/scripts/su-postcompact.sh"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: su-postcompact.sh の SUPERVISOR_DIR デフォルト値が .supervisor でない"
    return 1
  }
}

@test "ac4: SUPERVISOR_DIR をプロジェクトルート内の存在するディレクトリに設定した場合に正常動作する" {
  # PASS 条件: project root 内の有効なディレクトリを指定した場合、
  #            exit 0 かつ session.json 更新が試みられる（エラーなし）
  local safe_supervisor="$SANDBOX/.supervisor"
  mkdir -p "$safe_supervisor"

  run env SUPERVISOR_DIR="$safe_supervisor" CLAUDE_PROJECT_ROOT="$SANDBOX" \
    bash "$SANDBOX/scripts/su-postcompact.sh"

  assert_success
}
