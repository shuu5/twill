#!/usr/bin/env bats
# worker-code-reviewer-tmux-1143.bats - Verify Issue #1143:
# worker-code-reviewer.md に tmux 破壊的操作のターゲット解決ルールが追加されること
# RED: tmux bullet はまだ存在しないため全テストが FAIL する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  REVIEWER="${REPO_ROOT}/agents/worker-code-reviewer.md"
  AGENTS_DIR="${REPO_ROOT}/agents"
  export REPO_ROOT REVIEWER AGENTS_DIR
}

# ===========================================================================
# AC1: worker-code-reviewer.md の §2 バグパターンに tmux bullet が追加される
# ===========================================================================

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet exists in worker-code-reviewer.md" {
  [ -f "${REVIEWER}" ]
  grep -qE 'tmux.*kill-window|kill-window.*tmux|tmux.*kill-session|kill-session.*tmux' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'CRITICAL'" {
  [ -f "${REVIEWER}" ]
  grep -qE 'tmux.*CRITICAL|CRITICAL.*tmux' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions confidence >= 90 in tmux context" {
  [ -f "${REVIEWER}" ]
  # tmux bullet 内（tmux kill-window と同一行または近傍）に confidence >= 90 が含まれること
  # awk で tmux が含まれる行から5行以内に confidence >=90 または ≥ 90 があるか確認
  local found
  found=$(awk '/tmux.*kill-window|kill-window.*tmux|tmux.*kill-session|respawn-window/ {
    for (i = NR; i <= NR+5; i++) buf[i] = 1
  }
  (NR in buf) && /confidence.*90|≥ 90|>= 90/ { found=1 }
  END { print found+0 }' "${REVIEWER}")
  [ "${found}" -eq 1 ]
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'kill-window' and 'kill-session'" {
  [ -f "${REVIEWER}" ]
  grep -qE 'kill-window' "${REVIEWER}"
  grep -qE 'kill-session' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'respawn-window'" {
  [ -f "${REVIEWER}" ]
  grep -qE 'respawn-window' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'window_name' or '#{window_name}'" {
  [ -f "${REVIEWER}" ]
  grep -qE 'window_name|#\{window_name\}' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'ambiguous target' or '誤 kill'" {
  [ -f "${REVIEWER}" ]
  grep -qE 'ambiguous target|誤 kill|誤kill' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'list-windows' resolution" {
  [ -f "${REVIEWER}" ]
  grep -qE 'list-windows' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet mentions 'session:index' format" {
  [ -f "${REVIEWER}" ]
  grep -qE 'session:index|session_name.*window_index|#{session_name}' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet references pitfalls-catalog §4.11" {
  [ -f "${REVIEWER}" ]
  grep -qE '§4\.11|4\.11.*tmux|pitfalls.*4\.11' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet references §4.9 or Issue #948" {
  [ -f "${REVIEWER}" ]
  grep -qE '§4\.9|4\.9.*has-session|#948|Issue.*948' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet references tmux-resolve.sh or _resolve_window_target" {
  [ -f "${REVIEWER}" ]
  grep -qE 'tmux-resolve\.sh|_resolve_window_target' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet references Issue #1142" {
  [ -f "${REVIEWER}" ]
  grep -qE '#1142|Issue.*1142' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet appears inside §2 バグパターン section" {
  [ -f "${REVIEWER}" ]
  local section2_start false_pos_line tmux_line
  section2_start=$(grep -n '^### 2\. バグパターン' "${REVIEWER}" | head -1 | cut -d: -f1)
  [ -n "${section2_start}" ]
  false_pos_line=$(grep -n '^\*\*False-positive 除外ルール' "${REVIEWER}" | head -1 | cut -d: -f1)
  [ -n "${false_pos_line}" ]
  tmux_line=$(grep -n 'tmux.*破壊的操作\|tmux.*kill-window\|kill-window.*tmux' "${REVIEWER}" | head -1 | cut -d: -f1)
  [ -n "${tmux_line}" ]
  # tmux bullet は §2 開始後かつ False-positive ブロック直前に存在する
  [ "${tmux_line}" -gt "${section2_start}" ]
  [ "${tmux_line}" -lt "${false_pos_line}" ]
}

@test "worker-code-reviewer-tmux-1143: AC1 tmux bullet appears after '競合状態の可能性' bullet" {
  [ -f "${REVIEWER}" ]
  local race_line tmux_line
  race_line=$(grep -n '競合状態の可能性' "${REVIEWER}" | head -1 | cut -d: -f1)
  [ -n "${race_line}" ]
  tmux_line=$(grep -n 'tmux.*破壊的操作\|tmux.*kill-window\|kill-window.*tmux' "${REVIEWER}" | head -1 | cut -d: -f1)
  [ -n "${tmux_line}" ]
  [ "${tmux_line}" -gt "${race_line}" ]
}

# ===========================================================================
# AC3: specialist regression — 既存 False-positive 除外ルールと矛盾しない
# ===========================================================================

@test "worker-code-reviewer-tmux-1143: AC3 False-positive 除外ルール still present" {
  [ -f "${REVIEWER}" ]
  grep -qF 'False-positive 除外ルール（純粋 boolean 変数の条件式順序差）' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC3 False-positive rule content intact" {
  [ -f "${REVIEWER}" ]
  grep -qE '純粋な boolean 変数・フラグ同士の比較|副作用のない純粋な boolean' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC3 False-positive rule intact — INFO level mention" {
  [ -f "${REVIEWER}" ]
  grep -qE 'INFO.*スタイル提案|INFO（スタイル提案）' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC3 existing-behavior-preserve section still present" {
  [ -f "${REVIEWER}" ]
  grep -qE 'existing-behavior-preserve|既存動作の維持条件' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC3 §2 section heading unchanged" {
  [ -f "${REVIEWER}" ]
  grep -qF '### 2. バグパターン' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC3 output format JSON schema section still present" {
  [ -f "${REVIEWER}" ]
  grep -qE '"status".*PASS.*WARN.*FAIL|出力形式.*MUST' "${REVIEWER}"
}

# ===========================================================================
# AC4: 他ファイルは変更しない
# - worker-codex-reviewer.md は変更対象外
# - issue-critic.md は変更対象外
# - issue-feasibility.md は変更対象外
# ===========================================================================

@test "worker-code-reviewer-tmux-1143: AC4 worker-codex-reviewer.md does not contain tmux §4.11 bullet" {
  local codex_reviewer="${AGENTS_DIR}/worker-codex-reviewer.md"
  [ -f "${codex_reviewer}" ]
  # worker-codex-reviewer.md は tmux bullet の追加対象外
  # このテストは AC4 の「他ファイルは変更しない」の逆検証:
  # もし誤って codex-reviewer にも追記されていたら、AC4 違反として fail させる。
  # ただし RED フェーズでは未実装なので、このテストは「codex-reviewer に追記がない」ことを確認する。
  # 実装後も codex-reviewer に tmux §4.11 専用 bullet が追加されていないことを保証する。
  run grep -cE '§4\.11.*tmux.*破壊的操作のターゲット解決|tmux.*破壊的操作のターゲット解決.*§4\.11' "${codex_reviewer}"
  [ "${output}" = "0" ]
}

@test "worker-code-reviewer-tmux-1143: AC4 issue-critic.md does not contain tmux §4.11 bullet" {
  local critic="${AGENTS_DIR}/issue-critic.md"
  [ -f "${critic}" ]
  run grep -cE '§4\.11.*tmux.*破壊的操作のターゲット解決|tmux.*破壊的操作のターゲット解決.*§4\.11' "${critic}"
  [ "${output}" = "0" ]
}

@test "worker-code-reviewer-tmux-1143: AC4 issue-feasibility.md does not contain tmux §4.11 bullet" {
  local feasibility="${AGENTS_DIR}/issue-feasibility.md"
  [ -f "${feasibility}" ]
  run grep -cE '§4\.11.*tmux.*破壊的操作のターゲット解決|tmux.*破壊的操作のターゲット解決.*§4\.11' "${feasibility}"
  [ "${output}" = "0" ]
}

# ===========================================================================
# AC5: ドキュメント整合性
# ===========================================================================

@test "worker-code-reviewer-tmux-1143: AC5 worker-code-reviewer.md contains §4.11 reference" {
  [ -f "${REVIEWER}" ]
  grep -qE '§4\.11' "${REVIEWER}"
}

@test "worker-code-reviewer-tmux-1143: AC5 twl check --deps-integrity passes" {
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity"
  [ "${status}" -eq 0 ]
}
