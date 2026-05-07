#!/usr/bin/env bats
# ac-scaffold-tests-1481.bats
#
# Issue #1481: tech-debt(autopilot): worker-codex-reviewer dispatch を deterministic 化
# (5/1以降 出力ゼロ問題)
#
# RED: 実装前は全テスト fail
# GREEN: 実装後に PASS

load 'helpers/common'

# ---------------------------------------------------------------------------
# テスト対象スクリプトへの絶対パス
# NOTE: chain-runner.sh, merge-gate-check-spawn.sh, specialist-audit.sh には
#   set -euo pipefail があるため source 直接実行に注意。
#   grep/cat ベースで静的検査を行うアプローチを基本とする。
# ---------------------------------------------------------------------------

SCRIPTS_DIR=""
ADR_FILE=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  ADR_FILE="${REPO_ROOT}/architecture/decisions/ADR-022-chain-ssot-boundary.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: post-fix-verify / merge-gate を runner step に分割
#       chain-runner.sh が pr-review-manifest.sh を実行し manifest 各行に対し
#       claude --print --agent twl:worker-codex-reviewer 等で deterministic spawn
#
# RED: 現在 post-fix-verify は dispatch_mode: llm、runner ロジック未実装
# GREEN: dispatch_mode: runner に変更、runner spawn ロジック実装後 PASS
# ===========================================================================

@test "ac1a: deps.yaml の post-fix-verify に dispatch_mode: runner が存在する" {
  # AC: post-fix-verify を deterministic runner step に変更
  # RED: 現在 dispatch_mode: llm のため grep fail
  local deps_yaml="${REPO_ROOT}/deps.yaml"
  run bash -c "
    in_section=0
    while IFS= read -r line; do
      if echo \"\$line\" | grep -q 'post-fix-verify:'; then
        in_section=1
      fi
      if [[ \$in_section -eq 1 ]] && echo \"\$line\" | grep -q 'dispatch_mode:'; then
        echo \"\$line\" | grep -q 'runner' && exit 0
        exit 1
      fi
    done < \"${deps_yaml}\"
    exit 1
  "
  assert_success
}

@test "ac1b: chain-runner.sh に post-fix-verify 用 pr-review-manifest.sh 呼び出しロジックが存在する" {
  # AC: chain-runner.sh が pr-review-manifest.sh を実行する runner ロジックを持つ
  # RED: 現在 chain-runner.sh に post-fix-verify 向け pr-review-manifest 呼び出しが存在しない
  run grep -qE "post-fix-verify.*pr-review-manifest|pr-review-manifest.*post-fix-verify" \
    "${SCRIPTS_DIR}/chain-runner.sh"
  assert_success
}

@test "ac1c: chain-runner.sh に claude --print --agent.*worker-codex-reviewer spawn パターンが存在する" {
  # AC: manifest 各行に対し claude --print --agent twl:worker-codex-reviewer で deterministic spawn
  # RED: 現在 chain-runner.sh に worker-codex-reviewer への deterministic spawn ロジックが存在しない
  run grep -qE 'claude[[:space:]].*--print[[:space:]].*--agent[[:space:]].*worker-codex-reviewer' \
    "${SCRIPTS_DIR}/chain-runner.sh"
  assert_success
}

# ===========================================================================
# AC-2: SPAWNED_FILE 自己申告 path を deprecate
#       merge-gate-check-spawn.sh を JSONL findings.yaml 存在ベース判定へ
#
# RED: 現在 SPAWNED_FILE + comm -23 パターンが残存、findings.yaml 判定が未実装
# GREEN: SPAWNED_FILE 参照が削除され findings.yaml 存在確認ロジックが追加後 PASS
# ===========================================================================

@test "ac2a: merge-gate-check-spawn.sh が SPAWNED_FILE 参照を持たない（deprecate 済み）" {
  # AC: SPAWNED_FILE 自己申告 path を deprecate
  # RED: 現在 SPAWNED_FILE 参照が残存しているため grep が成功 → assert_failure が fail
  run grep -qF 'SPAWNED_FILE' "${SCRIPTS_DIR}/merge-gate-check-spawn.sh"
  assert_failure
}

@test "ac2b: merge-gate-check-spawn.sh が comm -23 + SPAWNED_FILE パターンを持たない" {
  # AC: LLM 自己申告ベースの comm -23 判定を削除
  # RED: 現在 comm -23 + SPAWNED_FILE パターンが残存しているため grep が成功 → assert_failure が fail
  run bash -c "grep -q 'comm -23' \"${SCRIPTS_DIR}/merge-gate-check-spawn.sh\" && \
    grep -q 'SPAWNED_FILE' \"${SCRIPTS_DIR}/merge-gate-check-spawn.sh\""
  assert_failure
}

@test "ac2c: merge-gate-check-spawn.sh が findings.yaml 存在確認ロジックを持つ" {
  # AC: findings.yaml 存在ベース判定に切り替え
  # RED: 現在 findings.yaml 存在確認ロジックが未実装のため grep fail
  run grep -qF 'findings.yaml' "${SCRIPTS_DIR}/merge-gate-check-spawn.sh"
  assert_success
}

# ===========================================================================
# AC-3: codex_available=YES なのに findings.yaml に worker-codex-reviewer reason
#       記録なし → HARD FAIL
#
# RED: 現在 specialist-audit.sh は CODEX_TOTAL=0（findings.yaml なし）の場合
#      何もチェックしない → HARD FAIL しないため exit 0 → テスト fail
# GREEN: HARD FAIL ロジック実装後 PASS
# ===========================================================================

@test "ac3a: merge-gate-check-spawn.sh または specialist-audit.sh に codex_available + no-reason = HARD FAIL ロジックが存在する" {
  # AC: codex_available=YES かつ findings.yaml に worker-codex-reviewer reason なし → HARD FAIL
  # RED: 現在どちらのスクリプトにも CODEX_TOTAL=0 時の HARD FAIL ロジックが存在しない
  run bash -c "grep -qE 'HARD.FAIL|codex_available.*no.reason|no.reason.*codex_available|CODEX_TOTAL.*0.*FAIL|FAIL.*CODEX_TOTAL.*0' \
    \"${SCRIPTS_DIR}/merge-gate-check-spawn.sh\" \"${SCRIPTS_DIR}/specialist-audit.sh\" 2>/dev/null"
  assert_success
}

@test "ac3b: codex_available=YES 環境で findings.yaml に worker-codex-reviewer reason なし → exit 1" {
  # AC: codex_available=YES かつ findings.yaml に reason なし → HARD FAIL（exit 1）
  # RED: 現在 specialist-audit.sh は CODEX_TOTAL=0 の場合チェックしないため exit 0

  # フィクスチャ準備: codex_available を YES にスタブ化
  stub_command "codex" 'echo "logged in"'

  # findings.yaml に worker-codex-reviewer エントリはあるが reason: フィールドなし
  local issue_dir
  issue_dir="$(mktemp -d)"
  local session_dir="${issue_dir}/session"
  mkdir -p "${session_dir}"
  cat > "${session_dir}/findings.yaml" <<'FINDINGS_EOF'
- specialist: worker-codex-reviewer
  status: complete
FINDINGS_EOF

  # JSONL フィクスチャ（worker-codex-reviewer が actual_specialists に含まれる）
  local jsonl_file="${issue_dir}/test.jsonl"
  printf '{"step":"merge-gate","actual_specialists":["worker-codex-reviewer"]}\n' > "${jsonl_file}"

  # specialist-audit.sh を --codex-session-dir 付きで実行
  # CODEX_TOTAL=1 かつ reason: なし → silent_skip 率 100% → FAIL が期待されるが
  # 現在の実装は findings.yaml に worker-codex-reviewer が全くない（CODEX_TOTAL=0）場合
  # HARD FAIL しない問題を検証する別シナリオ:
  # findings.yaml が全く存在しない（CODEX_TOTAL=0）かつ codex_available → HARD FAIL すべき
  local no_findings_dir
  no_findings_dir="$(mktemp -d)"

  run bash "${SCRIPTS_DIR}/specialist-audit.sh" \
    --jsonl "${jsonl_file}" \
    --codex-session-dir "${no_findings_dir}" \
    --mode merge-gate 2>/dev/null

  rm -rf "${issue_dir}" "${no_findings_dir}"

  # RED: 現在は CODEX_TOTAL=0 の場合 HARD FAIL しないため exit 0 → assert_failure が fail
  assert_failure
}

# ===========================================================================
# AC-4: ADR-017 / ADR-022 整合性ドキュメント更新
#       ADR-022 に deterministic dispatch に関する記述を追加
#
# RED: 現在 ADR-022 に "deterministic" dispatch に関する記述が存在しない
# GREEN: 記述追加後 PASS
# ===========================================================================

@test "ac4a: ADR-022 に deterministic dispatch に関する記述が存在する" {
  # AC: ADR-022 (chain SSoT) に deterministic dispatch の整合性が記述されている
  # RED: 現在 ADR-022 に "deterministic" キーワードが存在しない
  run grep -qi "deterministic" "${ADR_FILE}"
  assert_success
}

@test "ac4b: ADR-022 に post-fix-verify の deterministic dispatch への変更が具体的に記述されている" {
  # AC: ADR-022 が post-fix-verify を runner step に変更することを明記している
  # RED: 現在 ADR-022 に "post-fix-verify" と "deterministic" が同一コンテキストで存在しない
  run grep -qi "post-fix-verify.*deterministic\|deterministic.*post-fix-verify" "${ADR_FILE}"
  assert_success
}

# ===========================================================================
# AC-5: regression test: 1 wave 完走させ全 specialist の OUT/ ファイル生成を BATS で検証
#       merge-gate-check-spawn.sh または specialist-audit.sh が
#       .controller-issue/ 以下の OUT/ ファイル存在確認ロジックを持つ
#
# RED: 現在どちらのスクリプトにも OUT/ ファイル存在確認ロジックが存在しない
# GREEN: OUT/ ファイル存在確認ロジック実装後 PASS
# ===========================================================================

@test "ac5a: merge-gate-check-spawn.sh または specialist-audit.sh が OUT/ ファイル存在確認ロジックを持つ" {
  # AC: 全 specialist の OUT/ ファイル生成を検証するロジックが存在する
  # RED: 現在どちらのスクリプトにも OUT/ ファイル確認ロジックが存在しない
  run bash -c "grep -qE '/OUT/|OUT/[^/]' \
    \"${SCRIPTS_DIR}/merge-gate-check-spawn.sh\" \
    \"${SCRIPTS_DIR}/specialist-audit.sh\" 2>/dev/null"
  assert_success
}

@test "ac5b: specialist-audit.sh が OUT/ ファイル存在確認に必要な --controller-issue-dir オプションを持つ" {
  # AC: specialist-audit.sh が --controller-issue-dir 等のオプションで OUT/ ファイル確認を行う
  # RED: 現在 specialist-audit.sh に --controller-issue-dir / OUT/ 確認ロジックが存在しない
  # --controller-issue-dir が存在しないためヘルプに含まれない → grep fail
  run grep -qF 'controller-issue-dir' "${SCRIPTS_DIR}/specialist-audit.sh"
  assert_success
}
