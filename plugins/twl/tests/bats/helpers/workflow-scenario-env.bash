#!/usr/bin/env bash
# workflow-scenario-env.bash - Issue #144 / Phase 4-A Layer 2
#
# workflow-scenarios bats 共通の sandbox 構築ヘルパー。
# 各テストは setup() で setup_workflow_scenario_env を呼ぶ。teardown() は
# teardown_workflow_scenario_env を呼ぶ。実環境の AUTOPILOT_DIR / git config /
# gh CLI 等が混入しないよう全てを isolate する。

# 1 度だけ解決される plugin ルート（symlink 解決済み）
# trace-assertions.bash と mock-specialists.bash も自動 source する。
setup_workflow_scenario_env() {
  local helpers_dir
  helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PLUGIN_ROOT="$(cd "$helpers_dir/../../.." && pwd)"
  export PLUGIN_ROOT
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

  # PYTHONPATH: chain-runner.sh が source する python-env.sh は自身の位置から
  # git toplevel を解決するが、念のため明示しておく
  local repo_root
  repo_root="$(cd "$PLUGIN_ROOT/../.." && pwd)"
  if [[ -d "$repo_root/cli/twl/src" ]]; then
    export PYTHONPATH="$repo_root/cli/twl/src${PYTHONPATH:+:${PYTHONPATH}}"
  fi

  # Sandbox: 各テストごとに独立した tmpdir を bats 提供のものから派生させる
  WORKFLOW_SANDBOX="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/twl-wfscenario.XXXXXX")"
  export WORKFLOW_SANDBOX
  TWL_CHAIN_TRACE="$WORKFLOW_SANDBOX/trace.jsonl"
  export TWL_CHAIN_TRACE
  : > "$TWL_CHAIN_TRACE"

  # 環境分離: 実環境の AUTOPILOT_DIR / WORKER_ISSUE_NUM を必ず unset
  # （chain-runner の guard 群と resolve_issue_num が誤発火しないように）
  unset AUTOPILOT_DIR WORKER_ISSUE_NUM

  # gh CLI を no-op 化（実 API 叩かないように）
  WORKFLOW_STUB_BIN="$WORKFLOW_SANDBOX/.stub-bin"
  mkdir -p "$WORKFLOW_STUB_BIN"
  cat > "$WORKFLOW_STUB_BIN/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# stub gh: 全コマンドを成功扱い・空出力
exit 0
STUB_EOF
  chmod +x "$WORKFLOW_STUB_BIN/gh"
  _WFSC_ORIG_PATH="$PATH"
  export PATH="$WORKFLOW_STUB_BIN:$PATH"

  # Sandbox 内に git repo を構築し、worktree-create が早期 return する非 main
  # ブランチに切り替える
  pushd "$WORKFLOW_SANDBOX" >/dev/null
  git init -q -b feat/9999-dry-run 2>/dev/null \
    || { git init -q && git checkout -q -b feat/9999-dry-run; }
  git config user.email "test@example.com"
  git config user.name "test"
  git commit -q --allow-empty -m "init" 2>/dev/null || true

  # workflow-test-ready dry-run の change-id-resolve が成功するように
  # deltaspec/changes/<id>/ を 1 件配置
  mkdir -p deltaspec/changes/test-change
  : > deltaspec/changes/test-change/proposal.md
  cat > deltaspec/changes/test-change/.deltaspec.yaml <<'YAML_EOF'
status: pending
YAML_EOF
  popd >/dev/null

  # CWD を sandbox に固定（chain-runner の resolve_project_root が git toplevel を返す）
  _WFSC_ORIG_CWD="$PWD"
  cd "$WORKFLOW_SANDBOX"
}

teardown_workflow_scenario_env() {
  if [[ -n "${_WFSC_ORIG_CWD:-}" ]]; then
    cd "$_WFSC_ORIG_CWD" 2>/dev/null || cd /
  fi
  if [[ -n "${_WFSC_ORIG_PATH:-}" ]]; then
    export PATH="$_WFSC_ORIG_PATH"
  fi
  if [[ -n "${WORKFLOW_SANDBOX:-}" && -d "$WORKFLOW_SANDBOX" ]]; then
    rm -rf "$WORKFLOW_SANDBOX"
  fi
  unset WORKFLOW_SANDBOX TWL_CHAIN_TRACE WORKFLOW_STUB_BIN
}
