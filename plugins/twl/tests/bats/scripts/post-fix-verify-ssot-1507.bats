#!/usr/bin/env bats
# post-fix-verify-ssot-1507.bats
#
# Issue #1507: tech-debt: post-fix-verify chain.py SSOT 未登録
#
# AC-1: chain.py の CHAIN_STEPS リストに post-fix-verify が含まれる
# AC-2: chain.py の CHAIN_STEP_DISPATCH で post-fix-verify の dispatch mode が runner
# AC-3: chain-steps.sh の CHAIN_STEP_DISPATCH に post-fix-verify が含まれ、値が runner
# AC-4: deps.yaml の post-fix-verify エントリと chain.py の設定が一致する
#       (twl check --deps-integrity が PASS に相当)
# AC-5: step_post_fix_verify が codex_available=YES 時に worker-codex-reviewer を spawn する
# AC-6: step_post_fix_verify が agent に <review_target> と <target_files> を渡す
# AC-7: step_post_fix_verify が findings.yaml と checkpoint を生成する
# AC-8: merge-gate-check-spawn.sh が specialist-audit.sh に --codex-session-dir と
#       --controller-issue-dir を渡す
# AC-9: specialist-audit.sh が codex_available=YES かつ findings.yaml 不在の場合に
#       HARD FAIL する (exit 1 + "HARD FAIL" メッセージ)
#
# RED フェーズ:
#   実装前のため全テストが FAIL することを意図している。
#   実装完了後に GREEN に変わる。

load '../helpers/common'

CHAIN_PY=""
CHAIN_STEPS_SH=""
DEPS_YAML=""
CHAIN_RUNNER_SH=""
MERGE_GATE_SPAWN_SH=""
AUDIT_SH=""

setup() {
  common_setup
  CHAIN_PY="$REPO_ROOT/../../cli/twl/src/twl/autopilot/chain.py"
  CHAIN_STEPS_SH="$REPO_ROOT/scripts/chain-steps.sh"
  DEPS_YAML="$REPO_ROOT/deps.yaml"
  CHAIN_RUNNER_SH="$SANDBOX/scripts/chain-runner.sh"
  MERGE_GATE_SPAWN_SH="$SANDBOX/scripts/merge-gate-check-spawn.sh"
  AUDIT_SH="$SANDBOX/scripts/specialist-audit.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: chain.py の CHAIN_STEPS リストに post-fix-verify が含まれる
# ---------------------------------------------------------------------------

@test "ac1: chain.py CHAIN_STEPS に post-fix-verify が含まれる" {
  # AC: chain.py の CHAIN_STEPS リストに post-fix-verify が含まれる
  # RED: 現状の CHAIN_STEPS に post-fix-verify が存在しないため FAIL
  [[ -f "$CHAIN_PY" ]] || {
    echo "FAIL: chain.py が見つかりません: ${CHAIN_PY}" >&2
    return 1
  }
  # CHAIN_STEPS リストブロック内に post-fix-verify が含まれること
  # ブロック境界: CHAIN_STEPS: list[str] = [ ... ] の範囲
  grep -A60 "^CHAIN_STEPS: list" "$CHAIN_PY" | grep -qF '"post-fix-verify"'
}

# ---------------------------------------------------------------------------
# AC-2: chain.py の CHAIN_STEP_DISPATCH で post-fix-verify の dispatch mode が runner
# ---------------------------------------------------------------------------

@test "ac2: chain.py CHAIN_STEP_DISPATCH に post-fix-verify の dispatch mode runner が含まれる" {
  # AC: chain.py の CHAIN_STEP_DISPATCH で post-fix-verify の dispatch mode が runner
  # RED: 現状の CHAIN_STEP_DISPATCH に post-fix-verify エントリが存在しないため FAIL
  [[ -f "$CHAIN_PY" ]] || {
    echo "FAIL: chain.py が見つかりません: ${CHAIN_PY}" >&2
    return 1
  }
  # CHAIN_STEP_DISPATCH ブロック内に "post-fix-verify": "runner" が含まれること
  grep -A60 "^CHAIN_STEP_DISPATCH: dict" "$CHAIN_PY" | grep -qF '"post-fix-verify": "runner"'
}

# ---------------------------------------------------------------------------
# AC-3: chain-steps.sh の CHAIN_STEP_DISPATCH に post-fix-verify が含まれ、値が runner
# ---------------------------------------------------------------------------

@test "ac3: chain-steps.sh の CHAIN_STEPS 配列に post-fix-verify が含まれる" {
  # AC: chain-steps.sh の CHAIN_STEP_DISPATCH に post-fix-verify が含まれ、値が runner
  # RED: chain-steps.sh は chain.py と同期されておらず post-fix-verify が存在しないため FAIL
  [[ -f "$CHAIN_STEPS_SH" ]] || {
    echo "FAIL: chain-steps.sh が見つかりません: ${CHAIN_STEPS_SH}" >&2
    return 1
  }
  grep -qF "post-fix-verify" "$CHAIN_STEPS_SH"
}

@test "ac3: chain-steps.sh の CHAIN_STEP_DISPATCH に post-fix-verify の dispatch mode runner が含まれる" {
  # AC: chain-steps.sh の CHAIN_STEP_DISPATCH で post-fix-verify の値が runner
  # RED: chain-steps.sh に post-fix-verify エントリが存在しないため FAIL
  [[ -f "$CHAIN_STEPS_SH" ]] || {
    echo "FAIL: chain-steps.sh が見つかりません: ${CHAIN_STEPS_SH}" >&2
    return 1
  }
  grep -qF "[post-fix-verify]=runner" "$CHAIN_STEPS_SH"
}

# ---------------------------------------------------------------------------
# AC-4: deps.yaml の post-fix-verify エントリと chain.py の設定が一致する
# ---------------------------------------------------------------------------

@test "ac4: deps.yaml に post-fix-verify エントリが存在する" {
  # AC: deps.yaml の post-fix-verify エントリと chain.py の設定が一致する
  # RED: deps.yaml と chain.py の整合性チェックが PASS することを確認する
  #      現状 chain.py に post-fix-verify が未登録のため FAIL
  [[ -f "$DEPS_YAML" ]] || {
    echo "FAIL: deps.yaml が見つかりません: ${DEPS_YAML}" >&2
    return 1
  }
  # deps.yaml に post-fix-verify セクションが存在すること
  grep -qF "post-fix-verify:" "$DEPS_YAML"
}

@test "ac4: deps.yaml の post-fix-verify の dispatch_mode が runner と一致する" {
  # AC: deps.yaml の dispatch_mode と chain.py の CHAIN_STEP_DISPATCH が一致
  # RED: chain.py に post-fix-verify エントリが存在しないため整合性がとれず FAIL
  [[ -f "$DEPS_YAML" ]] || {
    echo "FAIL: deps.yaml が見つかりません: ${DEPS_YAML}" >&2
    return 1
  }
  # deps.yaml の post-fix-verify ブロック内に dispatch_mode: runner が含まれること
  grep -A20 "^  post-fix-verify:" "$DEPS_YAML" | grep -qF "dispatch_mode: runner"
}

@test "ac4: twl check --deps-integrity が post-fix-verify で PASS する（Python モジュール経由）" {
  # AC: twl check --deps-integrity が PASS に相当する整合性を検証
  # RED: chain.py に post-fix-verify が未登録のため deps-integrity チェックで検出される
  # PYTHONPATH は common_setup で設定済み
  python3 -c "
from twl.autopilot.chain import CHAIN_STEPS, CHAIN_STEP_DISPATCH
assert 'post-fix-verify' in CHAIN_STEPS, 'post-fix-verify が CHAIN_STEPS に存在しない'
assert CHAIN_STEP_DISPATCH.get('post-fix-verify') == 'runner', \
    f'dispatch mode が runner でない: {CHAIN_STEP_DISPATCH.get(\"post-fix-verify\")}'
" 2>&1
}

# ---------------------------------------------------------------------------
# AC-5: step_post_fix_verify が codex_available=YES 時に worker-codex-reviewer を spawn する
# ---------------------------------------------------------------------------

@test "ac5: step_post_fix_verify が codex_available=YES 時に claude --agent worker-codex-reviewer を実際に呼び出す" {
  # AC: step_post_fix_verify が codex_available=YES 時に worker-codex-reviewer を spawn する
  # 厳密条件: mock claude で実際の呼び出し引数をログし、
  #           --agent.*worker-codex-reviewer が含まれることを確認する
  # RED: pr-review-manifest.sh の codex_available 分岐が未実装、または
  #      chain-runner.sh の claude --print --agent 呼び出しが存在しないため FAIL
  [[ -f "$CHAIN_RUNNER_SH" ]] || {
    echo "FAIL: chain-runner.sh が見つかりません: ${CHAIN_RUNNER_SH}" >&2
    return 1
  }

  # --- mock claude: 呼び出し引数をログファイルに記録する ---
  local CLAUDE_ARGS_LOG="$SANDBOX/claude-args.log"
  cat > "$STUB_BIN/claude" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "$@" >> "${CLAUDE_ARGS_LOG}"
exit 0
MOCK_EOF
  chmod +x "$STUB_BIN/claude"
  # ログパスをサブシェルに渡すため env 経由でエクスポート
  export CLAUDE_ARGS_LOG

  # --- mock codex: codex_available() が真を返すようにする ---
  # pr-review-manifest.sh の codex_available() は:
  #   command -v codex && codex login status | grep -qi "logged in"
  cat > "$STUB_BIN/codex" <<'MOCK_EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  echo "logged in"
  exit 0
fi
exit 0
MOCK_EOF
  chmod +x "$STUB_BIN/codex"

  # --- 最小限の autopilot state を用意 ---
  mkdir -p "$SANDBOX/.autopilot/issues"

  # --- chain-runner.sh post-fix-verify を実行 ---
  # ISSUE_NUM を設定（record_current_step は issue_num なしでスキップするため任意）
  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    CLAUDE_ARGS_LOG="$CLAUDE_ARGS_LOG" \
    bash "$CHAIN_RUNNER_SH" post-fix-verify 2>/dev/null

  # --- ログファイルに --agent と worker-codex-reviewer が含まれることを検証 ---
  [[ -f "$CLAUDE_ARGS_LOG" ]] || {
    echo "FAIL: claude が一度も呼び出されませんでした (ログファイルなし)" >&2
    return 1
  }
  grep -qE -- '--agent[[:space:]].*worker-codex-reviewer|worker-codex-reviewer.*--agent' "$CLAUDE_ARGS_LOG" || {
    echo "FAIL: claude の引数に --agent.*worker-codex-reviewer が含まれません" >&2
    echo "実際の呼び出し引数:" >&2
    cat "$CLAUDE_ARGS_LOG" >&2
    return 1
  }
}

@test "ac5: step_post_fix_verify が codex_available 条件分岐を持つ" {
  # AC: codex_available=YES の条件で worker-codex-reviewer spawn を制御する
  # RED: 現状の実装には codex_available チェックが存在しないため FAIL
  [[ -f "$CHAIN_RUNNER_SH" ]] || {
    echo "FAIL: chain-runner.sh が見つかりません: ${CHAIN_RUNNER_SH}" >&2
    return 1
  }
  grep -A80 "^step_post_fix_verify()" "$CHAIN_RUNNER_SH" | \
    grep -qE "codex.available|CODEX_AVAILABLE|codex_available"
}

# ---------------------------------------------------------------------------
# AC-6: step_post_fix_verify が agent に <review_target> と <target_files> を渡す
# ---------------------------------------------------------------------------

@test "ac6: step_post_fix_verify が review_target を agent 呼び出しに含める" {
  # AC: step_post_fix_verify が agent に <review_target> (Issue body) を渡す
  # RED: 現状の claude --print --agent 呼び出しに review_target が含まれていないため FAIL
  [[ -f "$CHAIN_RUNNER_SH" ]] || {
    echo "FAIL: chain-runner.sh が見つかりません: ${CHAIN_RUNNER_SH}" >&2
    return 1
  }
  grep -A80 "^step_post_fix_verify()" "$CHAIN_RUNNER_SH" | \
    grep -qE "review.target|review_target|REVIEW_TARGET"
}

@test "ac6: step_post_fix_verify が target_files を agent 呼び出しに含める" {
  # AC: step_post_fix_verify が agent に <target_files> (git diff 一覧) を渡す
  # RED: 現状の claude --print --agent 呼び出しに target_files が含まれていないため FAIL
  [[ -f "$CHAIN_RUNNER_SH" ]] || {
    echo "FAIL: chain-runner.sh が見つかりません: ${CHAIN_RUNNER_SH}" >&2
    return 1
  }
  grep -A80 "^step_post_fix_verify()" "$CHAIN_RUNNER_SH" | \
    grep -qE "target.files|target_files|TARGET_FILES"
}

# ---------------------------------------------------------------------------
# AC-7: step_post_fix_verify が findings.yaml と checkpoint を生成する
# ---------------------------------------------------------------------------

@test "ac7: step_post_fix_verify が findings.yaml の生成処理を含む" {
  # AC: step_post_fix_verify が findings.yaml を生成する
  # RED: 現状の step_post_fix_verify に findings.yaml 生成ロジックが存在しないため FAIL
  [[ -f "$CHAIN_RUNNER_SH" ]] || {
    echo "FAIL: chain-runner.sh が見つかりません: ${CHAIN_RUNNER_SH}" >&2
    return 1
  }
  grep -A100 "^step_post_fix_verify()" "$CHAIN_RUNNER_SH" | \
    grep -qF "findings.yaml"
}

@test "ac7: step_post_fix_verify が checkpoint 書き込み処理を含む" {
  # AC: step_post_fix_verify が checkpoint を生成する
  # RED: 現状の step_post_fix_verify に checkpoint 書き込みが存在しないため FAIL
  [[ -f "$CHAIN_RUNNER_SH" ]] || {
    echo "FAIL: chain-runner.sh が見つかりません: ${CHAIN_RUNNER_SH}" >&2
    return 1
  }
  grep -A100 "^step_post_fix_verify()" "$CHAIN_RUNNER_SH" | \
    grep -qE "checkpoint (write|post-fix-verify)|twl.autopilot.checkpoint"
}

# ---------------------------------------------------------------------------
# AC-8: merge-gate-check-spawn.sh が specialist-audit.sh に
#        --codex-session-dir と --controller-issue-dir を渡す
# ---------------------------------------------------------------------------

@test "ac8: merge-gate-check-spawn.sh が specialist-audit.sh に --codex-session-dir を渡す" {
  # AC: merge-gate-check-spawn.sh が specialist-audit.sh に --codex-session-dir を渡す
  # RED: 現状の merge-gate-check-spawn.sh は --codex-session-dir を渡していないため FAIL
  [[ -f "$MERGE_GATE_SPAWN_SH" ]] || {
    echo "FAIL: merge-gate-check-spawn.sh が見つかりません: ${MERGE_GATE_SPAWN_SH}" >&2
    return 1
  }
  grep -qF -- "--codex-session-dir" "$MERGE_GATE_SPAWN_SH"
}

@test "ac8: merge-gate-check-spawn.sh が specialist-audit.sh に --controller-issue-dir を渡す" {
  # AC: merge-gate-check-spawn.sh が specialist-audit.sh に --controller-issue-dir を渡す
  # RED: 現状の merge-gate-check-spawn.sh は --controller-issue-dir を渡していないため FAIL
  [[ -f "$MERGE_GATE_SPAWN_SH" ]] || {
    echo "FAIL: merge-gate-check-spawn.sh が見つかりません: ${MERGE_GATE_SPAWN_SH}" >&2
    return 1
  }
  grep -qF -- "--controller-issue-dir" "$MERGE_GATE_SPAWN_SH"
}

# ---------------------------------------------------------------------------
# AC-9: specialist-audit.sh が codex_available=YES かつ findings.yaml 不在の場合に
#        HARD FAIL する (exit 1 + "HARD FAIL" メッセージ)
# ---------------------------------------------------------------------------

@test "ac9: specialist-audit.sh が codex コマンド存在 + findings.yaml 不在で HARD FAIL する" {
  # AC: codex_available=YES かつ findings.yaml 不在の場合に HARD FAIL (exit 1 + "HARD FAIL")
  # RED: merge-gate-check-spawn.sh が --codex-session-dir を渡していないため
  #      specialist-audit.sh の HARD FAIL が発動せず silent pass している

  local codex_session_dir="$SANDBOX/codex-session-empty"
  mkdir -p "$codex_session_dir"
  # findings.yaml を生成しない（空ディレクトリ）

  # 空 JSONL ファイル（/dev/null は character special file のため -f チェックで early exit する）
  local empty_jsonl="$SANDBOX/empty.jsonl"
  touch "$empty_jsonl"

  # codex コマンドスタブ（存在するが実行しない）
  local stub_bin="$SANDBOX/.codex-stub"
  mkdir -p "$stub_bin"
  printf '#!/usr/bin/env bash\necho "codex stub"\n' > "$stub_bin/codex"
  chmod +x "$stub_bin/codex"

  run env PATH="$stub_bin:$PATH" bash "$AUDIT_SH" \
    --jsonl "$empty_jsonl" \
    --codex-session-dir "$codex_session_dir" \
    --mode merge-gate 2>&1

  # exit 1 かつ "HARD FAIL" メッセージが stderr に出力されること
  [[ "$status" -eq 1 ]]
}

@test "ac9: specialist-audit.sh の HARD FAIL 出力に 'HARD FAIL' が含まれる" {
  # AC: HARD FAIL 時のメッセージに "HARD FAIL" が含まれること
  # RED: merge-gate-check-spawn.sh が --codex-session-dir を渡さないため
  #      specialist-audit.sh の HARD FAIL が発動せず "HARD FAIL" が出力されない

  local codex_session_dir="$SANDBOX/codex-session-empty-msg"
  mkdir -p "$codex_session_dir"

  local empty_jsonl="$SANDBOX/empty-msg.jsonl"
  touch "$empty_jsonl"

  local stub_bin="$SANDBOX/.codex-stub-msg"
  mkdir -p "$stub_bin"
  printf '#!/usr/bin/env bash\necho "codex stub"\n' > "$stub_bin/codex"
  chmod +x "$stub_bin/codex"

  run env PATH="$stub_bin:$PATH" bash "$AUDIT_SH" \
    --jsonl "$empty_jsonl" \
    --codex-session-dir "$codex_session_dir" \
    --mode merge-gate 2>&1

  echo "$output" | grep -qF "HARD FAIL"
}
