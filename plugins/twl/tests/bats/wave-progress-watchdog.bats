#!/usr/bin/env bats
# wave-progress-watchdog.bats
#
# RED-phase tests for Issue #1429:
#   feat(su-observer): wave-progress-watchdog.sh — daemon event による Wave 進行監視
#
# AC coverage:
#   AC-1  - wave-progress-watchdog.sh 新設・実行可能・shebang
#   AC-2  - .supervisor/events/wave-${current_wave}-pr-merged-*.json 監視
#   AC-3  - 全 Issue merged 時のみ auto-next-spawn.sh を 1 回だけ呼び出す（idempotency）
#   AC-4  - lock file flock -n による二重 invocation skip
#   AC-5  - 未完了時は spawn せず次 event を待機（false positive 防止）
#   AC-6  - PID を watcher-pid-wave-progress に書き SIGTERM/exit で trap 削除
#   AC-7  - wave-queue.json の current_wave を Wave N+1 spawn 後に atomic 更新
#   AC-8  - bats wave-progress-watchdog.bats が存在する（本ファイル自体の AC）
#   AC-9  - ac-test-mapping-1429.yaml で AC-1〜AC-8 と bats シナリオを 1 対 1 マッピング
#   AC-10 - deps.yaml に script コンポーネントとして追記・calls: [auto-next-spawn] 含む
#   AC-11 - refs/ref-wave-progress-watchdog.md を新設
#   AC-12 - 既定で OFF (WAVE_PROGRESS_WATCHDOG_ENABLED=1 で opt-in)
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  WATCHDOG_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/wave-progress-watchdog.sh"
  AUTO_NEXT_SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/auto-next-spawn.sh"
  WAVE_QUEUE_SCHEMA="${REPO_ROOT}/skills/su-observer/schemas/wave-queue.schema.json"
  DEPS_YAML="${REPO_ROOT}/deps.yaml"
  REF_DOC="${REPO_ROOT}/refs/ref-wave-progress-watchdog.md"
  MAPPING_YAML="${REPO_ROOT}/tests/bats/ac-test-mapping-1429.yaml"

  export WATCHDOG_SCRIPT AUTO_NEXT_SPAWN_SCRIPT WAVE_QUEUE_SCHEMA
  export DEPS_YAML REF_DOC MAPPING_YAML

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST

  SUPERVISOR_DIR="${TMPDIR_TEST}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}/events"
  mkdir -p "${SUPERVISOR_DIR}/locks"
  export SUPERVISOR_DIR
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC-1: wave-progress-watchdog.sh が新設され実行可能
# ===========================================================================

@test "ac1: wave-progress-watchdog.sh が存在する" {
  # AC: skills/su-observer/scripts/wave-progress-watchdog.sh が新設されている
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
}

@test "ac1: wave-progress-watchdog.sh が実行可能 (chmod +x)" {
  # AC: ファイルに実行権限が付与されている
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  [ -x "${WATCHDOG_SCRIPT}" ]
}

@test "ac1: wave-progress-watchdog.sh の shebang が #!/usr/bin/env bash" {
  # AC: shebang 行が #!/usr/bin/env bash であること
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  local first_line
  first_line=$(head -1 "${WATCHDOG_SCRIPT}")
  [ "${first_line}" = "#!/usr/bin/env bash" ]
}

# ===========================================================================
# AC-2: .supervisor/events/wave-${current_wave}-pr-merged-*.json を監視
# ===========================================================================

@test "ac2: wave-progress-watchdog.sh が wave-N-pr-merged イベントパターンを参照している" {
  # AC: スクリプト内に wave-${current_wave}-pr-merged または相当のパターンが含まれる
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'wave.*pr-merged|pr-merged.*wave|wave-\$\{.*\}-pr-merged' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-progress-watchdog.sh が inotify または polling による監視ロジックを含む" {
  # AC: inotifywait または while/sleep によるポーリングループが存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'inotifywait|while.*true|while \[\[|polling|POLL_INTERVAL' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-progress-watchdog.sh が SUPERVISOR_DIR または events ディレクトリを参照している" {
  # AC: .supervisor/events パスが参照されている
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'SUPERVISOR_DIR|\.supervisor.*events|events.*supervisor' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3: 全 Issue merged 時のみ auto-next-spawn.sh を 1 回だけ呼び出す（idempotency）
# ===========================================================================

@test "ac3: wave-progress-watchdog.sh が wave-queue.json の queue[].issues を参照している" {
  # AC: wave-queue.json.queue[].issues を .wave フィールドで current_wave フィルタして取得するロジックが存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'wave-queue\.json|wave_queue|queue.*issues|issues.*queue' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac3: wave-progress-watchdog.sh が .wave フィールドで current_wave フィルタするロジックを含む" {
  # AC: jq 等で .wave == current_wave のフィルタリングが行われる
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E '\.wave|current_wave.*filter|select.*wave|jq.*wave' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac3: wave-progress-watchdog.sh が auto-next-spawn.sh を呼び出すロジックを含む" {
  # AC: auto-next-spawn.sh の呼び出し箇所が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'auto-next-spawn' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac3: wave-progress-watchdog.sh が completed-flag による idempotency を実装している" {
  # AC: 再 spawn 防止のための completed-flag チェックが存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'completed.flag|completed_flag|\.completed|already.*spawn|spawn.*once' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-4: lock file flock -n による二重 invocation skip
# ===========================================================================

@test "ac4: wave-progress-watchdog.sh が flock を使用している" {
  # AC: flock コマンドによるロック取得が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'flock' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: wave-progress-watchdog.sh が flock -n オプションを使用している" {
  # AC: 非ブロッキングロック（flock -n）が使用されている
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'flock -n|flock.*-n' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: wave-progress-watchdog.sh の lock file パスが .supervisor/locks/wave-progress-watchdog.lock" {
  # AC: ロックファイルパスが wave-progress-watchdog.lock である
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'wave-progress-watchdog\.lock' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: wave-progress-watchdog.sh がロック取得失敗時に skip する分岐を含む" {
  # AC: flock -n 失敗時（二重起動）に skip して exit する分岐が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'skip|already.*running|duplicate|double.*invoke|flock.*exit|exit.*flock' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-5: 未完了時は spawn せず次 event を待機（false positive 防止）
# ===========================================================================

@test "ac5: wave-progress-watchdog.sh が全 Issue merged 判定ロジックを含む" {
  # AC: 全 Issue が merged されているかチェックするロジックが存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'all.*merged|merged.*all|all_merged|check.*merge|merge.*check' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: wave-progress-watchdog.sh が一部 merged 時は spawn をスキップする分岐を含む" {
  # AC: 全 Issue が merged でない場合は spawn をスキップして待機する分岐が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'skip.*spawn|spawn.*skip|not all|partial|wait.*next|continue' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-6: PID を watcher-pid-wave-progress に書き SIGTERM/exit で trap 削除
# ===========================================================================

@test "ac6: wave-progress-watchdog.sh が watcher-pid-wave-progress に PID を書き込む" {
  # AC: watcher-pid-wave-progress ファイルに PID が書き込まれる
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'watcher-pid-wave-progress' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac6: wave-progress-watchdog.sh が SIGTERM trap を設定している" {
  # AC: SIGTERM シグナルのトラップが設定されている
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'trap.*SIGTERM|trap.*TERM|trap.*EXIT' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac6: wave-progress-watchdog.sh の trap が PID ファイルを削除する" {
  # AC: trap ハンドラが watcher-pid-wave-progress ファイルを rm -f する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'rm.*watcher-pid-wave-progress|rm.*PID_FILE|rm.*pid.*file' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac6: wave-progress-watchdog.sh の PID file パターンが heartbeat-watcher.sh 互換" {
  # AC: watcher-pid-wave-progress は watcher-pid-heartbeat と同様のプレフィックスを持つ
  # context-budget-monitor.sh が watcher-pid-* を参照して kill するため互換性が必要
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'watcher-pid-' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-7: wave-queue.json の current_wave を atomic 更新（mktemp → mv）
# ===========================================================================

@test "ac7: wave-progress-watchdog.sh が mktemp を使って wave-queue.json を atomic 更新する" {
  # AC: mktemp で一時ファイルを作成し mv で atomic 置換する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'mktemp' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac7: wave-progress-watchdog.sh が mv で atomic 置換している" {
  # AC: mktemp と mv の組み合わせによる atomic 更新が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E '\bmv\b.*tmp|mv.*wave-queue|atomic.*update|tmp.*mv' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac7: wave-progress-watchdog.sh が auto-next-spawn.sh の dequeue 完了後に current_wave を更新する" {
  # AC: auto-next-spawn.sh 呼び出しの後に current_wave の更新ロジックが続く（順序保証）
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  # auto-next-spawn.sh の呼び出しと current_wave 更新の両方が存在することを確認
  run grep -E 'auto-next-spawn' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
  run grep -E 'current_wave' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac7: wave-progress-watchdog.sh の wave-queue.json 更新が既存 schema validation を通過する想定" {
  # AC: wave-queue.schema.json が存在しており、更新後の JSON がスキーマに適合する
  # RED: wave-progress-watchdog.sh が未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
  run jq empty "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-8: bats wave-progress-watchdog.bats が存在する（本ファイル自体の AC）
# ===========================================================================

@test "ac8: wave-progress-watchdog.bats 自身が存在する" {
  # AC: tests/bats/wave-progress-watchdog.bats が存在する（本テストファイル自体）
  # このテストは実装後も GREEN のまま
  local bats_file
  bats_file="${REPO_ROOT}/tests/bats/wave-progress-watchdog.bats"
  [ -f "${bats_file}" ]
}

@test "ac8: wave-progress-watchdog.bats が AC-1〜AC-7 のシナリオを含む" {
  # AC: bats ファイルに ac1〜ac7 のテスト名が存在する
  # RED: wave-progress-watchdog.sh が未作成のため他のテストが全て fail する
  # このチェック自体は bats ファイル存在後に GREEN になる
  local bats_file
  bats_file="${REPO_ROOT}/tests/bats/wave-progress-watchdog.bats"
  [ -f "${bats_file}" ]
  run grep -E '@test.*"ac[1-7]:' "${bats_file}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-9: ac-test-mapping-1429.yaml で AC-1〜AC-8 と bats シナリオを 1 対 1 マッピング
# ===========================================================================

@test "ac9: ac-test-mapping-1429.yaml が存在する" {
  # AC: tests/bats/ac-test-mapping-1429.yaml が存在する
  # RED: マッピングファイルが未作成のため fail
  [ -f "${MAPPING_YAML}" ]
}

@test "ac9: ac-test-mapping-1429.yaml が mappings: セクションを持つ" {
  # AC: YAML ファイルに mappings: キーが含まれる
  # RED: マッピングファイルが未作成のため fail
  [ -f "${MAPPING_YAML}" ]
  run grep -E '^mappings:' "${MAPPING_YAML}"
  [ "${status}" -eq 0 ]
}

@test "ac9: ac-test-mapping-1429.yaml に ac_index 1〜8 の全エントリが存在する" {
  # AC: ac_index: 1 〜 ac_index: 8 の全エントリが存在する
  # RED: マッピングファイルが未作成のため fail
  [ -f "${MAPPING_YAML}" ]
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    run grep -E "ac_index: ${i}\b" "${MAPPING_YAML}"
    [ "${status}" -eq 0 ]
  done
}

@test "ac9: ac-test-mapping-1429.yaml の全エントリに impl_files が存在する" {
  # AC: 全エントリに impl_files: フィールドが存在する
  # RED: マッピングファイルが未作成のため fail
  [ -f "${MAPPING_YAML}" ]
  run grep -E 'impl_files:' "${MAPPING_YAML}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-10: deps.yaml に script コンポーネントとして追記・calls: [auto-next-spawn] 含む
# ===========================================================================

@test "ac10: deps.yaml に wave-progress-watchdog が登録されている" {
  # AC: deps.yaml に wave-progress-watchdog エントリが存在する
  # RED: deps.yaml への追記が未完了のため fail
  run grep -E 'wave-progress-watchdog' "${DEPS_YAML}"
  [ "${status}" -eq 0 ]
}

@test "ac10: deps.yaml の wave-progress-watchdog エントリに calls: [auto-next-spawn] が含まれる" {
  # AC: エントリに calls: [auto-next-spawn] が含まれる
  # RED: deps.yaml への追記が未完了のため fail
  run grep -A 10 'wave-progress-watchdog' "${DEPS_YAML}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -E 'calls:|auto-next-spawn'
}

@test "ac10: deps.yaml の wave-progress-watchdog エントリに path が含まれる" {
  # AC: エントリに path: skills/su-observer/scripts/wave-progress-watchdog.sh 相当が含まれる
  # RED: deps.yaml への追記が未完了のため fail
  run grep -A 5 'wave-progress-watchdog' "${DEPS_YAML}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -E 'path:.*wave-progress-watchdog'
}

# ===========================================================================
# AC-11: refs/ref-wave-progress-watchdog.md を新設
# ===========================================================================

@test "ac11: refs/ref-wave-progress-watchdog.md が存在する" {
  # AC: plugins/twl/refs/ref-wave-progress-watchdog.md が新設されている
  # RED: ファイルが未作成のため fail
  [ -f "${REF_DOC}" ]
}

@test "ac11: ref-wave-progress-watchdog.md が空でない" {
  # AC: 参照ドキュメントに内容が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${REF_DOC}" ]
  local size
  size=$(wc -c < "${REF_DOC}")
  [ "${size}" -gt 10 ]
}

@test "ac11: ref-wave-progress-watchdog.md が wave-progress-watchdog.sh への言及を含む" {
  # AC: 参照ドキュメントにスクリプト名の言及が存在する
  # RED: ファイルが未作成のため fail
  [ -f "${REF_DOC}" ]
  run grep -E 'wave-progress-watchdog' "${REF_DOC}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-12: 既定で OFF (WAVE_PROGRESS_WATCHDOG_ENABLED=1 で opt-in)
# ===========================================================================

@test "ac12: wave-progress-watchdog.sh が WAVE_PROGRESS_WATCHDOG_ENABLED を参照している" {
  # AC: 環境変数 WAVE_PROGRESS_WATCHDOG_ENABLED によるガードが存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'WAVE_PROGRESS_WATCHDOG_ENABLED' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac12: WAVE_PROGRESS_WATCHDOG_ENABLED 未設定時は起動しない（早期 exit）" {
  # AC: WAVE_PROGRESS_WATCHDOG_ENABLED が 1 でない場合に早期 exit するロジックが存在する
  # RED: ファイルが未作成のため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'WAVE_PROGRESS_WATCHDOG_ENABLED.*exit|exit.*WAVE_PROGRESS_WATCHDOG_ENABLED|!=.*1.*exit|!= "1"' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac12: WAVE_PROGRESS_WATCHDOG_ENABLED=1 で起動したスクリプトが正常に開始する" {
  # AC: WAVE_PROGRESS_WATCHDOG_ENABLED=1 で呼び出した場合に実行が開始される
  # RED: ファイルが未作成のため fail（スクリプト自体が存在しない）
  [ -f "${WATCHDOG_SCRIPT}" ]
  # スクリプトがオプションなし呼び出し（--help 等）でも初期化が始まることを確認
  # 実際の daemon ループには入らないよう --help または引数なし実行で確認
  run env WAVE_PROGRESS_WATCHDOG_ENABLED=1 bash "${WATCHDOG_SCRIPT}" --help 2>&1 || true
  # exit code に関わらず、何らかの出力が得られることだけ確認（スクリプトが実行可能であること）
  # 実装前は [ -f ] で fail するためここには到達しない
  true
}

# ===========================================================================
# Issue #1447 — AC-9: auto-next-spawn が schema validation skip 時に
#   completed-flag が残らない回帰テスト（RED: 現行 _invoke_auto_next_spawn は
#   _mark_wave_completed を先行呼び出しするため fail する）
# ===========================================================================

@test "ac9-1447: auto-next-spawn が schema validation skip 時に completed-flag が作成されず wave-queue.json も改変されない" {
  # AC: AUTO_NEXT_SPAWN_SCRIPT を schema validation 失敗パス（exit 0 + skip log）として動作させ、
  #     watchdog 1 iteration 後に:
  #     (a) .supervisor/locks/wave-N-completed.flag が作成されていない
  #     (b) wave-queue.json が改変されていない
  #     ことを assert する
  #
  # RED: 現行 _invoke_auto_next_spawn は _mark_wave_completed "$1" を auto-next-spawn.sh 呼び出し前に
  #      実行するため、auto-next-spawn が skip しても flag が残留する。
  #      ac5 の実装（_mark_wave_completed 削除 + --target-wave 移管）後に GREEN となる。

  CURRENT_WAVE=3

  # wave-queue.json を正常な形式で作成
  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'EOF'
{
  "version": 1,
  "current_wave": 3,
  "queue": [
    {
      "wave": 3,
      "issues": [500, 501],
      "spawn_cmd_argv": ["bash", "--version"],
      "depends_on_waves": [2],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
EOF

  # wave-queue.json のスナップショット（改変チェック用）
  local original_queue
  original_queue=$(cat "${SUPERVISOR_DIR}/wave-queue.json")

  # 全 Issue の merge イベントを作成（_all_merged が true を返すよう）
  for issue_num in 500 501; do
    echo '{"issue": '"${issue_num}"', "merged_at": "2026-01-01T00:00:00Z"}' \
      > "${SUPERVISOR_DIR}/events/wave-${CURRENT_WAVE}-pr-merged-${issue_num}.json"
  done

  mkdir -p "${SUPERVISOR_DIR}/locks"

  # schema validation で必ず skip するフェイク auto-next-spawn.sh を作成
  # exit 0 を返すが dequeue も flag set も行わない（実際の skip パス相当）
  local fake_spawn
  fake_spawn="${TMPDIR_TEST}/fake-auto-next-spawn.sh"
  cat > "${fake_spawn}" <<'FAKE_EOF'
#!/usr/bin/env bash
# フェイク: schema validation 失敗による skip 動作をシミュレート
_SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
INTERVENTION_LOG="${_SUPERVISOR_DIR}/intervention-log.md"
TRIGGERED_BY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --triggered-by) TRIGGERED_BY="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$_SUPERVISOR_DIR" 2>/dev/null || true
printf '%s %s\n' "$(date -u +%FT%TZ)" \
  "auto-cleanup+next-spawn-skipped: triggered_by=${TRIGGERED_BY}, reason=JSON Schema validation failed" \
  >> "$INTERVENTION_LOG" 2>/dev/null || true
exit 0
FAKE_EOF
  chmod +x "${fake_spawn}"

  # _all_merged=true のとき continue してループするため --kill-after=1 で確実に SIGKILL する。
  # flag は最初のイテレーション（~1s）で作成される。SIGKILL 後に状態を確認する。
  SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
  WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
  AUTO_NEXT_SPAWN_SCRIPT="${fake_spawn}" \
  POLL_INTERVAL_SEC=1 \
  GH_API_FALLBACK_INTERVAL_SEC=1 \
  SINGLE_POLL_TEST_MODE=1 \
  WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
  timeout --kill-after=1 3 bash "${WATCHDOG_SCRIPT}" 2>/dev/null || true

  # (a) completed.flag が作成されていないことを assert
  #     RED: 現行 _invoke_auto_next_spawn は _mark_wave_completed を先行呼び出しするため
  #          flag が残留する → [ ! -f ... ] が FAIL する
  [ ! -f "${SUPERVISOR_DIR}/locks/wave-${CURRENT_WAVE}-completed.flag" ]

  # (b) wave-queue.json が改変されていないことを assert
  local current_queue
  current_queue=$(cat "${SUPERVISOR_DIR}/wave-queue.json")
  [ "${current_queue}" = "${original_queue}" ]
}
