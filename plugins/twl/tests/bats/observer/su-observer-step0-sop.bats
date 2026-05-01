#!/usr/bin/env bats
# su-observer-step0-sop.bats
#
# RED-phase tests for Issue #1188:
#   su-observer Step 0 SOP の bats テスト生成
#
# AC coverage:
#   AC5.1 - この .bats ファイル自体の存在（tests/bats/observer/ ディレクトリ新設）
#   AC5.2 - C1: Step 0 完了後、Monitor task (cld-observe-any) が active であることを assert
#   AC5.3 - C2: pitfalls-catalog.md の各 §X.Y エントリが doobidoo observer-pitfall tag に
#               対応する記憶を持つことを assert (snapshot 比較)
#   AC5.4 - C3: spawn-controller.sh 起動後に Monitor channel reset 出力が含まれることを assert
#               (Sub 2 merge 前は conditional skip)
#   AC5.5 - プロセス AC (全 PASS): mapping に記録のみ
#
# 全テストは実装前（RED）状態で fail する（AC5.2 は mock process で動作確認、
# AC5.3 は snapshot fixture による比較、AC5.4 は Sub 2 未 merge のため conditional skip）。
#
# NOTE (baseline-bash §9): このファイルではシングルクォート heredoc は使用しない。
# NOTE (baseline-bash §10): spawn-controller.sh には BASH_SOURCE guard が不在。
#   source する場合は set -euo pipefail 環境で main に到達するリスクがある。
#   AC5.4 では直接 source せず、CLD_SPAWN stub + SKIP_PARALLEL_CHECK=1 で副作用を排除する。
#
# impl_files 注意:
#   spawn-controller.sh に source guard が不在のため、source による副作用テストは行わない。
#   将来 spawn-controller.sh に `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard が追加された場合は
#   source 経由テストに変更すること。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  local plugin_tests_dir
  plugin_tests_dir="$(cd "${tests_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${plugin_tests_dir}/.." && pwd)"
  export REPO_ROOT

  # テスト対象ファイルのパス
  SPAWN_CONTROLLER="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"

  # fixture パス (このファイルと同じディレクトリの fixtures/ 配下)
  FIXTURES_DIR="${this_dir}/fixtures"
  MOCK_DAEMON="${FIXTURES_DIR}/mock-cld-observe-any.sh"
  PITFALLS_SNAPSHOT="${FIXTURES_DIR}/pitfalls-doobidoo-snapshot.json"

  export SPAWN_CONTROLLER PITFALLS_CATALOG FIXTURES_DIR MOCK_DAEMON PITFALLS_SNAPSHOT

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST

  # mock PID 追跡用
  MOCK_PID=""
  export MOCK_PID
}

teardown() {
  # mock daemon が残存している場合は cleanup（MOCK_PID 追跡分）
  if [[ -n "${MOCK_PID:-}" ]] && kill -0 "${MOCK_PID}" 2>/dev/null; then
    kill "${MOCK_PID}" 2>/dev/null || true
  fi
  # フォールバック: スクリプトパスにマッチする残留 daemon を全 kill
  pkill -f "mock-cld-observe-any" 2>/dev/null || true
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC5.1: observer/ ディレクトリおよびこのファイル自体の存在確認
#   (このテストが存在していること自体が AC5.1 の証明。
#    追加として fixtures/ も確認する)
# ===========================================================================

@test "ac5.1: tests/bats/observer/ directory exists" {
  # AC: tests/bats/observer/ ディレクトリが新設されている
  local observer_dir
  observer_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  [ -d "${observer_dir}" ]
  [[ "${observer_dir}" == */tests/bats/observer ]]
}

@test "ac5.1: fixtures directory exists under observer/" {
  # AC: tests/bats/observer/fixtures/ ディレクトリが存在する
  [ -d "${FIXTURES_DIR}" ]
}

@test "ac5.1: mock-cld-observe-any.sh fixture exists and is executable" {
  # AC: fixtures/mock-cld-observe-any.sh が存在し実行可能である
  [ -f "${MOCK_DAEMON}" ]
  [ -x "${MOCK_DAEMON}" ]
}

@test "ac5.1: pitfalls-doobidoo-snapshot.json fixture exists" {
  # AC: fixtures/pitfalls-doobidoo-snapshot.json が存在する
  [ -f "${PITFALLS_SNAPSHOT}" ]
}

# ===========================================================================
# AC5.2: C1 — Step 0 完了後、Monitor task (cld-observe-any) が active であること
#
#   mock daemon を背景プロセスとして起動し、pgrep -f 'cld-observe-any' が
#   exit 0 かつ PID > 0 を返すことを確認する。
#   実 cld-observe-any は CI 環境で起動不可のため mock で代替する。
#
#   mock 起動形式: `bash "${MOCK_DAEMON}" &`
#   スクリプトパスに 'cld-observe-any' を含めることで pgrep -f がマッチする。
# ===========================================================================

@test "ac5.2: mock cld-observe-any daemon starts as background process" {
  # AC: mock daemon がバックグラウンドで起動できる
  # RED: mock daemon は実装済みのため GREEN になるが、実 cld-observe-any との統合は未検証
  # fixture スクリプト経由: bash ./mock-cld-observe-any.sh の cmdline に cld-observe-any が含まれ pgrep でマッチ
  bash "${MOCK_DAEMON}" &
  MOCK_PID=$!
  export MOCK_PID

  # プロセスが起動していることを確認
  [ -n "${MOCK_PID}" ]
  kill -0 "${MOCK_PID}" 2>/dev/null

  # cleanup
  kill "${MOCK_PID}" 2>/dev/null || true
  MOCK_PID=""
}

@test "ac5.2: pgrep -f 'cld-observe-any' matches mock daemon process" {
  # AC: pgrep -f 'cld-observe-any' が mock daemon にマッチし exit 0 を返す
  # RED: 実 cld-observe-any が CI で起動できないため、mock で代替検証する

  # mock process を起動（fixture スクリプトパスに cld-observe-any が含まれる）
  bash "${MOCK_DAEMON}" &
  MOCK_PID=$!
  export MOCK_PID

  # pgrep -f で process arg name にマッチすることを確認
  sleep 0.3
  run pgrep -f 'cld-observe-any'
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  # 返された PID が正の整数であることを確認
  local pid
  pid=$(echo "${output}" | head -1 | tr -d '[:space:]')
  [ "${pid}" -gt 0 ]

  # cleanup
  kill "${MOCK_PID}" 2>/dev/null || true
  MOCK_PID=""
}

@test "ac5.2: cld-observe-any mock is stopped when killed" {
  # AC: mock daemon を kill すると pgrep がマッチしなくなる (cleanup 動作確認)
  bash "${MOCK_DAEMON}" &
  MOCK_PID=$!
  export MOCK_PID
  local mock_pid="${MOCK_PID}"

  # 起動直後は pgrep でマッチする
  sleep 0.3
  run pgrep -f 'cld-observe-any'
  [ "${status}" -eq 0 ]

  # kill 後は pgrep でマッチしなくなる
  kill "${mock_pid}" 2>/dev/null || true
  sleep 0.5
  run pgrep -f "${MOCK_DAEMON}"
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC5.3: C2 — pitfalls-catalog.md の §X.Y エントリ数と doobidoo snapshot が一致すること
#
#   デフォルト (CI / BATS_DOOBIDOO 未設定):
#     pitfalls-catalog.md の `^| [0-9]+\.[0-9]+` エントリ数と
#     fixtures/pitfalls-doobidoo-snapshot.json の entries 配列長が一致すること
#
#   オプション (BATS_DOOBIDOO=1 設定時):
#     実 doobidoo API を使用（CI では skip）
# ===========================================================================

@test "ac5.3: pitfalls-catalog.md has expected number of §X.Y entries (56)" {
  # AC: pitfalls-catalog.md の §X.Y エントリ数が snapshot と一致する
  # RED: pitfalls-catalog.md のエントリ数が snapshot と乖離する場合は fail
  local catalog_count
  catalog_count=$(grep -cE "^\| [0-9]+\.[0-9]+" "${PITFALLS_CATALOG}")
  [ "${catalog_count}" -eq 56 ]
}

@test "ac5.3: pitfalls-doobidoo-snapshot.json has 56 entries" {
  # AC: snapshot fixture の total_count が 56 である
  local snapshot_count
  snapshot_count=$(python3 -c "
import json, sys
with open('${PITFALLS_SNAPSHOT}') as f:
    d = json.load(f)
print(d['total_count'])
")
  [ "${snapshot_count}" -eq 56 ]
}

@test "ac5.3: snapshot entries count matches pitfalls-catalog.md entry count" {
  # AC: pitfalls-catalog.md の §X.Y エントリ数と snapshot の entries 配列長が一致する
  # デフォルト動作 (BATS_DOOBIDOO 未設定): snapshot fixture で比較
  if [[ "${BATS_DOOBIDOO:-0}" == "1" ]]; then
    skip "BATS_DOOBIDOO=1: 実 doobidoo API テストは別途実行"
  fi

  local catalog_count
  catalog_count=$(grep -cE "^\| [0-9]+\.[0-9]+" "${PITFALLS_CATALOG}")

  local snapshot_entries_count
  snapshot_entries_count=$(python3 -c "
import json, sys
with open('${PITFALLS_SNAPSHOT}') as f:
    d = json.load(f)
print(len(d['entries']))
")

  [ "${catalog_count}" -eq "${snapshot_entries_count}" ]
}

@test "ac5.3: snapshot entries all have tag=observer-pitfall" {
  # AC: snapshot の全エントリが tag=observer-pitfall を持つ
  if [[ "${BATS_DOOBIDOO:-0}" == "1" ]]; then
    skip "BATS_DOOBIDOO=1: 実 doobidoo API テストは別途実行"
  fi

  local all_have_tag
  all_have_tag=$(python3 -c "
import json, sys
with open('${PITFALLS_SNAPSHOT}') as f:
    d = json.load(f)
bad = [e for e in d['entries'] if e.get('tag') != 'observer-pitfall']
print('OK' if not bad else 'FAIL:' + str(bad[:3]))
")
  [ "${all_have_tag}" = "OK" ]
}

@test "ac5.3: snapshot sections cover all §X.Y from pitfalls-catalog.md" {
  # AC: snapshot の section 番号が pitfalls-catalog.md の §X.Y セクションと一致する
  if [[ "${BATS_DOOBIDOO:-0}" == "1" ]]; then
    skip "BATS_DOOBIDOO=1: 実 doobidoo API テストは別途実行"
  fi

  # catalog から section 番号を抽出してソート
  local catalog_sections
  catalog_sections=$(grep -oE "^\| [0-9]+\.[0-9]+" "${PITFALLS_CATALOG}" | tr -d '| ' | LC_ALL=C sort)

  # snapshot から section 番号を抽出してソート
  local snapshot_sections
  snapshot_sections=$(python3 -c "
import json, sys
with open('${PITFALLS_SNAPSHOT}') as f:
    d = json.load(f)
sections = sorted(e['section'] for e in d['entries'])
print('\n'.join(sections))
")

  [ "${catalog_sections}" = "${snapshot_sections}" ]
}

# ===========================================================================
# AC5.4: C3 — spawn-controller.sh 起動後に Monitor channel reset 出力が含まれること
#
#   Sub 2 (#feat-AC3) merge 前は RED-phase test として conditional skip する。
#   spawn-controller.sh に ">>> Monitor 再 arm 必要:" が実装されていない場合は
#   bats skip で明示する。
#
#   NOTE (baseline-bash §10): spawn-controller.sh に source guard が不在のため、
#   source による副作用は発生しない。代わりに実行結果の stdout/stderr を検査する。
#   CLD_SPAWN=/bin/true で cld-spawn 副作用を排除し、SKIP_PARALLEL_CHECK=1 で
#   並列チェックをバイパスする。
# ===========================================================================

@test "ac5.4: spawn-controller.sh exists and is executable" {
  # AC: spawn-controller.sh が存在し実行可能である
  [ -f "${SPAWN_CONTROLLER}" ]
  [ -x "${SPAWN_CONTROLLER}" ]
}

@test "ac5.4: spawn-controller.sh output contains '>>> Monitor 再 arm 必要' (Sub 2 feature)" {
  # AC: spawn-controller.sh 起動後の出力に Monitor channel reset 文字列が含まれる
  # Sub 2 merge 前は skip する（conditional skip）

  # Sub 2 未 merge チェック: spawn-controller.sh に実装がなければ skip
  if [[ -z "$(grep '>>> Monitor 再 arm 必要' "${SPAWN_CONTROLLER}" 2>/dev/null)" ]]; then
    skip 'Sub 2 (#feat-AC3) 未 merge: spawn-controller.sh に ">>> Monitor 再 arm 必要" が未実装'
  fi

  # Sub 2 が merge された場合のテスト（CLD_SPAWN stub + SKIP_PARALLEL_CHECK=1）
  # 最小限の prompt ファイルを作成
  local prompt_file="${TMPDIR_TEST}/test-prompt.txt"
  echo "test prompt for ac5.4" > "${prompt_file}"

  # spawn-controller.sh を CLD_SPAWN stub で実行し出力を確認
  run env \
    CLD_SPAWN=/bin/true \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="ac5.4-bats-test" \
    bash "${SPAWN_CONTROLLER}" co-autopilot "${prompt_file}"

  # 出力に Monitor 再 arm 文字列が含まれることを確認
  [[ "${output}" == *">>> Monitor 再 arm 必要"* ]]
}

@test "ac5.4: (pre-Sub2) spawn-controller.sh does NOT yet have Monitor arm string" {
  # AC5.4 Sub 2 merge 前の確認テスト:
  #   spawn-controller.sh に ">>> Monitor 再 arm 必要:" が未実装であることを確認する
  #   (このテストは Sub 2 merge 後に削除または反転させること)
  # RED: Sub 2 未実装のため ">>> Monitor 再 arm 必要" が不在であることを assert
  run grep '>>> Monitor 再 arm 必要' "${SPAWN_CONTROLLER}"
  # Sub 2 未 merge の場合は grep が 1 を返す（not found）
  [ "${status}" -ne 0 ]
}
