#!/usr/bin/env bats
# issue-1276-merge-guard-hook.bats
#
# RED-phase tests for Issue #1276:
#   feat(plugins/twl/hook): merge-guard hook — mcp_tool entry + shadow log
#
# AC coverage:
#   AC1 - .claude/settings.json の PreToolUse Bash matcher に mcp_tool entry が追加されている
#   AC2 - mcp_tool entry が mcp__twl__twl_validate_merge を呼び ${tool_input.command} を引数に渡す
#   AC3 - mcp_tool entry の outputType が "log"（block しない）
#   AC4 - 5 fixture シナリオ（bash/mcp_tool 出力突合 → mismatch 0）
#   AC5 - pre-bash-merge-guard.sh が /tmp/mcp-shadow-merge-guard.log に JSONL を書く
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  # git root = worktree root (.claude/ が存在するディレクトリ)
  GIT_ROOT="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
  export GIT_ROOT

  SETTINGS_JSON="${GIT_ROOT}/.claude/settings.json"
  MERGE_GUARD="${GIT_ROOT}/plugins/twl/scripts/hooks/pre-bash-merge-guard.sh"
  SHADOW_COMPARE="${GIT_ROOT}/plugins/twl/scripts/mcp-shadow-compare.sh"
  SHADOW_LOG="/tmp/mcp-shadow-merge-guard.log"

  export SETTINGS_JSON MERGE_GUARD SHADOW_COMPARE SHADOW_LOG

  # テスト用の一時ディレクトリ
  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
  # shadow log をテスト後にクリーンアップ（テスト間の干渉防止）
  rm -f "${SHADOW_LOG}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# AC1: settings.json の PreToolUse Bash matcher に mcp_tool entry が存在する
# ---------------------------------------------------------------------------

@test "ac1: settings.json に PreToolUse Bash matcher が存在する" {
  # AC: PreToolUse に matcher=Bash のエントリが存在する
  # RED: 変更前は存在するが mcp_tool entry がないため以降のテストで fail
  run bash -c "
    jq -e '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
    ' '${SETTINGS_JSON}' > /dev/null
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: settings.json の Bash matcher hooks に mcp_tool タイプのエントリが存在する" {
  # AC: Bash matcher の hooks 配列に type=mcp_tool のエントリが追加されている
  # RED: 実装前は mcp_tool entry が存在しないため fail
  run bash -c "
    jq -e '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
      | .hooks[]
      | select(.type == \"mcp_tool\")
    ' '${SETTINGS_JSON}' > /dev/null
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: Bash matcher に既存の command タイプ hooks が維持されている（回帰防止）" {
  # AC: 既存の pre-bash-merge-guard.sh command hook が削除されていない
  # GREEN: 既存実装が維持されていれば常に pass するが、回帰防止として記載
  run bash -c "
    count=\$(jq '
      [.hooks.PreToolUse[]
       | select(.matcher == \"Bash\")
       | .hooks[]
       | select(.type == \"command\" and (.command | test(\"pre-bash-merge-guard\")))]
      | length
    ' '${SETTINGS_JSON}')
    [ \"\${count}\" -ge 1 ]
  "
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC2: mcp_tool entry が mcp__twl__twl_validate_merge を呼び
#      ${tool_input.command} を引数に渡すこと
# ---------------------------------------------------------------------------

@test "ac2: mcp_tool entry の tool フィールドが twl_validate_merge である" {
  # AC: mcp_tool entry の tool 名が twl_validate_merge
  # RED: mcp_tool entry が存在しないため fail
  run bash -c "
    result=\$(jq -r '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
      | .hooks[]
      | select(.type == \"mcp_tool\")
      | .tool
    ' '${SETTINGS_JSON}' 2>/dev/null)
    [ \"\${result}\" = 'twl_validate_merge' ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac2: mcp_tool entry の server フィールドが twl である" {
  # AC: mcp_tool entry の server が twl
  # RED: mcp_tool entry が存在しないため fail
  run bash -c "
    result=\$(jq -r '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
      | .hooks[]
      | select(.type == \"mcp_tool\")
      | .server
    ' '${SETTINGS_JSON}' 2>/dev/null)
    [ \"\${result}\" = 'twl' ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac2: mcp_tool entry の input に command フィールドが存在し tool_input.command を参照する" {
  # AC: input.command に \${tool_input.command} が設定されている
  # RED: mcp_tool entry が存在しないため fail
  run bash -c "
    result=\$(jq -r '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
      | .hooks[]
      | select(.type == \"mcp_tool\")
      | .input.command
    ' '${SETTINGS_JSON}' 2>/dev/null)
    # \${tool_input.command} または tool_input.command が含まれること
    echo \"\${result}\" | grep -qE 'tool_input\\.command'
  "
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC3: mcp_tool 失敗時は warning ログのみ（block しない）— outputType: "log"
# ---------------------------------------------------------------------------

@test "ac3: mcp_tool entry の outputType が log である" {
  # AC: outputType=log → MCP 失敗時にブロックしない
  # RED: mcp_tool entry が存在しないため fail
  run bash -c "
    result=\$(jq -r '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
      | .hooks[]
      | select(.type == \"mcp_tool\")
      | .outputType
    ' '${SETTINGS_JSON}' 2>/dev/null)
    [ \"\${result}\" = 'log' ]
  "
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC4: fixture 5 件のシナリオテスト
#      bash と mcp_tool の shadow log 突合 → mismatch 0
#
# テスト戦略:
#   各シナリオで pre-bash-merge-guard.sh を TOOL_INPUT_command を設定して呼び出す。
#   実装後は shadow log に bash エントリが書き込まれる想定。
#   現在は shadow log への書き込みが未実装のため fail する。
# ---------------------------------------------------------------------------

# ヘルパー: shadow log に bash と mcp_tool ペアを書き込むシミュレーション
# 実装後のテストは pre-bash-merge-guard.sh が bash エントリを書き込み、
# mcp_tool フック側が mcp_tool エントリを書き込む想定。
# RED フェーズでは bash エントリ自体が書き込まれないことを確認して fail させる。

@test "ac4-fixture1: main→feature merge — bash エントリが shadow log に記録される" {
  # AC: git merge feat/something 実行時、bash 側が shadow log に verdict=allow で記録する
  # RED: pre-bash-merge-guard.sh に shadow log 書き込みが未実装のため fail
  local log_file="${TMPDIR_TEST}/shadow-merge.log"

  TOOL_INPUT_command="git merge feat/something" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  # shadow log にエントリが書き込まれていることを確認
  [ -f "${log_file}" ] || {
    # 実際のパスは /tmp/mcp-shadow-merge-guard.log
    [ -f "${SHADOW_LOG}" ] || {
      echo "FAIL: AC4 未実装 — shadow log が書き込まれていない" >&2
      return 1
    }
  }

  # bash エントリが存在することを確認
  local bash_entry
  bash_entry=$(grep '"source":"bash"' "${SHADOW_LOG}" 2>/dev/null || true)
  [ -n "${bash_entry}" ] || {
    echo "FAIL: AC4 未実装 — shadow log に source=bash エントリが存在しない" >&2
    return 1
  }
}

@test "ac4-fixture2: direct main commit reject — bash エントリが shadow log に記録される" {
  # AC: git push origin main 実行時、bash 側が shadow log に verdict=block で記録する
  # RED: pre-bash-merge-guard.sh に shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git push origin main" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  local bash_entry
  bash_entry=$(grep '"source":"bash"' "${SHADOW_LOG}" 2>/dev/null || true)
  [ -n "${bash_entry}" ] || {
    echo "FAIL: AC4 未実装 — shadow log に source=bash エントリが存在しない (fixture2: git push origin main)" >&2
    return 1
  }
}

@test "ac4-fixture3: squash variant — bash エントリが shadow log に記録される" {
  # AC: git merge --squash feat/topic 実行時、bash 側が shadow log に verdict=allow で記録する
  # RED: pre-bash-merge-guard.sh に shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git merge --squash feat/topic" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  local bash_entry
  bash_entry=$(grep '"source":"bash"' "${SHADOW_LOG}" 2>/dev/null || true)
  [ -n "${bash_entry}" ] || {
    echo "FAIL: AC4 未実装 — shadow log に source=bash エントリが存在しない (fixture3: git merge --squash)" >&2
    return 1
  }
}

@test "ac4-fixture4: non-merge git command — bash エントリが shadow log に skip で記録される" {
  # AC: git status 実行時、bash 側が shadow log に verdict=skip で記録する
  # RED: pre-bash-merge-guard.sh に shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git status" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  local bash_entry
  bash_entry=$(grep '"source":"bash"' "${SHADOW_LOG}" 2>/dev/null || true)
  [ -n "${bash_entry}" ] || {
    echo "FAIL: AC4 未実装 — shadow log に source=bash エントリが存在しない (fixture4: git status)" >&2
    return 1
  }
}

@test "ac4-fixture5: edge detached HEAD — bash エントリが shadow log に記録される" {
  # AC: git merge FETCH_HEAD 実行時、bash 側が shadow log に verdict=allow で記録する
  # RED: pre-bash-merge-guard.sh に shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git merge FETCH_HEAD" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  local bash_entry
  bash_entry=$(grep '"source":"bash"' "${SHADOW_LOG}" 2>/dev/null || true)
  [ -n "${bash_entry}" ] || {
    echo "FAIL: AC4 未実装 — shadow log に source=bash エントリが存在しない (fixture5: git merge FETCH_HEAD)" >&2
    return 1
  }
}

@test "ac4-shadow-compare: mcp-shadow-compare.sh が mismatch 0 を報告する（全5 fixture後）" {
  # AC: 全 fixture シナリオ実行後、bash/mcp_tool 突合で mismatch が 0 件
  # RED: shadow log 書き込みが未実装のため、ログが空/不存在で fail

  # 5 fixture を順次実行して shadow log を蓄積させる
  for cmd in \
    "git merge feat/something" \
    "git push origin main" \
    "git merge --squash feat/topic" \
    "git status" \
    "git merge FETCH_HEAD"
  do
    TOOL_INPUT_command="${cmd}" bash "${MERGE_GUARD}" 2>/dev/null || true
  done

  # shadow log が存在しなければ fail
  [ -f "${SHADOW_LOG}" ] || {
    echo "FAIL: AC4 未実装 — shadow log が存在しない: ${SHADOW_LOG}" >&2
    return 1
  }

  # mcp-shadow-compare.sh で突合
  run bash "${SHADOW_COMPARE}" --log-file "${SHADOW_LOG}"
  [ "${status}" -eq 0 ] || {
    echo "FAIL: AC4 未実装 — mcp-shadow-compare.sh が mismatch を検出した (status=${status})" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC5: pre-bash-merge-guard.sh が /tmp/mcp-shadow-merge-guard.log に
#      JSONL を追記する（mcp-shadow-compare.sh 互換フォーマット）
# ---------------------------------------------------------------------------

@test "ac5: pre-bash-merge-guard.sh がスクリプト内に shadow log 書き込みロジックを含む" {
  # AC: スクリプトに shadow log への JSONL 書き込みコードが存在する
  # RED: 現在の実装には shadow log 書き込みが存在しないため fail
  run bash -c "
    grep -qE 'mcp-shadow-merge-guard\.log|shadow.*merge.*guard|SHADOW_LOG' '${MERGE_GUARD}'
  "
  [ "${status}" -eq 0 ] || {
    echo "FAIL: AC5 未実装 — pre-bash-merge-guard.sh に shadow log 書き込みロジックが存在しない" >&2
    return 1
  }
}

@test "ac5: pre-bash-merge-guard.sh が git merge コマンドで shadow log に JSONL を書き込む" {
  # AC: git merge コマンド実行時に /tmp/mcp-shadow-merge-guard.log に JSONL が追記される
  # RED: shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git merge feat/test-branch" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  [ -f "${SHADOW_LOG}" ] || {
    echo "FAIL: AC5 未実装 — shadow log ファイルが作成されていない: ${SHADOW_LOG}" >&2
    return 1
  }

  # JSONL フォーマット（event_id, ts, source, verdict, command の各フィールド）を確認
  local last_entry
  last_entry=$(tail -1 "${SHADOW_LOG}" 2>/dev/null || echo "")
  [ -n "${last_entry}" ] || {
    echo "FAIL: AC5 未実装 — shadow log が空" >&2
    return 1
  }

  # JSONL として valid であることを確認
  run bash -c "echo '${last_entry}' | jq -e '.event_id and .ts and .source and .verdict and .command' > /dev/null"
  [ "${status}" -eq 0 ] || {
    echo "FAIL: AC5 未実装 — shadow log エントリが JSONL フォーマットでない: ${last_entry}" >&2
    return 1
  }
}

@test "ac5: shadow log エントリの source フィールドが bash である" {
  # AC: pre-bash-merge-guard.sh が書くエントリの source は "bash"
  # RED: shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git merge feat/verify-source" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  [ -f "${SHADOW_LOG}" ] || {
    echo "FAIL: AC5 未実装 — shadow log が存在しない" >&2
    return 1
  }

  local source_val
  source_val=$(tail -1 "${SHADOW_LOG}" | jq -r '.source // empty' 2>/dev/null || echo "")
  [ "${source_val}" = "bash" ] || {
    echo "FAIL: AC5 未実装 — shadow log エントリの source が 'bash' でない: '${source_val}'" >&2
    return 1
  }
}

@test "ac5: shadow log エントリの verdict フィールドが allow/block/skip のいずれかである" {
  # AC: verdict は allow, block, skip のいずれかの値を持つ
  # RED: shadow log 書き込みが未実装のため fail
  TOOL_INPUT_command="git merge feat/verify-verdict" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  [ -f "${SHADOW_LOG}" ] || {
    echo "FAIL: AC5 未実装 — shadow log が存在しない" >&2
    return 1
  }

  local verdict_val
  verdict_val=$(tail -1 "${SHADOW_LOG}" | jq -r '.verdict // empty' 2>/dev/null || echo "")
  case "${verdict_val}" in
    allow|block|skip) ;;
    *)
      echo "FAIL: AC5 未実装 — verdict が allow/block/skip でない: '${verdict_val}'" >&2
      return 1
      ;;
  esac
}

@test "ac5: shadow log への書き込みは追記（append）モードである" {
  # AC: 複数回実行で shadow log が追記される（既存エントリが消えない）
  # RED: shadow log 書き込みが未実装のため fail

  # 1回目
  TOOL_INPUT_command="git merge feat/first" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  local count_before
  count_before=$(wc -l < "${SHADOW_LOG}" 2>/dev/null || echo "0")

  # 2回目
  TOOL_INPUT_command="git merge feat/second" \
    bash "${MERGE_GUARD}" 2>/dev/null || true

  local count_after
  count_after=$(wc -l < "${SHADOW_LOG}" 2>/dev/null || echo "0")

  [ "${count_after}" -gt "${count_before}" ] || {
    echo "FAIL: AC5 未実装 — shadow log が追記されていない (before=${count_before}, after=${count_after})" >&2
    return 1
  }
}
