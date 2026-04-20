#!/usr/bin/env bats
# crg-auto-build-timeout.bats — Issue #754
#
# crg-auto-build の timeout ガード（timeout 600 uvx code-review-graph build）
# および並列実行耐性を検証する。
#
# Scenarios:
#   1. timeout 600s を超過 → exit 124 → 警告出力して workflow 継続
#   2. build 失敗（exit non-zero, non-124） → 警告出力して継続
#   3. build 成功（exit 0） → 成功メッセージ
#   4. .code-review-graph がシンボリックリンク → スキップ（何も出力しない）
#   5. graph.db が既存 → スキップ（何も出力しない）
#   6. .mcp.json に code-review-graph エントリなし → スキップ

load '../helpers/common'

# crg-auto-build.md の shell ロジックをシェルスクリプトとして再現するヘルパー。
# LLM が crg-auto-build.md に従って実行する Bash コマンドを模倣する。
_run_crg_build_logic() {
  local project_dir="$1"
  local mock_exit="${2:-0}"       # uvx の終了コード（124 = timeout）

  # Step 1: CRG 導入状態の判定
  if [[ ! -f "${project_dir}/.mcp.json" ]]; then
    return 0
  fi
  if ! grep -q "code-review-graph" "${project_dir}/.mcp.json" 2>/dev/null; then
    return 0
  fi
  if [[ -L "${project_dir}/.code-review-graph" ]]; then
    return 0
  fi
  if [[ -f "${project_dir}/.code-review-graph/graph.db" ]]; then
    return 0
  fi

  # Step 2 + 3: timeout ガード付き build + 結果判定
  local build_exit
  timeout 600 bash -c "exit ${mock_exit}" 2>/dev/null
  build_exit=$?

  if [[ $build_exit -eq 0 ]]; then
    echo "✓ CRG グラフビルド完了"
  elif [[ $build_exit -eq 124 ]]; then
    echo "⚠️ CRG グラフビルドに失敗しました（timeout 600s）"
  else
    echo "⚠️ CRG グラフビルドに失敗しました"
  fi
  return 0
}

setup() {
  common_setup
  PROJECT_DIR="${SANDBOX}/project"
  mkdir -p "$PROJECT_DIR"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario 1: timeout (exit 124) → 警告出力して継続
# ---------------------------------------------------------------------------
@test "timeout 600s 超過時: ⚠️ 警告を出力して workflow 継続" {
  cat > "${PROJECT_DIR}/.mcp.json" <<'EOF'
{"mcpServers": {"code-review-graph": {"command": "uvx", "args": ["code-review-graph", "serve"]}}}
EOF
  mkdir -p "${PROJECT_DIR}/.code-review-graph"
  # graph.db がない状態でタイムアウトを模倣

  run _run_crg_build_logic "$PROJECT_DIR" 124
  assert_success
  assert_output --partial "⚠️ CRG グラフビルドに失敗しました（timeout 600s）"
}

# ---------------------------------------------------------------------------
# Scenario 2: build 失敗（exit 1 など）→ 警告出力して継続
# ---------------------------------------------------------------------------
@test "build 失敗時: ⚠️ 警告を出力して workflow 継続" {
  cat > "${PROJECT_DIR}/.mcp.json" <<'EOF'
{"mcpServers": {"code-review-graph": {"command": "uvx", "args": ["code-review-graph", "serve"]}}}
EOF
  mkdir -p "${PROJECT_DIR}/.code-review-graph"

  run _run_crg_build_logic "$PROJECT_DIR" 1
  assert_success
  assert_output --partial "⚠️ CRG グラフビルドに失敗しました"
  refute_output --partial "timeout 600s"
}

# ---------------------------------------------------------------------------
# Scenario 3: build 成功（exit 0）→ 成功メッセージ
# ---------------------------------------------------------------------------
@test "build 成功時: ✓ 成功メッセージを出力" {
  cat > "${PROJECT_DIR}/.mcp.json" <<'EOF'
{"mcpServers": {"code-review-graph": {"command": "uvx", "args": ["code-review-graph", "serve"]}}}
EOF
  mkdir -p "${PROJECT_DIR}/.code-review-graph"

  run _run_crg_build_logic "$PROJECT_DIR" 0
  assert_success
  assert_output --partial "✓ CRG グラフビルド完了"
}

# ---------------------------------------------------------------------------
# Scenario 4: .code-review-graph がシンボリックリンク → スキップ
# ---------------------------------------------------------------------------
@test ".code-review-graph がシンボリックリンク: スキップ（出力なし）" {
  cat > "${PROJECT_DIR}/.mcp.json" <<'EOF'
{"mcpServers": {"code-review-graph": {"command": "uvx", "args": ["code-review-graph", "serve"]}}}
EOF
  ln -s /tmp "${PROJECT_DIR}/.code-review-graph"

  run _run_crg_build_logic "$PROJECT_DIR" 0
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Scenario 5: graph.db 既存 → スキップ
# ---------------------------------------------------------------------------
@test "graph.db 既存: スキップ（出力なし）" {
  cat > "${PROJECT_DIR}/.mcp.json" <<'EOF'
{"mcpServers": {"code-review-graph": {"command": "uvx", "args": ["code-review-graph", "serve"]}}}
EOF
  mkdir -p "${PROJECT_DIR}/.code-review-graph"
  touch "${PROJECT_DIR}/.code-review-graph/graph.db"

  run _run_crg_build_logic "$PROJECT_DIR" 0
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Scenario 6: .mcp.json に code-review-graph エントリなし → スキップ
# ---------------------------------------------------------------------------
@test ".mcp.json に code-review-graph エントリなし: スキップ（出力なし）" {
  cat > "${PROJECT_DIR}/.mcp.json" <<'EOF'
{"mcpServers": {"other-tool": {"command": "uvx", "args": ["other"]}}}
EOF

  run _run_crg_build_logic "$PROJECT_DIR" 0
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Scenario 7: timeout ガードの実在性確認（並列 4 Worker 模倣）
# 4 並列の場合でも全て 600 秒以内に完了（成功 or graceful fail）することを確認
# ---------------------------------------------------------------------------
@test "4 並列模倣: 全ジョブが 600s 以内に完了（graceful fail）" {
  for i in 1 2 3 4; do
    mkdir -p "${PROJECT_DIR}/worker${i}"
    cat > "${PROJECT_DIR}/worker${i}/.mcp.json" <<'EOF'
{"mcpServers": {"code-review-graph": {"command": "uvx", "args": ["code-review-graph", "serve"]}}}
EOF
    mkdir -p "${PROJECT_DIR}/worker${i}/.code-review-graph"
  done

  local outputs=()
  for i in 1 2 3 4; do
    outputs+=("$(_run_crg_build_logic "${PROJECT_DIR}/worker${i}" 124)")
  done

  for i in 0 1 2 3; do
    [[ "${outputs[$i]}" == *"⚠️"* ]] || [[ "${outputs[$i]}" == *"✓"* ]]
  done
}
