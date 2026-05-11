#!/usr/bin/env bats
# issue-1360-tmux-server-protection.bats
#
# GREEN-phase tests for Issue #1360:
#   P0 incident — tmux server protected scope crash + service-based recovery.
#
# AC coverage (updated for ADR-042 centralized approach):
#   AC-1  - coredump 設定手順 runbook が architecture/runbooks/coredump-config.md に存在
#   AC-2  - strace long-running runbook が architecture/runbooks/tmux-strace-runbook.md に存在
#   AC-3a - safe_kill_window ヘルパー本体に sleep 挿入（19 caller 全保護）
#   AC-3b - 集中化済 (#1385) のため orchestrator 内に直接 kill-window 呼び出しが残存しない
#   AC-3c - tmux-safety-guard.sh が scripts/ 配下に存在し L-1/L-2 lint を含む
#   AC-3d - bats regression test (orchestrator-kill-window-sleep.bats) が存在
#   AC-5a - tmux-version-evaluation.md が architecture/runbooks/ に存在
#   AC-5b - runbook に ipatho-server-2 / thinkpad のバージョン情報枠が含まれる
#   AC-5c - runbook に upgrade 判定（migrate / 据え置き）が記録されている
#   AC-6a - wave-queue.schema.json の WaveEntry に in_progress_issues / resume_issues フィールドあり
#   AC-6b - ADR-042 (tmux-twill.service wave-queue hook 設計) が存在
#   AC-6c - observer-auto-next-spawn.bats の AUTO_NEXT_SPAWN=0 パスが保全されている
#
# 実装ファイル参照:
#   - plugins/twl/scripts/lib/tmux-window-kill.sh (AC-3a)
#   - plugins/twl/scripts/tmux-safety-guard.sh (AC-3c)
#   - plugins/twl/architecture/runbooks/*.md (AC-1, AC-2, AC-5)
#   - plugins/twl/architecture/decisions/ADR-042-*.md (AC-6b)
#   - plugins/twl/skills/su-observer/schemas/wave-queue.schema.json (AC-6a)

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SAFE_KILL_HELPER="${REPO_ROOT}/scripts/lib/tmux-window-kill.sh"
  SAFETY_GUARD="${REPO_ROOT}/scripts/tmux-safety-guard.sh"
  WAVE_QUEUE_SCHEMA="${REPO_ROOT}/skills/su-observer/schemas/wave-queue.schema.json"
  ARCH_RUNBOOKS="${REPO_ROOT}/architecture/runbooks"
  COREDUMP_RUNBOOK="${ARCH_RUNBOOKS}/coredump-config.md"
  STRACE_RUNBOOK="${ARCH_RUNBOOKS}/tmux-strace-runbook.md"
  TMUX_VERSION_RUNBOOK="${ARCH_RUNBOOKS}/tmux-version-evaluation.md"
  ADR_042="${REPO_ROOT}/architecture/decisions/ADR-042-tmux-crash-recovery-wave-resume.md"
  OBSERVER_BATS="${REPO_ROOT}/tests/bats/observer-auto-next-spawn.bats"
  ORCHESTRATOR="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  AUTOPILOT_ORCH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"

  export SAFE_KILL_HELPER SAFETY_GUARD WAVE_QUEUE_SCHEMA ARCH_RUNBOOKS \
         COREDUMP_RUNBOOK STRACE_RUNBOOK TMUX_VERSION_RUNBOOK ADR_042 \
         OBSERVER_BATS ORCHESTRATOR AUTOPILOT_ORCH
}

# ===========================================================================
# AC-1: coredump 設定手順 runbook が作成されている
# ===========================================================================

@test "ac1: coredump runbook が architecture/runbooks/ 配下に存在する" {
  [ -f "${COREDUMP_RUNBOOK}" ]
}

@test "ac1: coredump runbook に coredump.conf / Storage=external / coredumpctl 言及あり" {
  run grep -qE 'coredump\.conf|Storage=external|coredumpctl' "${COREDUMP_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-2: strace long-running runbook が作成されている
# ===========================================================================

@test "ac2: strace runbook が architecture/runbooks/ 配下に存在する" {
  [ -f "${STRACE_RUNBOOK}" ]
}

@test "ac2: strace runbook に tmux server PID + strace 例が含まれる" {
  run grep -qE 'strace|TMUX_PID|tmux.*server|tmux-trace' "${STRACE_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3a: safe_kill_window ヘルパー本体に sleep が挿入されている
# ===========================================================================

@test "ac3a: safe_kill_window ヘルパーが存在する" {
  [ -f "${SAFE_KILL_HELPER}" ]
}

@test "ac3a: safe_kill_window 内に tmux kill-window 直後の sleep がある" {
  # kill-window と sleep の両方が含まれていることを検証
  run grep -qE 'tmux[[:space:]]+kill-window' "${SAFE_KILL_HELPER}"
  [ "${status}" -eq 0 ]
  run grep -qE 'sleep[[:space:]]+("?\$\{?SAFE_KILL_WINDOW_SLEEP|[0-9])' "${SAFE_KILL_HELPER}"
  [ "${status}" -eq 0 ]
}

@test "ac3a: safe_kill_window が SAFE_KILL_WINDOW_SLEEP 環境変数経由で無効化可能" {
  # default 1秒、テスト用に 0 で無効化可能であることを保証
  run grep -qE 'SAFE_KILL_WINDOW_SLEEP:-1' "${SAFE_KILL_HELPER}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3b: orchestrator 内に直接 kill-window 呼び出しが残存しない（#1385 集中化）
# ===========================================================================

@test "ac3b: issue-lifecycle-orchestrator.sh に tmux kill-window 直接呼び出しなし" {
  # 集中化されたヘルパー safe_kill_window 経由のみであること
  run grep -E 'tmux[[:space:]]+kill-window' "${ORCHESTRATOR}"
  [ "${status}" -ne 0 ]  # grep が何もマッチしないことが期待
}

@test "ac3b: autopilot-orchestrator.sh に tmux kill-window 直接呼び出しなし" {
  run grep -E 'tmux[[:space:]]+kill-window' "${AUTOPILOT_ORCH}"
  [ "${status}" -ne 0 ]
}

@test "ac3b: orchestrator が safe_kill_window 経由で kill する（caller 確認）" {
  run grep -qE 'safe_kill_window' "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3c: tmux-safety-guard.sh が存在し L-1/L-2 lint を含む
# ===========================================================================

@test "ac3c: tmux-safety-guard.sh が scripts/ 配下に存在する" {
  [ -f "${SAFETY_GUARD}" ]
}

@test "ac3c: tmux-safety-guard.sh が L-1 (direct kill-window 検出) lint を含む" {
  run grep -qE 'L-1|tmux[[:space:]]+kill-window' "${SAFETY_GUARD}"
  [ "${status}" -eq 0 ]
}

@test "ac3c: tmux-safety-guard.sh が L-2 (helper sleep 検証) lint を含む" {
  run grep -qE 'L-2|SAFE_KILL_WINDOW_SLEEP|sleep' "${SAFETY_GUARD}"
  [ "${status}" -eq 0 ]
}

@test "ac3c: tmux-safety-guard.sh が exit code で violation を返す" {
  # 実行して PASS することを確認（実装が正しいことを保証）
  run bash "${SAFETY_GUARD}" --quiet
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3d: bats regression test (orchestrator-kill-window-sleep.bats) が存在
# ===========================================================================

@test "ac3d: orchestrator-kill-window-sleep.bats が存在する" {
  [ -f "${REPO_ROOT}/tests/bats/scripts/orchestrator-kill-window-sleep.bats" ]
}

# ===========================================================================
# AC-5a: tmux-version-evaluation.md が作成されている
# ===========================================================================

@test "ac5a: tmux-version-evaluation.md が architecture/runbooks/ 配下に存在する" {
  [ -f "${TMUX_VERSION_RUNBOOK}" ]
}

@test "ac5a: tmux-version-evaluation.md に SIGSEGV / memory corruption / crash 言及あり" {
  run grep -qiE 'SIGSEGV|memory.corruption|segfault|crash' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-5b: ホスト別バージョン情報が runbook に含まれる
# ===========================================================================

@test "ac5b: tmux-version-evaluation.md に ipatho-server-2 の言及あり" {
  run grep -qE 'ipatho|ipatho-server' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

@test "ac5b: tmux-version-evaluation.md に thinkpad の言及あり" {
  run grep -qiE 'thinkpad|ThinkPad' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

@test "ac5b: tmux-version-evaluation.md に tmux 3.4 (現バージョン) の記録あり" {
  run grep -qE 'tmux[[:space:]]+3\.4' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-5c: upgrade 判定が記録されている
# ===========================================================================

@test "ac5c: tmux-version-evaluation.md に upgrade 判定（migrate または 据え置き）が記録されている" {
  run grep -qiE 'migrate|据え置き|defer|upgrade.*判定|判定.*upgrade|no.*upgrade' \
    "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-6a: wave-queue.schema.json に resume target Issue フィールドが存在
# ===========================================================================

@test "ac6a: wave-queue.schema.json が存在する" {
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
}

@test "ac6a: wave-queue.schema.json の WaveEntry に in_progress_issues または resume_issues フィールドあり" {
  run grep -qE 'resume_issues|in_progress_issues|resume.*issues|paused_issues' \
    "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

@test "ac6a: wave-queue.schema.json が valid JSON であり additionalProperties: false が保持されている" {
  # JSON 妥当性確認
  run python3 -c "import json; json.load(open('${WAVE_QUEUE_SCHEMA}'))"
  [ "${status}" -eq 0 ]
  # additionalProperties: false が両レイヤーに残っている
  count=$(grep -cE '"additionalProperties":[[:space:]]*false' "${WAVE_QUEUE_SCHEMA}")
  [ "${count}" -ge 2 ]
}

# ===========================================================================
# AC-6b: ADR-042 (tmux-twill.service wave-queue hook 設計) が記録されている
# ===========================================================================

@test "ac6b: ADR-042 が architecture/decisions/ 配下に存在する" {
  [ -f "${ADR_042}" ]
}

@test "ac6b: ADR-042 に tmux-twill.service の wave-queue hook 設計が記録されている" {
  run grep -qE 'tmux-twill.*service|wave-queue.*hook|wave.*resume|tmux.*resurrect' \
    "${ADR_042}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-6c: observer-auto-next-spawn.bats の AUTO_NEXT_SPAWN=0 パスが保全されている
# ===========================================================================

@test "ac6c: observer-auto-next-spawn.bats が存在し AUTO_NEXT_SPAWN=0 テストを含む" {
  [ -f "${OBSERVER_BATS}" ]
  run grep -qE 'AUTO_NEXT_SPAWN.*0|auto.next.spawn.*0|ac9.case1|case1' "${OBSERVER_BATS}"
  [ "${status}" -eq 0 ]
}
