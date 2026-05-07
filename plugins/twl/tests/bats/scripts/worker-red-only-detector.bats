#!/usr/bin/env bats
# worker-red-only-detector.bats — RED-phase tests for Issue #1482
#
# Issue #1482: merge-gate worker-red-only-detector 新設
# merge-gate に常時追加する RED-only PR 検出 specialist を実装する。
#
# AC coverage:
#   AC1 - worker-red-only-detector.md 新設 (model: sonnet, tools: Bash, Read, Grep)
#   AC2 - gh pr view --json files,additions,deletions で impl-candidate ファイル変更 0 件なら CRITICAL (confidence=85)
#   AC3 - PR body から実装クレームキーワード抽出、impl-candidate ファイル変更と不整合なら CRITICAL
#   AC4 - merge-gate manifest に常時追加 (pr-review-manifest.sh の phase-review|merge-gate 分岐)
#   AC5 - False-positive 抑止: 純粋 RED test PR (label 'red-only' 付き) はスキップ
#   AC6 - BATS test: scenario fixture (test only PR / test+impl PR / docs only PR) で expected severity 一致

load '../helpers/common'

AGENT_FILE=""
MANIFEST_SCRIPT=""
DETECTOR_SCRIPT=""

setup() {
  common_setup
  AGENT_FILE="$REPO_ROOT/agents/worker-red-only-detector.md"
  MANIFEST_SCRIPT="$SANDBOX/scripts/pr-review-manifest.sh"
  DETECTOR_SCRIPT="$REPO_ROOT/scripts/worker-red-only-detector.sh"

  # Default codex stub: "Not logged in"
  cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "login" && "$2" == "status" ]]; then
  echo "Not logged in"
  exit 1
fi
exit 0
STUB
  chmod +x "$STUB_BIN/codex"

  # Default git stub
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*) echo ".git" ;;
      *"branch --show-current"*) echo "feat/1482-test" ;;
      *) exit 0 ;;
    esac
  '

  # Default gh stub
  stub_command "gh" '
    case "$*" in
      *"pr view"*) echo "{}" ;;
      *) exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: worker-red-only-detector.md 新設 (model: sonnet, tools: Bash, Read, Grep)
# ---------------------------------------------------------------------------

@test "ac1: agents/worker-red-only-detector.md が存在する" {
  # AC: worker-red-only-detector.md 新設
  # RED: 実装前は fail する（ファイル未作成）
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
}

@test "ac1: worker-red-only-detector.md に YAML フロントマターが含まれる" {
  # AC: worker-red-only-detector.md 新設
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  # フロントマターは '---' で始まる
  head -1 "$AGENT_FILE" | grep -qF '---' || {
    echo "FAIL: AC #1 未実装 — フロントマターが存在しない (先頭行が '---' でない)" >&2
    return 1
  }
}

@test "ac1: worker-red-only-detector.md の model が sonnet である" {
  # AC: worker-red-only-detector.md 新設 (model: sonnet)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '^model:\s*sonnet' "$AGENT_FILE" || {
    echo "FAIL: AC #1 未実装 — フロントマターに 'model: sonnet' が存在しない" >&2
    grep -n 'model:' "$AGENT_FILE" >&2 || true
    return 1
  }
}

@test "ac1: worker-red-only-detector.md の tools に Bash が含まれる" {
  # AC: worker-red-only-detector.md 新設 (tools: Bash, Read, Grep)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '^\s*-\s*Bash' "$AGENT_FILE" || {
    echo "FAIL: AC #1 未実装 — tools に 'Bash' が存在しない" >&2
    return 1
  }
}

@test "ac1: worker-red-only-detector.md の tools に Read が含まれる" {
  # AC: worker-red-only-detector.md 新設 (tools: Bash, Read, Grep)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '^\s*-\s*Read' "$AGENT_FILE" || {
    echo "FAIL: AC #1 未実装 — tools に 'Read' が存在しない" >&2
    return 1
  }
}

@test "ac1: worker-red-only-detector.md の tools に Grep が含まれる" {
  # AC: worker-red-only-detector.md 新設 (tools: Bash, Read, Grep)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '^\s*-\s*Grep' "$AGENT_FILE" || {
    echo "FAIL: AC #1 未実装 — tools に 'Grep' が存在しない" >&2
    return 1
  }
}

@test "ac1: worker-red-only-detector.md に name フィールドが存在する" {
  # AC: worker-red-only-detector.md 新設 (フロントマター必須フィールド)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '^name:\s*' "$AGENT_FILE" || {
    echo "FAIL: AC #1 未実装 — フロントマターに name フィールドが存在しない" >&2
    return 1
  }
}

@test "ac1: worker-red-only-detector.md に type フィールドが存在する" {
  # AC: worker-red-only-detector.md 新設 (フロントマター必須フィールド)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #1 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '^type:\s*' "$AGENT_FILE" || {
    echo "FAIL: AC #1 未実装 — フロントマターに type フィールドが存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: gh pr view --json files,additions,deletions で impl-candidate ファイル変更 0 件なら
#       CRITICAL (confidence=85)
# ---------------------------------------------------------------------------

@test "ac2: worker-red-only-detector.md に gh pr view --json files コマンドへの言及がある" {
  # AC: gh pr view --json files,additions,deletions で impl-candidate ファイル変更 0 件なら CRITICAL
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #2 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE 'gh pr view.*--json.*files|--json.*files.*additions.*deletions' "$AGENT_FILE" || {
    echo "FAIL: AC #2 未実装 — gh pr view --json files への言及が存在しない" >&2
    return 1
  }
}

@test "ac2: worker-red-only-detector.md に impl-candidate ファイルパターンが定義されている" {
  # AC: *.bats|*test*|tests/.*\.yaml|*.test.sh 以外が impl-candidate
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #2 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  # .bats または test パターンへの言及を確認
  grep -qE '\.bats|test\*|impl.candidate' "$AGENT_FILE" || {
    echo "FAIL: AC #2 未実装 — impl-candidate ファイルパターンが定義されていない" >&2
    return 1
  }
}

@test "ac2: worker-red-only-detector.md に confidence=85 または confidence: 85 が含まれる" {
  # AC: impl-candidate ファイル変更 0 件なら CRITICAL (confidence=85)
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #2 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE 'confidence.*85|85.*confidence' "$AGENT_FILE" || {
    echo "FAIL: AC #2 未実装 — confidence=85 の指定が存在しない" >&2
    return 1
  }
}

@test "ac2: worker-red-only-detector.md に CRITICAL severity への言及がある" {
  # AC: impl-candidate ファイル変更 0 件なら CRITICAL
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #2 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qF 'CRITICAL' "$AGENT_FILE" || {
    echo "FAIL: AC #2 未実装 — CRITICAL severity への言及が存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3: PR body から「実装」「新設」「migrate」等 implementation claim キーワードを抽出、
#       impl-candidate ファイル変更と不整合なら CRITICAL
# ---------------------------------------------------------------------------

@test "ac3: worker-red-only-detector.md に PR body 解析への言及がある" {
  # AC: PR body から implementation claim キーワードを抽出
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #3 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE 'PR body|pr body|body.*implementation|body.*claim' "$AGENT_FILE" || {
    echo "FAIL: AC #3 未実装 — PR body 解析への言及が存在しない" >&2
    return 1
  }
}

@test "ac3: worker-red-only-detector.md に implementation claim キーワード（実装|新設|migrate）への言及がある" {
  # AC: 「実装」「新設」「migrate」等 implementation claim キーワード
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #3 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE '実装|新設|migrate' "$AGENT_FILE" || {
    echo "FAIL: AC #3 未実装 — implementation claim キーワード（実装|新設|migrate 等）への言及が存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC4: merge-gate manifest に常時追加
#       pr-review-manifest.sh の phase-review|merge-gate 分岐
# ---------------------------------------------------------------------------

@test "ac4: pr-review-manifest.sh が scripts/ に存在する" {
  # AC: merge-gate manifest に常時追加
  # RED: 実装前は fail する（既存ファイルだが worker-red-only-detector 追加前）
  [[ -f "$MANIFEST_SCRIPT" ]] || {
    echo "FAIL: AC #4 前提 — $MANIFEST_SCRIPT が存在しない" >&2
    return 1
  }
}

@test "ac4: merge-gate モードで worker-red-only-detector が出力される" {
  # AC: merge-gate manifest に常時追加
  # RED: pr-review-manifest.sh に worker-red-only-detector 追加前は fail する
  [[ -f "$MANIFEST_SCRIPT" ]] || {
    echo "FAIL: AC #4 前提 — $MANIFEST_SCRIPT が存在しない" >&2
    return 1
  }

  # git resolve-issue-num.sh が存在しない環境用の stub
  mkdir -p "$SANDBOX/scripts"
  cat > "$SANDBOX/scripts/resolve-issue-num.sh" <<'RESEOF'
#!/usr/bin/env bash
resolve_issue_num() { echo "1482"; }
RESEOF

  export ISSUE_NUM="1482"
  export PROJECT_ROOT="$SANDBOX"
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'plugins/twl/scripts/some-impl.sh' | bash '$MANIFEST_SCRIPT' --mode merge-gate 2>/dev/null"

  assert_success
  assert_output --partial "worker-red-only-detector"
}

@test "ac4: phase-review モードで worker-red-only-detector が出力される" {
  # AC: merge-gate manifest に常時追加 (phase-review|merge-gate 分岐)
  # RED: pr-review-manifest.sh に worker-red-only-detector 追加前は fail する
  [[ -f "$MANIFEST_SCRIPT" ]] || {
    echo "FAIL: AC #4 前提 — $MANIFEST_SCRIPT が存在しない" >&2
    return 1
  }

  mkdir -p "$SANDBOX/scripts"
  cat > "$SANDBOX/scripts/resolve-issue-num.sh" <<'RESEOF'
#!/usr/bin/env bash
resolve_issue_num() { echo "1482"; }
RESEOF

  export ISSUE_NUM="1482"
  export PROJECT_ROOT="$SANDBOX"
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'plugins/twl/scripts/some-impl.sh' | bash '$MANIFEST_SCRIPT' --mode phase-review 2>/dev/null"

  assert_success
  assert_output --partial "worker-red-only-detector"
}

@test "ac4: worker-red-only-detector が pr-review-manifest.sh のコード内に記載されている" {
  # AC: merge-gate manifest に常時追加（静的コード確認）
  # RED: 追加前は fail する
  [[ -f "$MANIFEST_SCRIPT" ]] || {
    echo "FAIL: AC #4 前提 — $MANIFEST_SCRIPT が存在しない" >&2
    return 1
  }
  grep -qF 'worker-red-only-detector' "$MANIFEST_SCRIPT" || {
    echo "FAIL: AC #4 未実装 — pr-review-manifest.sh に worker-red-only-detector の記載がない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC5: False-positive 抑止: 純粋 RED test PR (label 'red-only' 明示付き) はスキップ
# ---------------------------------------------------------------------------

@test "ac5: worker-red-only-detector.md に red-only ラベルチェックへの言及がある" {
  # AC: label 'red-only' 明示付き PR はスキップ
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #5 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE 'red-only|label.*red|skip.*label' "$AGENT_FILE" || {
    echo "FAIL: AC #5 未実装 — red-only ラベルチェックへの言及が存在しない" >&2
    return 1
  }
}

@test "ac5: worker-red-only-detector.md に SKIP または スキップへの言及がある" {
  # AC: red-only ラベル付き PR は CRITICAL を発行せずスキップ
  # RED: ファイル未存在のため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #5 未実装 — $AGENT_FILE が存在しない" >&2
    return 1
  }
  grep -qE 'SKIP|スキップ|skip' "$AGENT_FILE" || {
    echo "FAIL: AC #5 未実装 — スキップ動作への言及が存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC6: BATS test: scenario fixture (test only PR / test+impl PR / docs only PR)
#       で expected severity 一致
#
# NOTE: このファイル自体が AC6 の BATS test である。
#       AC6 では 3 つの fixture シナリオのテストを生成する。
#       各シナリオは gh pr view JSON 出力を mock し、
#       worker-red-only-detector の判定ロジック（PR body + files チェック）を検証する。
#       実装ファイルが存在しないため全テストは RED として fail する。
# ---------------------------------------------------------------------------

@test "ac6: scenario: test-only PR で CRITICAL が検出される" {
  # AC: scenario fixture (test only PR) → expected severity CRITICAL
  # RED: worker-red-only-detector.md が存在しないため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #6 未実装 — $AGENT_FILE が存在しない（test-only PR シナリオ実行不可）" >&2
    return 1
  }

  # test-only PR fixture: .bats ファイルのみ変更
  local pr_json
  pr_json='{"number":9999,"title":"add RED tests for foo","body":"テスト追加","labels":[],"files":[{"path":"plugins/twl/tests/bats/scripts/foo.bats","additions":50,"deletions":0}]}'

  [[ -f "$DETECTOR_SCRIPT" ]] || {
    echo "FAIL: AC #6 未実装 — $DETECTOR_SCRIPT が存在しない（detector bash wrapper 未作成）" >&2
    return 1
  }

  run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"
  assert_output --partial "CRITICAL"
}

@test "ac6: scenario: test+impl PR で CRITICAL が検出されない" {
  # AC: scenario fixture (test+impl PR) → expected severity なし（PASS）
  # RED: worker-red-only-detector.md が存在しないため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #6 未実装 — $AGENT_FILE が存在しない（test+impl PR シナリオ実行不可）" >&2
    return 1
  }

  # test+impl PR fixture: .bats + .sh ファイル変更
  local pr_json
  pr_json='{"number":9998,"title":"implement foo","body":"実装追加","labels":[],"files":[{"path":"plugins/twl/tests/bats/scripts/foo.bats","additions":50,"deletions":0},{"path":"plugins/twl/scripts/foo.sh","additions":100,"deletions":0}]}'

  [[ -f "$DETECTOR_SCRIPT" ]] || {
    echo "FAIL: AC #6 未実装 — $DETECTOR_SCRIPT が存在しない（detector bash wrapper 未作成）" >&2
    return 1
  }

  run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"
  refute_output --partial "CRITICAL"
}

@test "ac6: scenario: docs-only PR で CRITICAL が検出されない" {
  # AC: scenario fixture (docs only PR) → expected severity なし（PASS）
  # docs-only PR は実装変更なし・implementation claim キーワードなしのため CRITICAL 非対象
  # RED: worker-red-only-detector.md が存在しないため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #6 未実装 — $AGENT_FILE が存在しない（docs-only PR シナリオ実行不可）" >&2
    return 1
  }

  # docs-only PR fixture: .md ファイルのみ変更、PR body に implementation claim なし
  local pr_json
  pr_json='{"number":9997,"title":"update docs","body":"ドキュメント更新のみ","labels":[],"files":[{"path":"docs/guide.md","additions":10,"deletions":5}]}'

  [[ -f "$DETECTOR_SCRIPT" ]] || {
    echo "FAIL: AC #6 未実装 — $DETECTOR_SCRIPT が存在しない（detector bash wrapper 未作成）" >&2
    return 1
  }

  run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"
  refute_output --partial "CRITICAL"
}

@test "ac6: scenario: red-only ラベル付き PR で CRITICAL がスキップされる" {
  # AC: scenario fixture + AC5 の red-only ラベルスキップ確認
  # RED: worker-red-only-detector.md が存在しないため fail する
  [[ -f "$AGENT_FILE" ]] || {
    echo "FAIL: AC #6 未実装 — $AGENT_FILE が存在しない（red-only ラベルスキップシナリオ実行不可）" >&2
    return 1
  }

  # red-only ラベル付き test-only PR fixture
  local pr_json
  pr_json='{"number":9996,"title":"RED tests only","body":"テスト追加","labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/scripts/foo.bats","additions":50,"deletions":0}]}'

  [[ -f "$DETECTOR_SCRIPT" ]] || {
    echo "FAIL: AC #6 未実装 — $DETECTOR_SCRIPT が存在しない（detector bash wrapper 未作成）" >&2
    return 1
  }

  run bash "$DETECTOR_SCRIPT" --pr-json "$pr_json"
  refute_output --partial "CRITICAL"
}
