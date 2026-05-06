#!/usr/bin/env bats
# wave-progress-watchdog.bats
#
# RED-phase tests for Issue #1432:
#   feat(su-observer): wave-progress-watchdog.sh — gh API polling fallback
#
# AC coverage:
#   AC1  - wave-progress-watchdog.sh に gh API polling 関数（poll_gh_api_fallback）追加、60s ループ
#   AC2  - gh api /repos/{owner}/{repo}/pulls?state=closed&per_page=100 で current_wave PR merge 状態取得
#   AC3  - events/ signal ファイルが存在する場合、Layer 3 polling を skip（duplicate fire 抑止）
#   AC4  - 全 current_wave PR が merged → auto-next-spawn.sh 呼び出し（lock は S3 共有ロック）
#   AC5  - ETag キャッシュ（If-None-Match header）活用、304 で query 消費回避
#   AC6  - rate-limit (HTTP 403 + X-RateLimit-Remaining: 0) → exponential backoff (60→120→240、cap 600)
#   AC7  - gh auth status 失敗時は polling skip + intervention-log.md に WARN 記録
#   AC8  - auto-next-spawn 起動時に wave-queue.json の current_wave を確認し Layer 1/2 と重複 spawn しない
#   AC9  - bats: events/ 不在 + 全 PR merged → auto-next-spawn が 1 回のみ呼ばれること
#   AC10 - bats: 403 rate-limit 応答時に exponential backoff が適用されること
#   AC11 - shellcheck pass
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${bats_dir}/../.." && pwd)"
  export REPO_ROOT

  WATCHDOG_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/wave-progress-watchdog.sh"
  AUTO_NEXT_SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/auto-next-spawn.sh"

  export WATCHDOG_SCRIPT AUTO_NEXT_SPAWN_SCRIPT

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST

  # テスト用 .supervisor ディレクトリ
  SUPERVISOR_DIR="${TMPDIR_TEST}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}/events"
  export SUPERVISOR_DIR

  # INTERVENTION_LOG パス
  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"
  export INTERVENTION_LOG

  # stub bin ディレクトリ（PATH 優先）
  STUB_BIN="${TMPDIR_TEST}/stub-bin"
  mkdir -p "${STUB_BIN}"
  export STUB_BIN

  _ORIGINAL_PATH="${PATH}"
  export PATH="${STUB_BIN}:${PATH}"

  # デフォルト wave-queue.json（current_wave=2）
  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'WAVE_EOF'
{
  "version": 1,
  "current_wave": 2,
  "queue": []
}
WAVE_EOF
}

teardown() {
  export PATH="${_ORIGINAL_PATH}"
  rm -rf "${TMPDIR_TEST}"
}

# ---------------------------------------------------------------------------
# Helper: stub_command <name> <body>
# ---------------------------------------------------------------------------
stub_command() {
  local name="$1"
  local body="${2:-exit 0}"
  cat > "${STUB_BIN}/${name}" <<STUB_EOF
#!/usr/bin/env bash
${body}
STUB_EOF
  chmod +x "${STUB_BIN}/${name}"
}

# ===========================================================================
# AC1: poll_gh_api_fallback 関数 + 60s ループ
# ===========================================================================

@test "ac1: wave-progress-watchdog.sh exists" {
  # AC: wave-progress-watchdog.sh が skills/su-observer/scripts/ に新規作成される
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
}

@test "ac1: wave-progress-watchdog.sh defines poll_gh_api_fallback function" {
  # AC: poll_gh_api_fallback 関数（または同等の polling 関数）が定義されている
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E '^poll_gh_api_fallback\(\)|^function poll_gh_api_fallback' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac1: wave-progress-watchdog.sh has 60 second polling interval" {
  # AC: ポーリングループが 60s 間隔で動作する設定を持つ
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -iE 'POLL_INTERVAL.*60|60.*POLL_INTERVAL|sleep.*60|GH_API_FALLBACK.*60|60.*GH_API' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac1: wave-progress-watchdog.sh has polling loop structure" {
  # AC: while ループまたは相当する繰り返し構造が存在する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E '^while |^  while ' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: gh api /repos/{owner}/{repo}/pulls?state=closed&per_page=100 呼び出し
# ===========================================================================

@test "ac2: wave-progress-watchdog.sh calls gh api with closed PRs endpoint" {
  # AC: gh api /repos/{owner}/{repo}/pulls?state=closed&per_page=100 を呼び出す
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'gh api.*pulls|/pulls\?' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-progress-watchdog.sh uses state=closed and per_page=100 parameters" {
  # AC: クエリパラメータが state=closed かつ per_page=100 である
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'state=closed|per_page=100' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: wave-progress-watchdog.sh reads current_wave from wave-queue.json" {
  # AC: wave-queue.json の current_wave フィールドを参照して WAVE_N を決定する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'current_wave|WAVE_N|wave_num|wave_number' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: poll_gh_api_fallback fetches merged status for current_wave PRs (stub test)" {
  # AC: poll_gh_api_fallback が current_wave に紐付く PR の merged_at を確認できる
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]

  # gh stub: wave=2 の PRs を返す（全て merged）
  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC2'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf '[{"number":10,"state":"closed","merged_at":"2024-01-01T00:00:00Z","title":"feat: wave2","body":"Closes #100"}]\n'
    exit 0 ;;
  *) exit 0 ;;
esac
GH_STUB_AC2
  chmod +x "${STUB_BIN}/gh"

  # --single-poll モードで実行（実装後はループを抜けるフラグを想定）
  run bash "${WATCHDOG_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --supervisor-dir "${SUPERVISOR_DIR}" \
    --single-poll
  # スクリプトが存在しないため fail（RED）
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: events/ signal ファイル存在時に Layer 3 polling を skip
# ===========================================================================

@test "ac3: wave-progress-watchdog.sh checks events/ signal files before polling" {
  # AC: .supervisor/events/wave-${WAVE_N}-pr-merged-*.json が存在する場合に skip する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'events/|signal.*file|wave-.*pr-merged|duplicate' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac3: wave-progress-watchdog.sh skips polling when signal file exists (stub test)" {
  # AC: signal ファイルが存在する場合、gh API polling を skip する（duplicate fire 抑止）
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]

  # signal ファイルを事前作成
  cat > "${SUPERVISOR_DIR}/events/wave-2-pr-merged-100.json" <<'SIGNAL_EOF'
{"event":"WAVE-PR-MERGED","wave":2,"issue":100}
SIGNAL_EOF

  # gh が呼ばれないことを確認（呼ばれたら fail するスタブ）
  stub_command "gh" '
  echo "ERROR: gh called despite signal file existing" >&2
  exit 1
  '

  run bash "${WATCHDOG_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --supervisor-dir "${SUPERVISOR_DIR}" \
    --single-poll
  # ファイル不在のため fail（RED）
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: 全 current_wave PR merged → auto-next-spawn.sh 呼び出し
# ===========================================================================

@test "ac4: wave-progress-watchdog.sh calls auto-next-spawn.sh when all PRs merged" {
  # AC: 全 current_wave PR が merged 確認後に auto-next-spawn.sh を呼び出す
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'auto-next-spawn|auto_next_spawn' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: auto-next-spawn is called with correct --queue and --triggered-by arguments" {
  # AC: auto-next-spawn.sh --queue .supervisor/wave-queue.json --triggered-by wave-progress-watchdog
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'triggered-by.*wave-progress-watchdog|wave-progress-watchdog.*triggered-by' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# AC9 相当: events/ 不在 + 全 PR merged → auto-next-spawn が 1 回のみ呼ばれる
@test "ac9: events/ absent + all PRs merged -> auto-next-spawn called exactly once" {
  # AC: AC9 — events/ 不在かつ全 current_wave PR merged 時に auto-next-spawn.sh が 1 回のみ呼ばれる
  # RED: wave-progress-watchdog.sh が存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]

  # events/ ディレクトリは空（signal ファイルなし）
  # wave-queue.json: current_wave=2, wave=2 の issues=[100] を含む
  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'WQ_EOF'
{
  "version": 1,
  "current_wave": 2,
  "queue": [
    {
      "wave": 2,
      "issues": [100],
      "spawn_cmd_argv": ["bash", "dummy.sh"],
      "depends_on_waves": [],
      "spawn_when": "all_current_wave_idle_completed"
    }
  ]
}
WQ_EOF

  # gh stub: PR #10 が wave=2 issue=100 で merged 済み（body に Closes #100）
  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC9'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf '[{"number":10,"state":"closed","merged_at":"2024-01-01T00:00:00Z","body":"Closes #100","head":{"ref":"feat/100-test"}}]\n'
    exit 0 ;;
  *) exit 0 ;;
esac
GH_STUB_AC9
  chmod +x "${STUB_BIN}/gh"

  # auto-next-spawn.sh の呼び出し回数を記録するスタブ
  SPAWN_CALL_LOG="${TMPDIR_TEST}/auto-next-spawn-calls.log"
  cat > "${STUB_BIN}/auto-next-spawn.sh" <<SPAWN_STUB
#!/usr/bin/env bash
echo "called: \$*" >> "${SPAWN_CALL_LOG}"
exit 0
SPAWN_STUB
  chmod +x "${STUB_BIN}/auto-next-spawn.sh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    AUTO_NEXT_SPAWN_SCRIPT="${STUB_BIN}/auto-next-spawn.sh" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  # auto-next-spawn が 1 回のみ呼ばれたことを確認
  [ -f "${SPAWN_CALL_LOG}" ]
  call_count=$(wc -l < "${SPAWN_CALL_LOG}")
  [ "${call_count}" -eq 1 ]
}

# ===========================================================================
# AC5: ETag キャッシュ（If-None-Match）活用、304 で query 消費回避
# ===========================================================================

@test "ac5: wave-progress-watchdog.sh uses ETag cache file for If-None-Match header" {
  # AC: ETag キャッシュファイル /tmp/.wave-watchdog-etag-${WAVE_N}.txt を使用する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'etag|ETag|If-None-Match|ETAG' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: etag cache file path is /tmp/.wave-watchdog-etag-WAVE_N.txt" {
  # AC: キャッシュファイルパスが /tmp/.wave-watchdog-etag-${WAVE_N}.txt である
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'wave-watchdog-etag|\.wave-watchdog-etag' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: 304 response skips query consumption (degradation to full poll on cache miss)" {
  # AC: 304 応答時はデータ再取得せず、キャッシュファイル消失時はフルポーリングに degradation する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E '304|not.*modified|NOT_MODIFIED|degradation|fallback.*full|full.*poll' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: rate-limit (403 + X-RateLimit-Remaining: 0) → exponential backoff
# ===========================================================================

@test "ac6: wave-progress-watchdog.sh detects HTTP 403 rate-limit response" {
  # AC: HTTP 403 + X-RateLimit-Remaining: 0 を rate-limit として検知する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'rate.limit|RateLimit|403|RATE_LIMIT' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac6: exponential backoff sequence is 60->120->240 with cap 600" {
  # AC: exponential backoff が 60s → 120s → 240s で cap 600s である
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'backoff|BACKOFF|cap.*600|600.*cap|240|exponential' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# AC10 相当: 403 rate-limit 応答時に exponential backoff が適用されること
@test "ac10: 403 rate-limit response triggers exponential backoff (stub test)" {
  # AC: AC10 — 403 rate-limit 応答時に polling 間隔が exponential backoff で延長される
  # RED: wave-progress-watchdog.sh が存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]

  # gh stub: 最初の呼び出しで 403 rate-limit を返す
  CALL_COUNT_FILE="${TMPDIR_TEST}/gh-call-count.txt"
  echo "0" > "${CALL_COUNT_FILE}"

  cat > "${STUB_BIN}/gh" <<GH_STUB_AC10
#!/usr/bin/env bash
count_file="${CALL_COUNT_FILE}"
case "\$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    count=\$(cat "\${count_file}" 2>/dev/null || echo 0)
    count=\$((count + 1))
    echo "\${count}" > "\${count_file}"
    if [ "\${count}" -le 1 ]; then
      echo '{"message":"API rate limit exceeded"}' >&2
      exit 5
    else
      printf '[]\n'
      exit 0
    fi
    ;;
  *) exit 0 ;;
esac
GH_STUB_AC10
  chmod +x "${STUB_BIN}/gh"

  # backoff ログファイルがスクリプト実行後に生成されることを期待
  BACKOFF_LOG="${SUPERVISOR_DIR}/backoff-applied.log"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  # backoff が適用されたログが残ること
  run grep -E 'backoff|rate.limit|RATE_LIMIT' "${SUPERVISOR_DIR}/intervention-log.md"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: gh auth status 失敗時 → polling skip + intervention-log WARN 記録
# ===========================================================================

@test "ac7: wave-progress-watchdog.sh checks gh auth status before polling" {
  # AC: gh auth status を実行し、失敗時は polling を skip する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'gh auth status|auth.*status|AUTH_STATUS' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac7: gh auth failure writes WARN to intervention-log.md (stub test)" {
  # AC: gh auth status 失敗時に intervention-log.md に WARN レコードを残す（daemon を crash させない）
  # RED: wave-progress-watchdog.sh が存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]

  # gh auth status を失敗させるスタブ
  stub_command "gh" '
  case "$*" in
    *"auth status"*)
      echo "Error: Not logged in" >&2
      exit 1 ;;
    *) exit 0 ;;
  esac
  '

  run env PATH="${STUB_BIN}:${PATH}" \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  # intervention-log に WARN が記録されていることを確認
  run grep -iE 'WARN.*auth|auth.*WARN|gh auth' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac7: gh auth failure does not crash daemon (exit 0)" {
  # AC: gh auth status 失敗時に daemon を crash させない（exit 0 で継続）
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'auth.*skip|skip.*auth|auth.*warn|WARN.*auth' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: auto-next-spawn 起動時に current_wave 確認、Layer 1/2 重複 spawn 防止
# ===========================================================================

@test "ac8: wave-progress-watchdog.sh verifies current_wave before calling auto-next-spawn" {
  # AC: auto-next-spawn 呼び出し前に wave-queue.json の current_wave を確認する
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'current_wave.*spawn|spawn.*current_wave|duplicate.*spawn|spawn.*duplicate' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac8: wave-progress-watchdog.sh prevents duplicate spawn when current_wave already advanced" {
  # AC: current_wave が既に次の wave に進んでいる場合は auto-next-spawn を呼ばない
  # RED: ファイルが存在しないため fail
  [ -f "${WATCHDOG_SCRIPT}" ]

  # wave-queue.json: current_wave=3（既に次の wave）
  cat > "${SUPERVISOR_DIR}/wave-queue.json" <<'WQ2_EOF'
{
  "version": 1,
  "current_wave": 3,
  "queue": []
}
WQ2_EOF

  # auto-next-spawn.sh の呼び出し記録スタブ
  SPAWN_CALL_LOG="${TMPDIR_TEST}/spawn-calls-ac8.log"
  cat > "${STUB_BIN}/auto-next-spawn.sh" <<SPAWN_STUB2
#!/usr/bin/env bash
echo "called: \$*" >> "${SPAWN_CALL_LOG}"
exit 0
SPAWN_STUB2
  chmod +x "${STUB_BIN}/auto-next-spawn.sh"

  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC8'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf '[{"number":10,"state":"closed","merged_at":"2024-01-01T00:00:00Z","body":"Closes #100"}]\n'
    exit 0 ;;
  *) exit 0 ;;
esac
GH_STUB_AC8
  chmod +x "${STUB_BIN}/gh"

  run env AUTO_NEXT_SPAWN="${STUB_BIN}/auto-next-spawn.sh" bash "${WATCHDOG_SCRIPT}" \
    --queue "${SUPERVISOR_DIR}/wave-queue.json" \
    --supervisor-dir "${SUPERVISOR_DIR}" \
    --target-wave 2 \
    --single-poll
  [ "${status}" -eq 0 ]

  # auto-next-spawn が呼ばれていないことを確認
  [ ! -f "${SPAWN_CALL_LOG}" ]
}

# ===========================================================================
# AC11: shellcheck pass
# ===========================================================================

@test "ac11: shellcheck passes on wave-progress-watchdog.sh" {
  [ -f "${WATCHDOG_SCRIPT}" ]
  if ! command -v shellcheck > /dev/null 2>&1; then
    skip "shellcheck not installed"
  fi
  run shellcheck "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac11: bash syntax check passes on wave-progress-watchdog.sh" {
  [ -f "${WATCHDOG_SCRIPT}" ]
  run bash -n "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}
