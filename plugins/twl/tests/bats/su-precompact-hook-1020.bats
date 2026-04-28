#!/usr/bin/env bats
# su-precompact-hook-1020.bats
#
# Issue #1020: tech-debt(observer): PreCompact hook が working-memory を退避せず cat のみ
#              auto-compact 経路で su-compact が経由されない
#
# AC1: su-precompact.sh が working-memory.md の auto 更新（session.json から状態取り出し → ensure write）を実装する
# AC2: su-postcompact.sh stdout に「Skill(twl:su-compact) を実行して Long-term Memory 保存」を明示誘導
# AC3: su-observer/SKILL.md SU-5 セクションに context 残量検知手段が明示される（案 C 範囲）
# AC4: bats 経路で auto_precompact trigger が動作確認（working-memory.md 更新検証）
#
# 全テストは現在の実装では FAIL（RED）状態であること

load 'helpers/common'

PRECOMPACT_SCRIPT=""
POSTCOMPACT_SCRIPT=""
SKILL_MD=""

setup() {
  common_setup

  local helpers_dir
  helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir="$helpers_dir"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  REPO_ROOT_1020="$(cd "${tests_dir}/.." && pwd)"

  PRECOMPACT_SCRIPT="${REPO_ROOT_1020}/scripts/su-precompact.sh"
  POSTCOMPACT_SCRIPT="${REPO_ROOT_1020}/scripts/su-postcompact.sh"
  SKILL_MD="${REPO_ROOT_1020}/skills/su-observer/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: su-precompact.sh が working-memory.md の write を実装していること
#
# RED: 現在の実装は cat のみで working-memory.md を write しない
# ===========================================================================

@test "ac1: su-precompact.sh が working-memory.md を write する（static grep）" {
  # RED: 現在の実装に write 操作が存在しないため fail する
  # PASS 条件（実装後）: スクリプト内に working-memory.md への書き込みパターンが存在する
  run grep -E '(tee|>\s*.*working-memory\.md|write.*working-memory|ensure.*write)' "$PRECOMPACT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: working-memory.md への write 操作が su-precompact.sh に存在しない"
    echo "現在の実装:"
    cat "$PRECOMPACT_SCRIPT"
    return 1
  }
}

@test "ac1: su-precompact.sh が session.json から状態を取り出す（static grep）" {
  # RED: 現在の実装は session.json を参照しないため fail する
  # PASS 条件（実装後）: スクリプト内に session.json 参照が存在する
  run grep -E 'session\.json' "$PRECOMPACT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: session.json の参照が su-precompact.sh に存在しない"
    echo "現在の実装:"
    cat "$PRECOMPACT_SCRIPT"
    return 1
  }
}

@test "ac1: su-precompact.sh が bash -n を通過する（syntax check）" {
  # 実装前後ともに syntax は通過すべき（実装後の回帰防止）
  run bash -n "$PRECOMPACT_SCRIPT"
  assert_success
}

# ===========================================================================
# AC2: su-postcompact.sh の stdout に Skill(twl:su-compact) 誘導が含まれること
#
# RED: 現在の実装に「Skill(twl:su-compact)」文字列が存在しないため fail する
# ===========================================================================

@test "ac2: su-postcompact.sh に 'Skill(twl:su-compact)' を明示する行が存在する（static grep）" {
  # RED: 現在の su-postcompact.sh に Skill(twl:su-compact) 誘導が存在しないため fail する
  # PASS 条件（実装後）: スクリプト内に明示誘導行が存在する
  run grep -F 'Skill(twl:su-compact)' "$POSTCOMPACT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: 'Skill(twl:su-compact)' を実行して Long-term Memory 保存の誘導が su-postcompact.sh に存在しない"
    echo "現在の実装:"
    cat "$POSTCOMPACT_SCRIPT"
    return 1
  }
}

@test "ac2: su-postcompact.sh 実行時に stdout に 'Skill(twl:su-compact)' が含まれる" {
  # RED: 現在の実装には Skill(twl:su-compact) の出力がないため fail する
  # テスト用の .supervisor ディレクトリをサンドボックスに作成
  local supervisor_dir="${SANDBOX}/.supervisor"
  mkdir -p "$supervisor_dir"
  echo "test working memory content" > "${supervisor_dir}/working-memory.md"

  run bash "$POSTCOMPACT_SCRIPT"

  echo "--- stdout ---"
  echo "$output"
  echo "--- status: $status ---"

  echo "$output" | grep -qF 'Skill(twl:su-compact)' || {
    echo "FAIL: stdout に 'Skill(twl:su-compact)' が含まれない"
    return 1
  }
}

# ===========================================================================
# AC3: SKILL.md の SU-5 セクションに context 残量検知手段が明示されること
#
# RED: 現在の SKILL.md の SU-5 行には検知手段が記載されていないため fail する
# ===========================================================================

@test "ac3: SKILL.md の SU-5 行に context 残量検知手段が記述されている（grep チェック）" {
  # RED: 現在の SU-5 行は「context 消費量 80% 到達時に知識外部化を開始しなければならない（SHALL）」のみで
  #      「検知手段」の記述がないため fail する
  # PASS 条件（実装後）: SU-5 の行または近傍に検知手段（hooks/budget/PreCompact/残量 等）の言及がある
  local su5_context
  su5_context=$(grep -A 3 'SU-5' "$SKILL_MD" || true)

  echo "--- SU-5 context ---"
  echo "$su5_context"

  echo "$su5_context" | grep -qE '(PreCompact|hooks?|budget|残量|検知|detect|trigger)' || {
    echo "FAIL: SU-5 セクションに context 残量検知手段の記述が存在しない"
    echo "現在の SU-5:"
    echo "$su5_context"
    return 1
  }
}

# ===========================================================================
# AC4: auto_precompact trigger — working-memory.md 更新検証
#      tempdir 使用、su-precompact.sh 実行後に working-memory.md が更新される
#
# RED: 現在の実装は cat のみで write しないため fail する
# ===========================================================================

@test "ac4: su-precompact.sh 実行後に working-memory.md が更新される（tempdir）" {
  # RED: 現在の実装は working-memory.md を write しないため fail する
  # PASS 条件（実装後）: su-precompact.sh 実行後に working-memory.md が存在し更新される

  local supervisor_dir="${SANDBOX}/.supervisor"
  mkdir -p "$supervisor_dir"

  # session.json を作成（session.json から状態取り出しができるように）
  cat > "${supervisor_dir}/session.json" <<'SESSIONEOF'
{
  "session_id": "test-session-1020",
  "claude_session_id": "test-claude-session-id",
  "observer_window": "test-window",
  "status": "active",
  "current_task": "Issue #1020 implementation",
  "started_at": "2026-04-28T00:00:00Z"
}
SESSIONEOF

  # SUPERVISOR_DIR をサンドボックスの .supervisor に向ける
  run env SUPERVISOR_DIR="${supervisor_dir}" bash "$PRECOMPACT_SCRIPT"

  echo "--- stdout ---"
  echo "$output"
  echo "--- status: $status ---"

  # working-memory.md が存在することを確認
  [ -f "${supervisor_dir}/working-memory.md" ] || {
    echo "FAIL: su-precompact.sh 実行後に working-memory.md が作成/更新されていない"
    echo "supervisor_dir 内容:"
    ls -la "$supervisor_dir"
    return 1
  }

  # working-memory.md の内容が空でないことを確認
  local content
  content=$(cat "${supervisor_dir}/working-memory.md")
  [ -n "$content" ] || {
    echo "FAIL: working-memory.md が空（内容が書き込まれていない）"
    return 1
  }
}

@test "ac4: su-precompact.sh 実行後の working-memory.md に session.json の情報が含まれる" {
  # RED: 現在の実装は session.json を読まないため fail する
  # PASS 条件（実装後）: working-memory.md に session.json の状態情報が反映されている

  local supervisor_dir="${SANDBOX}/.supervisor"
  mkdir -p "$supervisor_dir"

  cat > "${supervisor_dir}/session.json" <<'SESSIONEOF'
{
  "session_id": "test-session-1020",
  "claude_session_id": "test-claude-session-id",
  "observer_window": "",
  "status": "active",
  "current_task": "Issue #1020 precompact implementation",
  "started_at": "2026-04-28T00:00:00Z"
}
SESSIONEOF

  run env SUPERVISOR_DIR="${supervisor_dir}" bash "$PRECOMPACT_SCRIPT"

  [ -f "${supervisor_dir}/working-memory.md" ] || {
    echo "FAIL: working-memory.md が存在しない"
    return 1
  }

  # working-memory.md に session 情報（session_id または状態）が含まれることを確認
  local content
  content=$(cat "${supervisor_dir}/working-memory.md")
  echo "--- working-memory.md ---"
  echo "$content"

  echo "$content" | grep -qE '(test-session-1020|session_id|current_task|Issue #1020)' || {
    echo "FAIL: working-memory.md に session.json の情報が含まれていない"
    echo "working-memory.md の内容:"
    echo "$content"
    return 1
  }
}

@test "ac4: su-precompact.sh — .supervisor ディレクトリが存在しない場合は正常 exit 0" {
  # .supervisor なしの場合は exit 0 で終了すること（既存動作の回帰防止）
  run env SUPERVISOR_DIR="${SANDBOX}/nonexistent-supervisor" bash "$PRECOMPACT_SCRIPT"
  assert_success
}
