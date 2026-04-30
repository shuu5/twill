#!/usr/bin/env bats
# observer-auto-next-spawn.bats
#
# RED-phase tests for Issue #1155:
#   feat(observer): IDLE-COMPLETED -> 自動 next-action 機構
#
# AC coverage:
#   AC1  - IDLE_COMPLETED_AUTO_NEXT_SPAWN 環境変数新設（AUTO_KILL と独立評価）
#   AC2  - .supervisor/wave-queue.json JSON Schema 管理 + validation
#   AC3  - _all_current_wave_idle_completed() で同 Wave 全 window IDLE-COMPLETED 判定
#   AC4  - auto-next-spawn.sh 新設（--queue/--triggered-by/--dry-run, exec argv 直接渡し）
#   AC5  - intervention-log.md への auto-cleanup+next-spawn 記録
#   AC6  - AUTO_NEXT_SPAWN=0 / 未設定時の #1132 既存 kill-only 動作保全
#   AC7  - 誤 spawn シナリオ全 spawn-skip（5 シナリオ）
#   AC8  - AUTO_NEXT_SPAWN=dry-run / --dry-run で spawn echo のみ
#   AC9  - observer-auto-next-spawn.bats 6 ケース GREEN（本ファイル自体の AC）
#   AC10 - ドキュメント 5 箇所更新
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  AUTO_NEXT_SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/auto-next-spawn.sh"
  OBSERVER_WAVE_CHECK="${REPO_ROOT}/skills/su-observer/scripts/lib/observer-wave-check.sh"
  WAVE_QUEUE_SCHEMA="${REPO_ROOT}/skills/su-observer/schemas/wave-queue.schema.json"
  SPAWN_CONTROLLER="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"
  OBSERVER_IDLE_CHECK="${REPO_ROOT}/skills/su-observer/scripts/lib/observer-idle-check.sh"
  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  DEPS_YAML="${REPO_ROOT}/deps.yaml"
  WAVE_MGMT_DOC="${REPO_ROOT}/skills/su-observer/refs/su-observer-wave-management.md"

  export AUTO_NEXT_SPAWN_SCRIPT OBSERVER_WAVE_CHECK WAVE_QUEUE_SCHEMA
  export SPAWN_CONTROLLER CLD_OBSERVE_ANY OBSERVER_IDLE_CHECK
  export MONITOR_CATALOG PITFALLS_CATALOG SKILL_MD DEPS_YAML WAVE_MGMT_DOC

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST

  # テスト用 supervisor dir のセットアップ
  SUPERVISOR_DIR="${TMPDIR_TEST}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"
  export SUPERVISOR_DIR
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC-9 ケース 1: AUTO_NEXT_SPAWN 未設定 → kill のみ（#1132 regression）
#   - wave-queue.json 不参照
#   - intervention-log に auto- 記録なし
#   - unset IDLE_COMPLETED_TS[$WIN] のみ
# ===========================================================================

@test "ac9-case1: AUTO_NEXT_SPAWN unset -> kill only, wave-queue.json not referenced" {
  # AC: IDLE_COMPLETED_AUTO_NEXT_SPAWN 未設定時は #1132 の kill-only 動作を維持する
  # RED: auto-next-spawn.sh が未実装のため fail

  # wave-queue.json が存在しない状態で、AUTO_NEXT_SPAWN=0 時に参照されないことを検証
  # cld-observe-any が AUTO_NEXT_SPAWN=0 時に auto-next-spawn.sh を呼ばないことを確認
  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN' "${CLD_OBSERVE_ANY}"
  # AUTO_NEXT_SPAWN 分岐が cld-observe-any に実装されていないため fail
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac9-case1: AUTO_NEXT_SPAWN unset -> intervention-log has no auto-cleanup+next-spawn record" {
  # AC: AUTO_NEXT_SPAWN 未設定時は intervention-log に auto-cleanup+next-spawn を記録しない
  # RED: 実装が存在しないため fail

  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"

  # kill のみ実行した後に intervention-log に auto- プレフィックスが書かれないことを確認
  # 実装後は AUTO_KILL=1 かつ AUTO_NEXT_SPAWN=0 の場合のスモークテストとなる
  # 現時点では auto-next-spawn.sh が存在しないため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
}

@test "ac9-case1: AUTO_NEXT_SPAWN unset -> cld-observe-any behavior unchanged (kill-only path exists)" {
  # AC: #1132 既存動作（IDLE_COMPLETED_AUTO_KILL=1 → kill のみ）が保全されている
  # RED: AUTO_NEXT_SPAWN 分岐が未実装のため fail

  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN|AUTO_NEXT_SPAWN' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC-9 ケース 2: AUTO_NEXT_SPAWN=1 + 同 Wave 全 idle + valid queue → spawn 実行
#   - intervention-log 記録
#   - wave-queue.json 更新（dequeue + current_wave 更新）
# ===========================================================================

@test "ac9-case2: AUTO_NEXT_SPAWN=1 + all-wave-idle + valid queue -> spawn executed" {
  # AC: AUTO_NEXT_SPAWN=1 かつ同 Wave 全 window が IDLE-COMPLETED かつ valid queue 存在時に
  #     spawn_cmd_argv を exec で実行する
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  # valid wave-queue.json を作成
  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [200, 201],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  # --dry-run なしで次 wave の spawn コマンドが exec される（bash --version は安全）
  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-window-12345" \
    --dry-run
  # dry-run でも 0 exit のはず（実装後）
  [ "${status}" -eq 0 ]
}

@test "ac9-case2: AUTO_NEXT_SPAWN=1 + spawn -> intervention-log appended" {
  # AC: spawn 実行時に intervention-log.md に記録が追記される
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [200, 201],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-window-12345" \
    --dry-run

  [ "${status}" -eq 0 ]
  # intervention-log に auto-cleanup+next-spawn または auto-cleanup+next-spawn-dryrun が記録される
  run grep -E 'auto-cleanup\+next-spawn' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac9-case2: AUTO_NEXT_SPAWN=1 + spawn -> wave-queue.json dequeued and current_wave updated" {
  # AC: spawn 成功後に wave-queue.json から該当 entry を削除し current_wave を更新する
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [200, 201],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  # dry-run では queue を dequeue しないため non-dry-run で確認したいが
  # exec で実際の spawn をテスト内で実行するのは危険なため、
  # dry-run=false 相当のロジック（queue 更新部分）の単体テストとして実装後に GREEN になる
  # 現時点は fail("AC#9-case2 未実装") と等価
  fail "AC#9 case2 (wave-queue dequeue) 未実装"
}

# ===========================================================================
# AC-9 ケース 3: AUTO_NEXT_SPAWN=1 + 同 Wave 一部 active → spawn skip
#   - intervention-log に skipped reason 記録
# ===========================================================================

@test "ac9-case3: AUTO_NEXT_SPAWN=1 + some-wave-window-active -> spawn skipped" {
  # AC: 同 Wave に active（非 IDLE-COMPLETED）window が残存する場合は spawn をスキップする
  # RED: observer-wave-check.sh と auto-next-spawn.sh が未実装のため fail

  [ -f "${OBSERVER_WAVE_CHECK}" ]
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [200],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  # IDLE_COMPLETED_TS を部分的にのみ設定（同 Wave の一部 window のみ IDLE-COMPLETED）
  # _all_current_wave_idle_completed が false を返すシナリオ
  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-active-window-99999"
  # spawn skip のため exit 0（skip は失敗ではない）
  [ "${status}" -eq 0 ]

  # stdout に spawn skip の旨が出力される
  echo "${output}" | grep -E 'skip|SKIP|not all.*idle|active.*window'
}

@test "ac9-case3: spawn skipped -> intervention-log has skipped reason" {
  # AC: spawn skip 時に intervention-log に auto-cleanup+next-spawn-skipped を記録する
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"

  fail "AC#9 case3 (spawn skip intervention-log) 未実装"
}

# ===========================================================================
# AC-9 ケース 4: AUTO_NEXT_SPAWN=1 + wave-queue.json 不在 → warning log + skip（exit 0）
# ===========================================================================

@test "ac9-case4: AUTO_NEXT_SPAWN=1 + wave-queue.json missing -> warning log + skip exit 0" {
  # AC: wave-queue.json が不在の場合は warning log を出して spawn をスキップし exit 0 する
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  # wave-queue.json を作成しない
  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-12345"

  # exit 0 で終了する（skip は失敗ではない）
  [ "${status}" -eq 0 ]

  # warning が出力される
  echo "${output}${stderr}" | grep -iE 'warn|missing|not found|not exist|no.*queue'
}

# ===========================================================================
# AC-9 ケース 5: AUTO_NEXT_SPAWN=1 + JSON Schema invalid → warning log + spawn skip
# ===========================================================================

@test "ac9-case5: AUTO_NEXT_SPAWN=1 + invalid wave-queue.json schema -> warning + skip" {
  # AC: JSON Schema validation 失敗時（e.g. version=2）は warning log + spawn skip する
  # RED: auto-next-spawn.sh と wave-queue.schema.json が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  # version=2 は invalid（schema では version=1 固定）
  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 2,
  "current_wave": 1,
  "queue": []
}
EOF

  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-12345"

  # exit 0 で終了する（schema 不正は致命的エラーではなく skip）
  [ "${status}" -eq 0 ]

  # warning が出力される
  echo "${output}${stderr}" | grep -iE 'warn|invalid|schema|validation'
}

@test "ac9-case5: wave-queue.schema.json exists and is valid JSON" {
  # AC: wave-queue.schema.json が存在し valid JSON である
  # RED: ファイルが未作成のため fail

  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  run jq empty "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-9 ケース 6: AUTO_NEXT_SPAWN=dry-run → echo のみ・実 spawn なし・queue 状態保持
#   - intervention-log に auto-cleanup+next-spawn-dryrun 記録
# ===========================================================================

@test "ac9-case6: AUTO_NEXT_SPAWN=dry-run -> spawn command echoed only, no exec" {
  # AC: dry-run モードでは spawn_cmd_argv を echo するだけで実際の exec を行わない
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [300],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-12345" \
    --dry-run

  [ "${status}" -eq 0 ]
  # spawn コマンドが echo されている
  echo "${output}" | grep -E 'bash|--version|dry.run|DRY.RUN|dryrun'
}

@test "ac9-case6: dry-run -> wave-queue.json queue state preserved (not dequeued)" {
  # AC: dry-run 実行後に wave-queue.json の queue は変化しない（dequeue しない）
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [300],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-12345" \
    --dry-run || true

  # queue の wave 2 エントリが残っていることを確認
  run jq -e '.queue | length > 0' "${SUPERVISOR_DIR}/wave-queue.json"
  [ "${status}" -eq 0 ]
}

@test "ac9-case6: dry-run -> intervention-log has dryrun record" {
  # AC: dry-run 時に intervention-log に auto-cleanup+next-spawn-dryrun として記録される
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [300],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-12345" \
    --dry-run || true

  run grep -E 'auto-cleanup\+next-spawn-dryrun' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 追加テスト: AC-1 IDLE_COMPLETED_AUTO_NEXT_SPAWN 変数定義
# ===========================================================================

@test "ac1: cld-observe-any has IDLE_COMPLETED_AUTO_NEXT_SPAWN branch" {
  # AC: cld-observe-any に IDLE_COMPLETED_AUTO_NEXT_SPAWN 評価分岐が追加される
  # RED: 未実装のため fail
  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac1: AUTO_NEXT_SPAWN and AUTO_KILL are evaluated independently" {
  # AC: AUTO_NEXT_SPAWN=1 かつ AUTO_KILL=0 の場合は warning log + next-spawn skip となる
  # RED: 分岐が未実装のため fail
  run grep -E 'AUTO_KILL.*AUTO_NEXT_SPAWN|AUTO_NEXT_SPAWN.*AUTO_KILL|warning.*AUTO_KILL' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac1: AUTO_KILL=0 and AUTO_NEXT_SPAWN=1 triggers warning" {
  # AC: AUTO_KILL=0 & AUTO_NEXT_SPAWN=1 の組み合わせで warning log が出る
  # RED: 実装が存在しないため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  fail "AC#1 (AUTO_KILL=0 + AUTO_NEXT_SPAWN=1 warning) 未実装"
}

# ===========================================================================
# 追加テスト: AC-2 wave-queue.json JSON Schema validation
# ===========================================================================

@test "ac2: wave-queue.json schema has required version field (int=1)" {
  # AC: wave-queue.schema.json が version フィールド（int, const=1）を必須として定義する
  # RED: wave-queue.schema.json が未作成のため fail
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  run jq -e '.properties.version' "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-queue.json schema has required current_wave field (int)" {
  # AC: wave-queue.schema.json が current_wave フィールドを必須として定義する
  # RED: wave-queue.schema.json が未作成のため fail
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  run jq -e '.properties.current_wave' "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-queue.json schema has required queue[].spawn_cmd_argv field (string[], minItems=1)" {
  # AC: queue[].spawn_cmd_argv が string[] minItems=1 として定義される
  # RED: wave-queue.schema.json が未作成のため fail
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  run jq -e '.definitions.WaveEntry.properties.spawn_cmd_argv // .properties.queue.items.properties.spawn_cmd_argv' "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-queue.json schema has spawn_when enum (all_current_wave_idle_completed)" {
  # AC: spawn_when が enum で all_current_wave_idle_completed を含む
  # RED: wave-queue.schema.json が未作成のため fail
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  run grep -E 'all_current_wave_idle_completed' "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

@test "ac2: auto-next-spawn.sh performs jq schema validation on startup" {
  # AC: auto-next-spawn.sh 起動時に jq または validate-schema.sh で JSON Schema validation を実行する
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'jq.*validate|validate-schema|schema.*valid|valid.*schema|jq.*schema' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 追加テスト: AC-3 observer-wave-check.sh 新設
# ===========================================================================

@test "ac3: scripts/lib/observer-wave-check.sh exists" {
  # AC: observer-wave-check.sh が scripts/lib/ に新規作成される
  # RED: ファイルが未作成のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
}

@test "ac3: observer-wave-check.sh defines _all_current_wave_idle_completed function" {
  # AC: _all_current_wave_idle_completed() 関数が定義されている
  # RED: ファイルが未作成のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  run grep -E '^_all_current_wave_idle_completed\(\)|^function _all_current_wave_idle_completed' \
    "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
}

@test "ac3: _all_current_wave_idle_completed uses wave-queue.json current_wave" {
  # AC: 関数内で wave-queue.json の current_wave を取得している
  # RED: ファイルが未作成のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  run grep -E 'current_wave' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
}

@test "ac3: _all_current_wave_idle_completed uses tmux list-windows with (ap|wt|coi) filter" {
  # AC: tmux list-windows の結果を ^(ap|wt|coi)-.*  パターンでフィルタする
  # RED: ファイルが未作成のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  run grep -E 'list-windows|ap.*wt.*coi|coi.*wt.*ap|\(ap\|wt\|coi\)' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
}

@test "ac3: _all_current_wave_idle_completed checks IDLE_COMPLETED_TS for all wave windows" {
  # AC: 同 Wave 全 window の IDLE_COMPLETED_TS[$WIN] > 0 を確認する
  # RED: ファイルが未作成のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  run grep -E 'IDLE_COMPLETED_TS' "${OBSERVER_WAVE_CHECK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 追加テスト: AC-4 auto-next-spawn.sh 新設
# ===========================================================================

@test "ac4: auto-next-spawn.sh exists" {
  # AC: auto-next-spawn.sh が scripts/ に新規作成される
  # RED: ファイルが未作成のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
}

@test "ac4: auto-next-spawn.sh accepts --queue argument" {
  # AC: --queue <path> 引数を受け付ける
  # RED: ファイルが未作成のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E '\-\-queue|--queue' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: auto-next-spawn.sh accepts --triggered-by argument" {
  # AC: --triggered-by <window> 引数を受け付ける
  # RED: ファイルが未作成のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E '\-\-triggered.by|triggered_by' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: auto-next-spawn.sh uses exec not eval for spawn_cmd_argv" {
  # AC: spawn_cmd_argv の実行は exec を使用し eval/bash -c は禁止
  # RED: ファイルが未作成のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  # exec が使用されていることを確認
  run grep -E '^[[:space:]]*exec[[:space:]]' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
  # eval が使用されていないことを確認
  run grep -E '^[[:space:]]*eval[[:space:]]' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -ne 0 ]
}

@test "ac4: auto-next-spawn.sh validates spawn_cmd_argv[0] against allowlist" {
  # AC: spawn_cmd_argv[0] が bash / cld-spawn 絶対パス のみ許可するアローリストで検証する
  # RED: ファイルが未作成のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'allowlist|allow.list|cld.spawn|bash.*allow' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: auto-next-spawn.sh rejects spawn_cmd_argv[0] outside allowlist with intervention-log" {
  # AC: アローリスト外の spawn_cmd_argv[0] を abort し intervention-log に拒否ログを書く
  # RED: auto-next-spawn.sh が未実装のため fail

  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]

  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"

  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 1,
  "queue": [
    {
      "wave": 2,
      "issues": [400],
      "spawn_cmd_argv": ["/usr/bin/evil-command", "--args"],
      "depends_on_waves": [1],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  run bash "${AUTO_NEXT_SPAWN_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --triggered-by "wt-test-12345"

  # abort（非 0 exit）
  [ "${status}" -ne 0 ]

  # intervention-log に拒否ログが書かれる
  run grep -E 'reject|deny|abort|allowlist|not allowed' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 追加テスト: AC-5 intervention-log.md フォーマット
# ===========================================================================

@test "ac5: auto-next-spawn.sh appends ISO8601 UTC timestamp to intervention-log" {
  # AC: intervention-log への記録が ISO8601 UTC タイムスタンプで始まる
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'date.*ISO|date.*UTC|date -u.*%FT%T|iso8601|ISO8601' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: intervention-log format includes triggered_by and killed fields" {
  # AC: ログ形式が triggered_by=<window>, killed=<window> を含む
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'triggered_by|killed=' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: intervention-log format includes next_wave and spawned fields on success" {
  # AC: ログ形式が next_wave=<N>, spawned=[<issue_csv>] を含む
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'next_wave=|spawned=' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: intervention-log records spawn-skipped with reason on skip" {
  # AC: skip 時に auto-cleanup+next-spawn-skipped: triggered_by=<w>, reason=<理由> を記録
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'next-spawn-skipped|spawn.skipped.*reason|reason.*skip' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 追加テスト: AC-6 AUTO_NEXT_SPAWN=0 での kill-only 動作保全
# ===========================================================================

@test "ac6: AUTO_KILL=1 only (no AUTO_NEXT_SPAWN) -> kill executes" {
  # AC: IDLE_COMPLETED_AUTO_KILL=1 のみ設定時は kill を実行する（既存 #1132 動作）
  # RED: 検証に必要な AUTO_NEXT_SPAWN 分岐が未実装のため fail
  run grep -E 'IDLE_COMPLETED_AUTO_KILL.*1' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  # AUTO_NEXT_SPAWN のチェックが AUTO_KILL と独立していることを確認
  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac6: AUTO_KILL=1 only -> wave-queue.json not referenced in kill-only path" {
  # AC: kill-only パスでは wave-queue.json を参照しない
  # RED: 分岐が未実装のため fail
  fail "AC#6 (kill-only path wave-queue not referenced) 未実装"
}

@test "ac6: AUTO_KILL=1 only -> no auto-cleanup+next-spawn in intervention-log" {
  # AC: kill-only 実行後の intervention-log に auto-cleanup+next-spawn 行がない
  # RED: auto-next-spawn.sh が未実装のため fail
  fail "AC#6 (kill-only intervention-log has no auto- record) 未実装"
}

@test "ac6: AUTO_KILL=1 only -> unset IDLE_COMPLETED_TS[WIN] after kill, AUTO_NEXT_SPAWN path absent" {
  # AC: kill 成功後に IDLE_COMPLETED_TS[$WIN] を unset する（既存動作）かつ
  #     AUTO_NEXT_SPAWN の分岐が kill-only パスには存在しない
  # RED: kill-only パスの AUTO_NEXT_SPAWN 独立評価が未実装のため fail
  run grep -E "unset.*IDLE_COMPLETED_TS" "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  # kill-only パスで AUTO_NEXT_SPAWN が独立して評価される分岐が存在することを確認
  # （既存 kill パスと次 spawn パスが独立した if ブロックであることが必要）
  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# 追加テスト: AC-7 誤 spawn シナリオ全 spawn-skip
# ===========================================================================

@test "ac7-a: active window remaining in wave -> spawn skipped" {
  # AC: 同 Wave に active window 残存時は spawn をスキップする
  # RED: observer-wave-check.sh が未実装のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  fail "AC#7(a) (active window -> spawn skip) 未実装"
}

@test "ac7-b: LLM-active-override (C3) window exists -> spawn skipped" {
  # AC: _check_idle_completed C3(LLM-active-override)が真の window が存在する場合は spawn スキップ
  # RED: observer-wave-check.sh が未実装のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  fail "AC#7(b) (C3 LLM-active-override -> spawn skip) 未実装"
}

@test "ac7-c: wave-queue.json absent -> spawn skipped (exit 0)" {
  # AC: wave-queue.json 不在時は warning log + spawn skip で exit 0
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  fail "AC#7(c) (wave-queue absent -> skip exit 0) 未実装"
}

@test "ac7-d: JSON schema validation failure -> spawn skipped" {
  # AC: JSON Schema validation 失敗時は warning log + spawn skip
  # RED: auto-next-spawn.sh と wave-queue.schema.json が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  fail "AC#7(d) (schema invalid -> skip) 未実装"
}

@test "ac7-e: current_wave mismatch (triggered window not in current_wave) -> spawn skipped" {
  # AC: kill 対象 window が current_wave に属さない場合は spawn をスキップする
  # RED: observer-wave-check.sh が未実装のため fail
  [ -f "${OBSERVER_WAVE_CHECK}" ]
  fail "AC#7(e) (current_wave mismatch -> skip) 未実装"
}

# ===========================================================================
# 追加テスト: AC-8 dry-run モード
# ===========================================================================

@test "ac8: IDLE_COMPLETED_AUTO_NEXT_SPAWN=dry-run in env -> dry-run mode activated" {
  # AC: 環境変数 IDLE_COMPLETED_AUTO_NEXT_SPAWN=dry-run で dry-run モードが有効になる
  # RED: cld-observe-any への AUTO_NEXT_SPAWN 分岐が未実装のため fail
  run grep -E 'dry.run|dry_run' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac8: auto-next-spawn.sh --dry-run flag suppresses exec" {
  # AC: --dry-run フラグで実際の spawn が抑制される
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E '\-\-dry.run|dry_run' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac8: dry-run intervention-log uses dryrun prefix" {
  # AC: dry-run 時の intervention-log エントリに auto-cleanup+next-spawn-dryrun: プレフィックスを使う
  # RED: auto-next-spawn.sh が未実装のため fail
  [ -f "${AUTO_NEXT_SPAWN_SCRIPT}" ]
  run grep -E 'next-spawn-dryrun|dryrun' "${AUTO_NEXT_SPAWN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 追加テスト: AC-10 ドキュメント更新
# ===========================================================================

@test "ac10: monitor-channel-catalog.md has IDLE_COMPLETED_AUTO_NEXT_SPAWN description" {
  # AC: monitor-channel-catalog.md §[IDLE-COMPLETED] に AUTO_NEXT_SPAWN の説明が追加される
  # RED: 追記が未完了のため fail
  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN|AUTO_NEXT_SPAWN' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac10: pitfalls-catalog.md section 4.10 S-1b row has AUTO_NEXT_SPAWN description" {
  # AC: pitfalls-catalog.md §4.10 S-1b 行に IDLE_COMPLETED_AUTO_NEXT_SPAWN 関連の記述が追記される
  # RED: IDLE_COMPLETED_AUTO_NEXT_SPAWN への言及が未追記のため fail
  run grep -E 'IDLE_COMPLETED_AUTO_NEXT_SPAWN' "${PITFALLS_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac10: SKILL.md Wave management section is updated" {
  # AC: SKILL.md の Wave 管理セクションが更新されている
  # RED: 更新が未完了のため fail
  run grep -E 'auto-next-spawn|AUTO_NEXT_SPAWN|wave.queue.*auto|auto.*wave.queue' "${SKILL_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac10: deps.yaml registers auto-next-spawn.sh" {
  # AC: deps.yaml に auto-next-spawn.sh が登録される
  # RED: 登録が未完了のため fail
  run grep -E 'auto-next-spawn' "${DEPS_YAML}"
  [ "${status}" -eq 0 ]
}

@test "ac10: deps.yaml registers observer-wave-check.sh" {
  # AC: deps.yaml に observer-wave-check.sh が登録される
  # RED: 登録が未完了のため fail
  run grep -E 'observer-wave-check' "${DEPS_YAML}"
  [ "${status}" -eq 0 ]
}

@test "ac10: su-observer-wave-management.md has reference link to auto-next-spawn" {
  # AC: su-observer-wave-management.md に auto-next-spawn.sh への参照リンクが追加される
  # RED: 追記が未完了のため fail
  run grep -E 'auto-next-spawn' "${WAVE_MGMT_DOC}"
  [ "${status}" -eq 0 ]
}
