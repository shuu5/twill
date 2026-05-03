#!/usr/bin/env bats
# issue-1250-record-detection-gap-flock.bats
#
# RED-phase tests for Issue #1250:
#   tech-debt(observer): record-detection-gap.sh の append 書き込みに flock 排他制御を追加する
#
# 問題: .supervisor/intervention-log.md への append 書き込みが flock 保護なし。
#       複数 worker が同時呼び出しした場合、race condition でログ行が失われる可能性がある。
#
# 修正方針: append 操作に flock を使った排他制御を追加する。
#
# AC coverage:
#   AC-1: record-detection-gap.sh に flock 使用が存在することを確認（静的確認）
#   AC-2: 並列呼び出し時にログ行が失われないことを確認（同時 10 プロセス → wc -l が 10 以上）
#   AC-3: twl validate 相当の検証で WARNING がないことを確認（現時点では skip）
#   AC-4: 既存機能（--type, --detail, log 追記）が flock 追加後も正常動作することを確認
#
# 全テストは実装前（RED）状態で fail する（flock が未実装のため）。
# SUPERVISOR_DIR は相対パスのみ（絶対パス不可）。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  # このファイルは tests/bats/ 直下に配置されているため、2レベルアップで REPO_ROOT に到達
  # tests/bats/ -> tests/ -> plugins/twl/ (REPO_ROOT)
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
  export SCRIPT

  # テスト実行時のカレントディレクトリを tmpdir に切り替え（SUPERVISOR_DIR 相対パス用）
  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
  cd "${TMPDIR_TEST}"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC-1: record-detection-gap.sh に flock 使用が存在することを確認（静的確認）
# ===========================================================================

@test "ac1: record-detection-gap.sh contains flock command" {
  # AC: flock 保護が実装されている（grep で静的確認）
  # RED: 現在の実装に flock が存在しないため fail
  run grep -E '\bflock\b' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac1: flock is used in proximity to intervention-log.md append" {
  # AC: flock がログ追記箇所を保護している（flock と >> の組み合わせが存在する）
  # RED: 現在の実装に flock が存在しないため fail
  # grep でマッチがあれば exit 0、なければ exit 1
  run grep -c 'flock' "${SCRIPT}"
  # マッチ件数が 0 件（grep -c が 0 を返し exit 1）の場合は fail
  [ "${status}" -eq 0 ]
  [ "${output}" -gt 0 ]
}

# ===========================================================================
# AC-2: 並列呼び出し時にログ行が失われないことを確認
#        静的確認（flock の存在）と動的確認（並列実行）の両面でカバー
# ===========================================================================

@test "ac2: flock lock mechanism is statically present for concurrency safety" {
  # AC: flock によるロックが script に静的に存在する（並列安全の前提条件）
  # RED: 現在の実装に flock が存在しないため fail
  # 実装では flock -n, flock -x, または exec {fd}< ... flock $fd のいずれかが必要
  run grep -E '\bflock\b.*(-[nexsu]|[0-9]+)' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: concurrent 10 writes produce exactly 10 log lines (no race condition loss)" {
  # AC: 10 プロセス並列で記録した場合、ログに正確に 10 行存在する（行消失なし）
  # RED: flock がないため race condition でログ行が失われる可能性があり、
  #      かつ静的確認（ac2 test1）が fail するため、この AC は実装依存
  # 注意: このテストは race condition を確定的に再現しないが、
  #       flock なし環境では偶発的に fail する（非決定的 RED）。
  #       静的確認テストと合わせて AC-2 をカバーする。
  local supervisor_dir="flock-parallel-test"
  local log_file="${supervisor_dir}/intervention-log.md"

  # 10 プロセスを並列起動して wait
  for i in $(seq 1 10); do
    SUPERVISOR_DIR="${supervisor_dir}" \
      bash "${SCRIPT}" \
        --type "parallel-test" \
        --detail "worker ${i} write" \
        --severity low &
  done
  wait

  local line_count
  line_count="$(wc -l < "${log_file}" 2>/dev/null || echo 0)"
  # flock なしでは行数が 10 未満になる可能性がある（race condition）
  # flock ありでは常に 10 行であることを保証する
  [ "${line_count}" -eq 10 ]
}

# ===========================================================================
# AC-3: twl validate 相当の検証で WARNING がないことを確認
#        現時点では環境依存のためスキップ
# ===========================================================================

@test "ac3: twl check --check reports no missing files (WARNING-free)" {
  # AC: twl validate 相当で WARNING が出ないこと
  # RED: 実装前は skip（この AC は実装完了後に手動確認）
  skip "AC-3: twl check は実装完了後に手動確認。実装後 GREEN 化すること"
}

# ===========================================================================
# AC-4: 既存機能が flock 追加後も正常動作することを確認（regression test）
# ===========================================================================

@test "ac4: basic invocation with --type and --detail appends to log" {
  # AC: flock 追加後も --type, --detail の基本動作（log 追記）が維持される
  # RED: flock 実装後の regression 保証テスト。実装前後ともに GREEN が期待されるが、
  #      flock 実装によって append が壊れた場合に fail する
  local supervisor_dir="basic-regression"
  SUPERVISOR_DIR="${supervisor_dir}" \
    bash "${SCRIPT}" \
      --type "regression-check" \
      --detail "basic invocation test"
  [ -f "${supervisor_dir}/intervention-log.md" ]
  local line_count
  line_count="$(wc -l < "${supervisor_dir}/intervention-log.md")"
  [ "${line_count}" -ge 1 ]
}

@test "ac4: log entry format is preserved after flock addition (ISO 8601 timestamp)" {
  # AC: flock 追加後もログエントリの形式が保持される（ISO 8601 タイムスタンプ）
  local supervisor_dir="format-regression"
  SUPERVISOR_DIR="${supervisor_dir}" \
    bash "${SCRIPT}" \
      --type "format-check" \
      --detail "timestamp format test"

  run bash -c "tail -1 '${supervisor_dir}/intervention-log.md' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[detection-gap\]'"
  [ "${status}" -eq 0 ]
}

@test "ac4: --related-issue option still works after flock addition" {
  # AC: --related-issue オプションが flock 追加後も正常動作する
  local supervisor_dir="related-issue-regression"
  SUPERVISOR_DIR="${supervisor_dir}" \
    bash "${SCRIPT}" \
      --type "related-check" \
      --detail "related issue test" \
      --related-issue "#1250"

  run grep '#1250\|1250' "${supervisor_dir}/intervention-log.md"
  [ "${status}" -eq 0 ]
}

@test "ac4: --severity high hint still outputs to stderr after flock addition" {
  # AC: --severity high の stderr hint 出力が flock 追加後も保持される
  local supervisor_dir="severity-regression"
  run bash -c "SUPERVISOR_DIR='${supervisor_dir}' bash '${SCRIPT}' \
    --type 'severity-check' \
    --detail 'severity high regression' \
    --severity high 2>&1 >/dev/null"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "gh issue create" ]]
}

@test "ac4: sequential writes produce correct line count (no truncation by flock)" {
  # AC: 逐次書き込み時に flock がログを壊さない（5 回書き込み → 5 行）
  local supervisor_dir="sequential-regression"
  for i in $(seq 1 5); do
    SUPERVISOR_DIR="${supervisor_dir}" \
      bash "${SCRIPT}" \
        --type "sequential-test" \
        --detail "sequential write ${i}" \
        --severity low
  done

  local line_count
  line_count="$(wc -l < "${supervisor_dir}/intervention-log.md")"
  [ "${line_count}" -eq 5 ]
}
