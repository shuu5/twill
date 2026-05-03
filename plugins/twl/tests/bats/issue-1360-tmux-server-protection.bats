#!/usr/bin/env bats
# issue-1360-tmux-server-protection.bats
#
# RED-phase tests for Issue #1360:
#   fix(incident): P0 incident — tmux server protected scope 対処
#     - tmux server 再発防止のための coredump 設定・strace runbook 整備
#     - issue-lifecycle-orchestrator.sh の kill-window 直後 sleep 1 挿入（10 箇所）
#     - tmux-safety-guard.sh への kill-window lint 追加
#     - tmux version 評価 runbook 整備（SIGSEGV/memory corruption fix 調査）
#     - wave-queue.schema.json の Wave resume 対象 Issue 列保持能力確認
#
# AC coverage:
#   AC-1  - coredump 設定手順 runbook が architecture/runbooks/ 配下に作成されている
#   AC-2  - strace long-running runbook が architecture/runbooks/ 配下に作成されている
#   AC-3a - observer 側 kill-window 直後に sleep 1 が既挿入（確認テスト）
#   AC-3b - issue-lifecycle-orchestrator.sh の 10 箇所全 kill-window 直後に sleep 1 が挿入されている
#   AC-3c - tmux-safety-guard.sh が存在し kill-window 直後 sleep 1 なし検出 lint を含む
#   AC-5a - architecture/runbooks/tmux-version-evaluation.md が作成されている
#   AC-5b - tmux-version-evaluation.md に ipatho-server-2 / thinkpad のバージョン情報が含まれる
#   AC-5c - upgrade 判定（migrate / 据え置き）が ADR または runbook に記録されている
#   AC-6a - wave-queue.schema.json の WaveEntry に Wave resume 対象 Issue を識別できるフィールドが存在する
#   AC-6b - tmux-twill.service 起動時 wave-queue hook 設計が ADR または design doc に記録されている
#   AC-6c - observer-auto-next-spawn.bats の AUTO_NEXT_SPAWN=0 パスが破壊されていない（既存テスト保全）
#
# 全テストは実装前（RED）状態で fail する（AC-3a は既適用のため GREEN）。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  ORCHESTRATOR="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  SAFETY_GUARD="${REPO_ROOT}/scripts/tmux-safety-guard.sh"
  WAVE_QUEUE_SCHEMA="${REPO_ROOT}/skills/su-observer/schemas/wave-queue.schema.json"
  ARCH_RUNBOOKS="${REPO_ROOT}/architecture/runbooks"
  COREDUMP_RUNBOOK="${ARCH_RUNBOOKS}/coredump-config.md"
  STRACE_RUNBOOK="${ARCH_RUNBOOKS}/tmux-strace-runbook.md"
  TMUX_VERSION_RUNBOOK="${ARCH_RUNBOOKS}/tmux-version-evaluation.md"
  OBSERVER_BATS="${REPO_ROOT}/tests/bats/observer-auto-next-spawn.bats"
  AUTOPILOT_ORCH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"

  export ORCHESTRATOR SAFETY_GUARD WAVE_QUEUE_SCHEMA ARCH_RUNBOOKS \
         COREDUMP_RUNBOOK STRACE_RUNBOOK TMUX_VERSION_RUNBOOK \
         OBSERVER_BATS AUTOPILOT_ORCH
}

# ===========================================================================
# AC-1: coredump 設定手順 runbook が作成されている
# ===========================================================================

@test "ac1: coredump runbook が architecture/runbooks/ 配下に存在する" {
  # AC: /etc/systemd/coredump.conf の Storage=external 等の設定手順を記録した runbook
  # RED: ファイルが未作成のため fail
  [ -f "${COREDUMP_RUNBOOK}" ]
}

@test "ac1: coredump runbook に coredump.conf または Storage=external への言及がある" {
  # RED: runbook が存在しないため fail
  run grep -qE 'coredump\.conf|Storage=external|coredumpctl' "${COREDUMP_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-2: strace long-running runbook が作成されている
# ===========================================================================

@test "ac2: strace runbook が architecture/runbooks/ 配下に存在する" {
  # AC: strace -f -p <tmux-server-pid> -o /var/log/tmux-trace.log の long-running 手順
  # RED: ファイルが未作成のため fail
  [ -f "${STRACE_RUNBOOK}" ]
}

@test "ac2: strace runbook に tmux-server-pid および strace コマンド例が含まれる" {
  # RED: runbook が存在しないため fail
  run grep -qE 'strace|tmux.*server.*pid|tmux-trace' "${STRACE_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3a: observer 側 kill-window 直後 sleep 1 既挿入（確認 — 既適用）
# ===========================================================================

@test "ac3a: autopilot-orchestrator.sh の kill-window 直後に sleep 1 が挿入されている" {
  # AC: observer 側 (autopilot-orchestrator.sh) は doobidoo hash 26cc074d で sleep 1 既挿入
  # RED: 実装フェーズで sleep 1 を挿入した後 GREEN になる
  # 空行をスキップして kill-window 直後の sleep 1 を確認
  run awk '/tmux kill-window.*window_name.*2>\/dev\/null.*true/{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${AUTOPILOT_ORCH}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-3b: issue-lifecycle-orchestrator.sh の 10 箇所 kill-window に sleep 1 挿入
# ===========================================================================

@test "ac3b: orchestrator の kill-window L372 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run awk 'NR==372{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L411 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run awk 'NR==411{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L562 直後に sleep 1 がある" {
  run awk 'NR==562{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L589 直後に sleep 1 がある" {
  run awk 'NR==589{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L595 直後に sleep 1 がある" {
  run awk 'NR==595{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L641 直後に sleep 1 がある" {
  run awk 'NR==641{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L712 直後に sleep 1 がある" {
  run awk 'NR==712{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L728 直後に sleep 1 がある" {
  run awk 'NR==728{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L753 直後に sleep 1 がある" {
  run awk 'NR==753{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window L792 直後に sleep 1 がある" {
  run awk 'NR==792{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{exit 0} found{exit 1}' \
    "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac3b: orchestrator の kill-window 全 10 箇所すべてに sleep 1 が挿入されている（集約確認）" {
  # kill-window 直後（空行スキップ）に sleep 1 がある箇所のカウントが 10 以上であることを確認
  local count
  count=$(awk '/tmux kill-window.*2>\/dev\/null.*true/{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{count++; found=0; next} found{found=0} END{print count+0}' \
    "${ORCHESTRATOR}")
  [ "${count}" -ge 10 ]
}

# ===========================================================================
# AC-3c: tmux-safety-guard.sh が存在し kill-window lint を含む
# ===========================================================================

@test "ac3c: tmux-safety-guard.sh が scripts/ 配下に存在する" {
  # RED: ファイルが未作成のため fail
  [ -f "${SAFETY_GUARD}" ]
}

@test "ac3c: tmux-safety-guard.sh に kill-window 直後 sleep 1 なし検出の lint ロジックが含まれる" {
  # RED: lint ロジックが未実装のため fail
  # kill-window と sleep 1 の組み合わせを検査するロジックを確認（広すぎるパターンを避ける）
  run grep -qE 'kill-window[^|]*sleep[[:space:]]*1|sleep[[:space:]]*1[^|]*kill-window|kill.window.*lint' "${SAFETY_GUARD}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-5a: tmux-version-evaluation.md が作成されている
# ===========================================================================

@test "ac5a: tmux-version-evaluation.md が architecture/runbooks/ 配下に存在する" {
  # AC: tmux 3.5/3.6 の SIGSEGV/memory corruption fix 一覧を記録
  # RED: ファイルが未作成のため fail
  [ -f "${TMUX_VERSION_RUNBOOK}" ]
}

@test "ac5a: tmux-version-evaluation.md に SIGSEGV または memory corruption への言及がある" {
  # RED: ファイルが存在しないため fail
  run grep -qiE 'SIGSEGV|memory.corruption|segfault|crash' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-5b: バージョン情報が runbook に記録されている
# ===========================================================================

@test "ac5b: tmux-version-evaluation.md に ipatho-server-2 のバージョン情報が含まれる" {
  # RED: ファイルが存在しないため fail
  run grep -qE 'ipatho|ipatho-server' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

@test "ac5b: tmux-version-evaluation.md に thinkpad のバージョン情報が含まれる" {
  # RED: ファイルが存在しないため fail
  run grep -qiE 'thinkpad|ThinkPad' "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-5c: upgrade 判定が記録されている
# ===========================================================================

@test "ac5c: tmux-version-evaluation.md に upgrade 判定（migrate または 据え置き）が記録されている" {
  # RED: ファイルが存在しないため fail
  run grep -qiE 'migrate|据え置き|upgrade.*判定|判定.*upgrade|no.*upgrade|アップグレード' \
    "${TMUX_VERSION_RUNBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-6a: wave-queue.schema.json に Wave resume 対象 Issue フィールドが存在する
# ===========================================================================

@test "ac6a: wave-queue.schema.json が存在する" {
  # NOTE: ファイルは存在する（#1155 で作成済）
  [ -f "${WAVE_QUEUE_SCHEMA}" ]
}

@test "ac6a: wave-queue.schema.json の WaveEntry に resume_issues または in_progress_issues フィールドが存在する" {
  # AC: Wave resume 対象 Issue 列を保持できるか検証
  # RED: 現スキーマは issues フィールドのみで resume 識別不可のため fail
  run grep -qE 'resume_issues|in_progress_issues|resume.*issues|paused_issues' \
    "${WAVE_QUEUE_SCHEMA}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-6b: tmux-twill.service wave-queue hook 設計が記録されている
# ===========================================================================

@test "ac6b: tmux-twill.service の wave-queue hook 設計が ADR または design doc に記録されている" {
  # RED: 設計文書が未作成のため fail
  run grep -rlE 'tmux-twill.*service.*wave-queue|wave-queue.*hook.*service|tmux.*resurrect.*wave' \
    "${REPO_ROOT}/architecture/"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC-6c: observer-auto-next-spawn.bats の AUTO_NEXT_SPAWN=0 パスが保全されている
# ===========================================================================

@test "ac6c: observer-auto-next-spawn.bats が存在し AUTO_NEXT_SPAWN=0 テストを含む" {
  # AC: AUTO_NEXT_SPAWN=0 / 未設定時の既存挙動を破らないこと
  # NOTE: 既存テストが存在するため GREEN
  [ -f "${OBSERVER_BATS}" ]
  run grep -qE 'AUTO_NEXT_SPAWN.*0|auto.next.spawn.*0|ac9.case1|case1' "${OBSERVER_BATS}"
  [ "${status}" -eq 0 ]
}
