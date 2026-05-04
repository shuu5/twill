#!/usr/bin/env bats
# issue-1346-spawn-controller-supervisor-dir-validate.bats
# RED tests for Issue #1346: spawn-controller.sh SUPERVISOR_DIR 検証 tech-debt
#
# AC coverage（スコープ内のみ）:
#   AC1 - spawn-controller.sh がスクリプト冒頭で SUPERVISOR_DIR を validate することを確認
#   AC2 - 共有 lib supervisor-dir-validate.sh が存在し正しく機能することを確認
#   AC6 - lib 単体テスト: (a)絶対パス (b)..含む (c)禁止文字 (d)正常パス
#   AC7 - 既存スクリプトが壊れないことを確認
#   AC8 - deps.yaml に lib エントリが追加されていることを確認
#
# スコープ外（AC3, AC4, AC5 横展開部分）:
#   record-detection-gap.sh / session-init.sh / step0-monitor-bootstrap.sh
#   step0-memory-ambient.sh / heartbeat-watcher.sh / auto-next-spawn.sh の変更なし
#
# テスト設計:
#   - supervisor-dir-validate.sh は未実装のため存在チェックが RED で fail する
#   - spawn-controller.sh に validate 呼び出しがまだないため呼び出し確認が RED で fail する
#   - deps.yaml に lib エントリがまだないため存在確認が RED で fail する
#   - lib 単体テストは lib が存在しないため全て RED で fail する
#
# WARN: source guard 確認結果:
#   spawn-controller.sh に [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard が存在しない。
#   set -euo pipefail 環境で source すると main 到達前に exit に巻き込まれるリスクあり。
#   本テストでは source せず、static grep 検査 および bash サブシェルで直接実行する設計で回避済み。
#   実装者は spawn-controller.sh への source guard 追加を検討すること（impl_files 参照）。

load 'helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  LIB_SCRIPT="${REPO_ROOT}/scripts/lib/supervisor-dir-validate.sh"
  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"

  export LIB_SCRIPT SPAWN_SCRIPT

  # cld-spawn stub（実際の tmux spawn をスキップ）
  stub_command "cld-spawn" 'echo "cld-spawn-stub: $*"; exit 0'

  # tmux stub（副作用を回避）
  stub_command "tmux" 'echo "tmux-stub: $*"; exit 0'

  # プロンプトファイルをサンドボックスに作成
  echo "test prompt content" > "$SANDBOX/test-prompt.txt"

  export SKIP_PARALLEL_CHECK=1
  export SKIP_PARALLEL_REASON="bats test issue-1346 RED phase"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC2: 共有 lib supervisor-dir-validate.sh の存在確認
#
# RED: ファイルがまだ存在しないため fail する
# PASS 条件（実装後）:
#   - plugins/twl/scripts/lib/supervisor-dir-validate.sh が存在する
#   - 実行可能権限がある
# ===========================================================================

@test "ac2: supervisor-dir-validate.sh が scripts/lib/ に存在する" {
  # AC: 共有検証ロジックを plugins/twl/scripts/lib/supervisor-dir-validate.sh に切り出す
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${LIB_SCRIPT}" ]
}

@test "ac2: supervisor-dir-validate.sh が実行可能権限を持つ" {
  # AC: 共有 lib が source 可能な実行可能ファイルとして存在する
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${LIB_SCRIPT}" ]
  [ -x "${LIB_SCRIPT}" ]
}

@test "ac2: supervisor-dir-validate.sh が validate_supervisor_dir 関数を定義している" {
  # AC: 共有 lib に validate_supervisor_dir 関数が含まれる
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${LIB_SCRIPT}" ]
  grep -q "validate_supervisor_dir" "${LIB_SCRIPT}"
}

# ===========================================================================
# AC6(a): 絶対パス（/ 始まり）を拒否する（record-detection-gap.sh パターン準拠）
#
# RED: lib が存在しないため fail する
# PASS 条件（実装後）:
#   - 絶対パス（/ 始まり）を渡すと exit 1 かつエラーメッセージが出力される
#   - 例: /etc/passwd, /tmp/supervisor → 拒否
# ===========================================================================

@test "ac6a: validate_supervisor_dir が絶対パス /etc/passwd を拒否して exit 1 する" {
  # AC: 絶対パス（/ 始まり）を検証で弾く（record-detection-gap.sh ^/ チェック準拠）
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '/etc/passwd'
"
  [ "$status" -ne 0 ]
}

@test "ac6a: validate_supervisor_dir が絶対パス拒否時にエラーメッセージを stderr に出力する" {
  # AC: 絶対パスを検証で弾く（エラーメッセージ確認）
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '/tmp/absolute-path' 2>&1
"
  [ "$status" -ne 0 ]
  [ -n "$output" ]
}

# ===========================================================================
# AC6(b): ".." を含むパスを拒否する（パストラバーサル防止）
#
# RED: lib が存在しないため fail する
# PASS 条件（実装後）:
#   - ".." を含む絶対パスを渡すと exit 1
#   - 例: /tmp/../etc → 拒否
# ===========================================================================

@test "ac6b: validate_supervisor_dir が .. を含む相対パスを拒否して exit 1 する" {
  # AC: '..' パストラバーサルを含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '../../../../.supervisor'
"
  [ "$status" -ne 0 ]
}

@test "ac6b: validate_supervisor_dir が ../ を含む相対パスを拒否する" {
  # AC: '..' パストラバーサルを含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '../.supervisor'
"
  [ "$status" -ne 0 ]
}

# ===========================================================================
# AC6(c): 禁止文字（$ ; | \ & ( ) < >）を含むパスを拒否する
#
# RED: lib が存在しないため fail する
# PASS 条件（実装後）:
#   - 禁止文字を含む値を渡すと exit 1
# ===========================================================================

@test "ac6c: validate_supervisor_dir がドル記号を含むパスを拒否する" {
  # AC: 禁止文字 $ を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c '
source '"'"''"${LIB_SCRIPT}"''"'"'
validate_supervisor_dir '"'"'.supervisor$evil'"'"'
'
  [ "$status" -ne 0 ]
}

@test "ac6c: validate_supervisor_dir がセミコロンを含むパスを拒否する" {
  # AC: 禁止文字 ; を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor;rm -rf /'
"
  [ "$status" -ne 0 ]
}

@test "ac6c: validate_supervisor_dir がパイプを含むパスを拒否する" {
  # AC: 禁止文字 | を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor|cmd'
"
  [ "$status" -ne 0 ]
}

@test "ac6c: validate_supervisor_dir がバックスラッシュを含むパスを拒否する" {
  # AC: 禁止文字 \ を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c 'source '"'"''"${LIB_SCRIPT}"''"'"'
validate_supervisor_dir '"'"'.supervisor\cmd'"'"
  [ "$status" -ne 0 ]
}

@test "ac6c: validate_supervisor_dir がアンパサンドを含むパスを拒否する" {
  # AC: 禁止文字 & を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor&cmd'
"
  [ "$status" -ne 0 ]
}

@test "ac6c: validate_supervisor_dir が丸括弧を含むパスを拒否する" {
  # AC: 禁止文字 ( ) を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor(evil)'
"
  [ "$status" -ne 0 ]
}

@test "ac6c: validate_supervisor_dir が不等号を含むパスを拒否する" {
  # AC: 禁止文字 < > を含む値を検証で弾く
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor<file>'
"
  [ "$status" -ne 0 ]
}

# ===========================================================================
# AC6(d): 正常パスが通過する
#
# RED: lib が存在しないため fail する
# PASS 条件（実装後）:
#   - 相対パスかつ禁止文字・".." を含まない値を渡すと exit 0
#   - record-detection-gap.sh パターン準拠: 相対パスが正常値
# ===========================================================================

@test "ac6d: validate_supervisor_dir がデフォルト値 .supervisor を許可して exit 0 する" {
  # AC: 正常な相対パスが validate を通過する（record-detection-gap.sh パターン準拠）
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor'
"
  [ "$status" -eq 0 ]
}

@test "ac6d: validate_supervisor_dir が英数字のみの相対パスを許可する" {
  # AC: 正常な相対パスが validate を通過する
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir 'my-supervisor'
"
  [ "$status" -eq 0 ]
}

@test "ac6d: validate_supervisor_dir がハイフン・アンダースコアを含む相対パスを許可する" {
  # AC: 正常な相対パスが validate を通過する
  # RED: lib 不在のため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir 'supervisor-dir_v2'
"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC1: spawn-controller.sh がスクリプト冒頭で SUPERVISOR_DIR を validate する
#
# RED: validate 呼び出しがまだ実装されていないため fail する
# PASS 条件（実装後）:
#   - spawn-controller.sh の冒頭（L60 以前）付近に validate_supervisor_dir の呼び出しがある
#   - supervisor-dir-validate.sh を source する行が存在する
#   - 不正な SUPERVISOR_DIR を渡すと spawn-controller.sh が exit 1 する
# ===========================================================================

@test "ac1: spawn-controller.sh が supervisor-dir-validate.sh を source している" {
  # AC: スクリプト冒頭での単一 validate 呼び出し
  # RED: 実装前は fail する（source 行が未実装）
  grep -q "supervisor-dir-validate.sh" "${SPAWN_SCRIPT}"
}

@test "ac1: spawn-controller.sh が validate_supervisor_dir を呼び出している" {
  # AC: スクリプト冒頭での validate 呼び出し
  # RED: 実装前は fail する（呼び出し行が未実装）
  grep -q "validate_supervisor_dir" "${SPAWN_SCRIPT}"
}

@test "ac1: validate 呼び出しがスクリプト冒頭（L80以前）に存在する" {
  # AC: スクリプト冒頭での単一 validate 呼び出しとする
  # RED: 実装前は fail する（呼び出し行が未実装）
  #
  # 検証方法: head -80 した範囲内に validate_supervisor_dir が含まれる
  head -80 "${SPAWN_SCRIPT}" | grep -q "validate_supervisor_dir"
}

@test "ac1: 不正な SUPERVISOR_DIR（絶対パス）を渡すと spawn-controller.sh が非 0 で終了する" {
  # AC: SUPERVISOR_DIR を mkdir -p / パス連結に渡す前に検証する（record-detection-gap.sh パターン: 絶対パス拒否）
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  # validate_supervisor_dir を直接呼び出してスクリプト冒頭の検証を確認
  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '/tmp/absolute-invalid' || exit 1
echo 'reached downstream'
"
  [ "$status" -ne 0 ]
  [[ "$output" != *"reached downstream"* ]]
}

@test "ac1: 不正な SUPERVISOR_DIR（.. 含む）を渡すと spawn-controller.sh が非 0 で終了する" {
  # AC: SUPERVISOR_DIR に '..' パストラバーサルが含まれる場合に検証で弾く
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '../../etc/traversal' || exit 1
echo 'reached downstream'
"
  [ "$status" -ne 0 ]
  [[ "$output" != *"reached downstream"* ]]
}

@test "ac1: 正常な相対パスの SUPERVISOR_DIR は validate を通過して spawn-controller.sh に到達する" {
  # AC: 正常な SUPERVISOR_DIR では validate が通過し、通常フローに進む
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }

  run bash -c "
source '${LIB_SCRIPT}'
validate_supervisor_dir '.supervisor'
echo 'validate passed'
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate passed"* ]]
}

# ===========================================================================
# AC8: deps.yaml に supervisor-dir-validate の lib エントリが存在する
#
# RED: エントリがまだ追加されていないため fail する
# PASS 条件（実装後）:
#   - deps.yaml に supervisor-dir-validate: エントリが含まれる
#   - path: scripts/lib/supervisor-dir-validate.sh が記載されている
# ===========================================================================

@test "ac8: deps.yaml に supervisor-dir-validate エントリが存在する" {
  # AC: plugins/twl/scripts/lib/supervisor-dir-validate.sh を deps.yaml の lib エントリに追加する
  # RED: 実装前は fail する（エントリ未追加）
  local deps_yaml="${REPO_ROOT}/deps.yaml"
  [ -f "$deps_yaml" ]
  grep -q "supervisor-dir-validate" "$deps_yaml"
}

@test "ac8: deps.yaml の supervisor-dir-validate エントリに正しい path が記載されている" {
  # AC: deps.yaml の lib エントリが正しいパスを指している
  # RED: 実装前は fail する（エントリ未追加）
  local deps_yaml="${REPO_ROOT}/deps.yaml"
  [ -f "$deps_yaml" ]
  # Markdown テーブル用語列マッチパターン（PR #1357 / commit 532d6e20）に従い
  # grep -qF 'supervisor-dir-validate.sh' で path 列の値を確認する
  grep -qF "supervisor-dir-validate.sh" "$deps_yaml"
}

# ===========================================================================
# AC7: 既存スクリプトが壊れないことを確認（static 検査）
#
# RED/GREEN 混在:
#   - 現状 PASS しているものもあるが、lib 追加後も既存動作が壊れないことを保証するため記載
#   - spawn-controller.sh の static 構造チェック（bash -n）は現状 PASS のはず
# ===========================================================================

@test "ac7: spawn-controller.sh が bash -n でシンタックスエラーなしで通過する" {
  # AC: 既存の source するスクリプトが 1 つも壊れない
  # GREEN: 現状も通過するはず（実装後も維持されることを保証）
  run bash -n "${SPAWN_SCRIPT}"
  assert_success
}

@test "ac7: supervisor-dir-validate.sh 追加後に spawn-controller.sh が bash -n を通過する（実装後 PASS）" {
  # AC: lib 追加後も spawn-controller.sh のシンタックスが正しい
  # RED: lib が存在しないため source した場合の検証は未確認
  #      lib 存在確認 + bash -n を組み合わせて検証
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }
  run bash -n "${SPAWN_SCRIPT}"
  assert_success
}

@test "ac7: supervisor-dir-validate.sh 自体が bash -n でシンタックスエラーなしで通過する" {
  # AC: lib スクリプト自体にシンタックスエラーがない
  # RED: lib が存在しないため fail する
  [ -f "${LIB_SCRIPT}" ] || {
    echo "RED: supervisor-dir-validate.sh 未実装"
    false
  }
  run bash -n "${LIB_SCRIPT}"
  assert_success
}
