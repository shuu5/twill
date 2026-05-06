#!/usr/bin/env bats
# wave-progress-watchdog-1446.bats
#
# RED-phase tests for Issue #1446:
#   tech-debt: wave-progress-watchdog — rate-limit detection via HTTP headers
#
# AC coverage:
#   AC1 - poll_gh_api_fallback が HTTP/.*403 + X-RateLimit-Remaining: 0 ヘッダで rate-limit を検知
#   AC2 - return 2 と exponential backoff (_gh_backoff) は変更されない
#   AC3 - 既存 ac6/ac10 テスト fixture が HTTP 403 + header 形式で PASS する（fixture 文字列置換のみ）
#   AC4 - 旧 grep -qiE 'rate limit|API rate|exceeded' パターンが削除されている
#   AC5 - rate-limit ヘッダなし gh 失敗時 → WARN ログ + return 0（daemon 継続）
#   AC7 - ヘッダ解析は header section（最初の空行まで）に限定

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${bats_dir}/../.." && pwd)"
  export REPO_ROOT

  WATCHDOG_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/wave-progress-watchdog.sh"
  export WATCHDOG_SCRIPT

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST

  SUPERVISOR_DIR="${TMPDIR_TEST}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}/events"
  export SUPERVISOR_DIR

  INTERVENTION_LOG="${SUPERVISOR_DIR}/intervention-log.md"
  export INTERVENTION_LOG

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

# ===========================================================================
# AC1: HTTP 403 + X-RateLimit-Remaining: 0 ヘッダで rate-limit 検知
# ===========================================================================

@test "ac1: HTTP 403 status line + x-ratelimit-remaining: 0 header triggers rate-limit (return 2)" {
  # AC: gh --include 形式のレスポンスで HTTP/.*403 かつ X-RateLimit-Remaining: 0 があれば return 2
  # RED: 現在の実装はエラーメッセージ文字列マッチのため、このヘッダ形式では検知しない
  [ -f "${WATCHDOG_SCRIPT}" ]

  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC1'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf 'HTTP/1.1 403 Forbidden\r\nx-ratelimit-limit: 60\r\nx-ratelimit-remaining: 0\r\nx-ratelimit-reset: 9999999999\r\n\r\n{"message":"Forbidden"}\n'
    exit 1 ;;
  *) exit 0 ;;
esac
GH_STUB_AC1
  chmod +x "${STUB_BIN}/gh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  # rate-limit 検知 → backoff ログが intervention-log に記録される
  run grep -iE 'rate.limit|backoff' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac1: implementation checks HTTP/.*403 pattern in response" {
  # AC: poll_gh_api_fallback が HTTP ステータスライン 403 を参照している
  # RED: 現在の実装は HTTP ステータスラインを参照していない
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'HTTP/.*403|HTTP.*403|grep.*403' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac1: implementation checks X-RateLimit-Remaining header in response" {
  # AC: poll_gh_api_fallback が X-RateLimit-Remaining ヘッダを参照している
  # RED: 現在の実装は X-RateLimit-Remaining を参照していない
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -iE 'X-RateLimit-Remaining|ratelimit.remaining|RateLimit.Remaining' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: return 2 と exponential backoff は変更されない
# ===========================================================================

@test "ac2: poll_gh_api_fallback still returns 2 on rate-limit detection" {
  # AC: rate-limit 検知時の戻り値 return 2 は変更されない
  # RED: rate-limit が検知されないため return 2 が発生しない（HTTP ヘッダ形式では）
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'return 2' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: _gh_backoff exponential doubling logic is preserved" {
  # AC: exponential backoff (_gh_backoff *= 2) の実装は変更されない
  # RED: 実装済み確認（現在は PASS → fixture 変更後も維持されることを保証）
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E '_gh_backoff.*\* 2|_gh_backoff=.*backoff.*\*|backoff.*\*.*2' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: 既存 ac6/ac10 fixture が HTTP 403 + header 形式で PASS すること
# ===========================================================================

@test "ac3: existing ac6 test passes with HTTP 403 + x-ratelimit-remaining: 0 fixture" {
  # AC: wave-progress-watchdog.bats ac6 系テストが HTTP ヘッダ fixture で PASS する
  # RED: 現在の実装では HTTP ヘッダ fixture ではなく error message に依存するため FAIL
  [ -f "${WATCHDOG_SCRIPT}" ]

  # ac6 相当: HTTP 403 + x-ratelimit-remaining: 0 を rate-limit として検知できること
  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC3_AC6'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf 'HTTP/1.1 403 Forbidden\r\nx-ratelimit-remaining: 0\r\n\r\n{}\n'
    exit 1 ;;
  *) exit 0 ;;
esac
GH_STUB_AC3_AC6
  chmod +x "${STUB_BIN}/gh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -iE 'rate.limit|backoff' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac3: existing ac10 test passes with HTTP 403 + x-ratelimit-remaining: 0 fixture" {
  # AC: wave-progress-watchdog.bats ac10 系テストが HTTP ヘッダ fixture で PASS する
  # RED: 現在の実装は error message テキストに依存するため、ヘッダ形式では FAIL
  [ -f "${WATCHDOG_SCRIPT}" ]

  CALL_COUNT_FILE="${TMPDIR_TEST}/gh-call-count.txt"
  echo "0" > "${CALL_COUNT_FILE}"

  cat > "${STUB_BIN}/gh" <<GH_STUB_AC3_AC10
#!/usr/bin/env bash
count_file="${CALL_COUNT_FILE}"
case "\$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    count=\$(cat "\${count_file}" 2>/dev/null || echo 0)
    count=\$((count + 1))
    echo "\${count}" > "\${count_file}"
    if [ "\${count}" -le 1 ]; then
      printf 'HTTP/1.1 403 Forbidden\r\nx-ratelimit-remaining: 0\r\n\r\n{}\n'
      exit 1
    else
      printf '[]\n'
      exit 0
    fi
    ;;
  *) exit 0 ;;
esac
GH_STUB_AC3_AC10
  chmod +x "${STUB_BIN}/gh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -iE 'rate.limit|backoff' "${INTERVENTION_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: 旧エラーメッセージマッチが削除されている
# ===========================================================================

@test "ac4: old grep -qiE 'rate limit|API rate|exceeded' pattern is removed" {
  # AC: エラーメッセージ文字列マッチ (rate limit|API rate|exceeded) が削除されている
  # RED: 現在の実装にはこのパターンが存在する
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E "grep.*rate.limit|grep.*API.rate|grep.*exceeded" "${WATCHDOG_SCRIPT}"
  # パターンが存在しないこと（grep が何もマッチしない = status 1 が期待値）
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC5: rate-limit ヘッダなし gh 失敗 → WARN + return 0
# ===========================================================================

@test "ac5: non-rate-limit gh failure produces WARN and returns 0 (daemon continues)" {
  # AC: HTTP 403 + RateLimit ヘッダなしの gh 失敗は WARN + return 0 で daemon を継続
  # RED: 現在の実装は error message がなければ return 0 を返すため PASS する
  #      (ただし実装後も同動作を維持していることを保証するため残す)
  [ -f "${WATCHDOG_SCRIPT}" ]

  # 汎用エラー（rate-limit ヘッダなし）
  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC5'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf 'HTTP/1.1 500 Internal Server Error\r\n\r\n{"message":"server error"}\n'
    exit 1 ;;
  *) exit 0 ;;
esac
GH_STUB_AC5
  chmod +x "${STUB_BIN}/gh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  # daemon は crash せず exit 0
  [ "${status}" -eq 0 ]

  # rate-limit によるバックオフが記録されていないこと
  if [ -f "${INTERVENTION_LOG}" ]; then
    run grep -iE 'rate.limit.*backoff|backoff.*rate.limit' "${INTERVENTION_LOG}"
    [ "${status}" -ne 0 ]
  fi
}

@test "ac5: gh api failure without rate-limit headers keeps daemon running" {
  # AC: rate-limit ヘッダなし非ゼロ exit は WARN ログのみ + return 0
  # RED: 現在は error message マッチがなければ return 0 するが、HTTP ヘッダ実装後も同様に動作すること
  [ -f "${WATCHDOG_SCRIPT}" ]
  run grep -E 'WARN.*gh.api.failed|gh.*api.*failed.*WARN' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: ヘッダ解析は header section のみ（JSON body の誤検知防止）
# ===========================================================================

@test "ac7: 'rate limit' text in JSON body does NOT trigger rate-limit detection" {
  # AC: JSON body 内の rate limit 文字列では rate-limit 判定しない
  # RED: 現在の実装は body の文字列もマッチするため false positive が発生する
  [ -f "${WATCHDOG_SCRIPT}" ]

  # HTTP 403 + RateLimit ヘッダなし（500エラー）だが body に "rate limit" テキストあり
  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC7'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf 'HTTP/1.1 500 Internal Server Error\r\ncontent-type: application/json\r\n\r\n{"message":"API rate limit exceeded for upstream service"}\n'
    exit 1 ;;
  *) exit 0 ;;
esac
GH_STUB_AC7
  chmod +x "${STUB_BIN}/gh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  # body の "API rate limit exceeded" テキストが false positive を起こさないこと
  # rate-limit backoff が記録されていないことを確認
  if [ -f "${INTERVENTION_LOG}" ]; then
    run grep -iE 'rate.limit.*backoff|backoff.*rate.limit' "${INTERVENTION_LOG}"
    [ "${status}" -ne 0 ]
  fi
}

@test "ac7: implementation limits header parsing to section before blank line" {
  # AC: ヘッダ解析が最初の空行までに限定されている
  # RED: 現在の実装にはヘッダセクション限定ロジックがない
  [ -f "${WATCHDOG_SCRIPT}" ]
  # awk '/^$/{exit}' または head -n で空行前を取得するパターンがある
  run grep -E 'awk.*\^\$|head.*-n|sed.*blank|header.*section|split.*header' "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac7: HTTP 403 without x-ratelimit-remaining: 0 does NOT trigger rate-limit" {
  # AC: HTTP 403 でも X-RateLimit-Remaining: 0 がない場合は rate-limit 判定しない
  # RED: 現在の実装はヘッダ確認をしていないため、HTTP 403 単体での制御は未実装
  [ -f "${WATCHDOG_SCRIPT}" ]

  # HTTP 403 だが RateLimit ヘッダなし（一般的な認証エラー等）
  cat > "${STUB_BIN}/gh" <<'GH_STUB_AC7_403ONLY'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"api"*"pulls"*)
    printf 'HTTP/1.1 403 Forbidden\r\ncontent-type: application/json\r\n\r\n{"message":"Resource not accessible by integration"}\n'
    exit 1 ;;
  *) exit 0 ;;
esac
GH_STUB_AC7_403ONLY
  chmod +x "${STUB_BIN}/gh"

  run env \
    WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
    WAVE_QUEUE_FILE="${SUPERVISOR_DIR}/wave-queue.json" \
    SUPERVISOR_DIR="${SUPERVISOR_DIR}" \
    GH_API_FALLBACK_INTERVAL_SEC=1 \
    POLL_INTERVAL_SEC=1 \
    SINGLE_POLL_TEST_MODE=1 \
    bash "${WATCHDOG_SCRIPT}"
  [ "${status}" -eq 0 ]

  # rate-limit として判定されないこと（backoff ログなし）
  if [ -f "${INTERVENTION_LOG}" ]; then
    run grep -iE 'rate.limit.*backoff|backoff.*rate.limit' "${INTERVENTION_LOG}"
    [ "${status}" -ne 0 ]
  fi
}
