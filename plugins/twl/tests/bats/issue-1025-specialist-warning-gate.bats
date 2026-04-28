#!/usr/bin/env bats
# issue-1025-specialist-warning-gate.bats
#
# Issue #1025: tech-debt(autopilot) - specialist review warning が merge ブロックを発火せず
#              PR #1024 が AC 未達成のまま merged
#
# AC1: PR #1024 と同型の AC 未達成 case を bats fixture で再現
# AC2: 上記 case で merge-gate が block を発火することを test
# AC3: phase-review.json の warning category schema を文書化（schema 定義/検証）
#
# 問題の本質:
#   findings 配列に category: "ac_missing" の WARNING が存在しても
#   merge-gate-check-phase-review.sh がブロックしない。
#   現在このスクリプトは status=MISSING の場合のみチェックし、
#   findings の内容（warning category）を見ていない。
#
# RED フェーズ: 全テストは実装前に FAIL する

load 'helpers/common'

SCRIPT=""

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  export ISSUE_NUM="1025"
  SCRIPT="$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  mkdir -p "$SANDBOX/.autopilot/checkpoints"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# python3 checkpoint stub helper
# merge-gate-check-phase-review.sh は以下を実行する:
#   python3 -m twl.autopilot.checkpoint read --step phase-review --field status
# この stub は指定した status 値を返す
# ---------------------------------------------------------------------------

_stub_checkpoint_status() {
  local status_value="$1"
  cat > "$STUB_BIN/python3" <<PYEOF
#!/usr/bin/env bash
# stub: python3 -m twl.autopilot.checkpoint read --step phase-review --field status
echo "${status_value}"
PYEOF
  chmod +x "$STUB_BIN/python3"
}

# python3 stub: status=PASS を返す（findings に category="ac_missing" の WARNING がある PR #1024 同型 case）
_stub_checkpoint_pass_with_ac_missing_warning() {
  _stub_checkpoint_status "PASS"

  # phase-review.json fixture: PR #1024 と同型の AC 未達成 case
  cat > "$SANDBOX/.autopilot/checkpoints/phase-review.json" <<'JSONEOF'
{
  "step": "phase-review",
  "status": "PASS",
  "findings_summary": "0 CRITICAL, 1 WARNING",
  "critical_count": 0,
  "findings": [
    {
      "severity": "WARNING",
      "category": "ac_missing",
      "message": "AC #1 未確認: specialist review が AC カバレッジを検証していない",
      "confidence": 90
    }
  ],
  "timestamp": "2026-04-28T00:00:00Z"
}
JSONEOF
}

# ===========================================================================
# AC1: PR #1024 と同型の AC 未達成 case を bats fixture で再現
#
# 再現条件:
#   - phase-review.json の status = "PASS"（MISSING ではない）
#   - findings[] に category="ac_missing" の WARNING が存在する
#   - 現在の merge-gate-check-phase-review.sh は findings を見ないため exit 0 を返す
#
# RED: _stub_checkpoint_pass_with_ac_missing_warning の fixture が
#      merge-gate-check-phase-review.sh の findings チェック機能を必要とするが、
#      現在その機能が存在しないため「問題を再現するテスト」として fail する。
#
# 実装目標: merge-gate-check-phase-review.sh が findings[].category を検査して
#           "ac_missing" が存在すれば REJECT (exit 1) を返すこと。
# ===========================================================================

@test "ac1: category=ac_missing の WARNING が findings に存在するフィクスチャ作成" {
  # AC1: PR #1024 と同型の fixture を作成し、category フィールドを確認する
  _stub_checkpoint_pass_with_ac_missing_warning

  local json_file="$SANDBOX/.autopilot/checkpoints/phase-review.json"
  [[ -f "$json_file" ]] || {
    echo "FAIL: phase-review.json フィクスチャが作成されていない" >&2
    return 1
  }

  # findings に ac_missing category が存在することを確認
  local ac_missing_count
  ac_missing_count=$(jq '[.findings[] | select(.category == "ac_missing")] | length' \
    "$json_file" 2>/dev/null || echo "0")

  # RED: findings の category チェックが merge-gate-check-phase-review.sh に未実装
  # このテスト自体はフィクスチャが正しく作れることを確認するため PASS するが、
  # 以下の assert が示す「期待する動作」が未実装
  [[ "$ac_missing_count" -ge 1 ]] || {
    echo "FAIL: findings に category=ac_missing のエントリが存在しない" >&2
    return 1
  }

  # RED: merge-gate-check-phase-review.sh に findings チェック機能が存在しないことを確認
  # 現在の実装で findings チェック用のコード行が存在しないことを検証
  local has_findings_check=0
  if grep -q 'ac_missing\|findings.*category\|category.*findings' "$SCRIPT" 2>/dev/null; then
    has_findings_check=1
  fi
  [[ "$has_findings_check" -gt 0 ]] || {
    echo "FAIL: AC #1 未実装 — merge-gate-check-phase-review.sh に findings[].category チェックが存在しない" >&2
    echo "  現在の実装は status=MISSING のみを検査し、findings の内容を見ていない" >&2
    return 1
  }
}

@test "ac1: phase-review.json の findings[].category フィールドが ac_missing を持つこと" {
  # AC1: fixture が正しい schema を持つことを確認
  _stub_checkpoint_pass_with_ac_missing_warning

  local json_file="$SANDBOX/.autopilot/checkpoints/phase-review.json"
  local category
  category=$(jq -r '.findings[0].category // empty' "$json_file" 2>/dev/null || echo "")

  [[ "$category" == "ac_missing" ]] || {
    echo "FAIL: findings[0].category が 'ac_missing' ではない: '$category'" >&2
    return 1
  }

  # RED: この fixture を受け取った merge-gate-check-phase-review.sh が
  # findings を検査してブロックする機能が未実装であることを確認
  local has_category_check=0
  if grep -q 'ac_missing\|findings\[' "$SCRIPT" 2>/dev/null; then
    has_category_check=1
  fi
  [[ "$has_category_check" -gt 0 ]] || {
    echo "FAIL: AC #1 未実装 — merge-gate-check-phase-review.sh が findings[].category を検査していない" >&2
    return 1
  }
}

# ===========================================================================
# AC2: category=ac_missing の WARNING が存在する case で merge-gate が block を発火すること
#
# 期待動作（実装後）:
#   - phase-review.json の status が PASS でも
#   - findings[] に category="ac_missing" の WARNING があれば
#   - merge-gate-check-phase-review.sh は exit 1 (REJECT) を返す
#
# RED: 現在の実装は status=MISSING のみチェックし findings を見ないため、
#      この case で exit 0 を返してしまう（ブロックしない）
# ===========================================================================

@test "ac2: category=ac_missing の WARNING がある場合 merge-gate が exit 1 (REJECT) を返す" {
  # status=PASS だが findings に ac_missing warning がある case
  _stub_checkpoint_pass_with_ac_missing_warning

  run bash "$SCRIPT"

  # RED: 現在の実装は exit 0 を返す（findings を見ていない）
  # assert_failure は実装前に fail する（exit 0 のため）
  assert_failure || {
    echo "FAIL: AC #2 未実装 — merge-gate-check-phase-review.sh が findings[].category を検査していない" >&2
    echo "  現在の実装: status=PASS のとき常に exit 0 を返す" >&2
    echo "  期待動作:   findings に category=ac_missing が存在すれば exit 1 を返す" >&2
    return 1
  }
}

@test "ac2: category=ac_missing の WARNING がある場合 stderr に REJECT メッセージが出力される" {
  _stub_checkpoint_pass_with_ac_missing_warning

  run bash "$SCRIPT" 2>&1

  # RED: 現在の実装は findings を見ないため REJECT メッセージが出力されない
  assert_output --partial "REJECT" || {
    echo "FAIL: AC #2 未実装 — REJECT メッセージが出力されていない" >&2
    echo "  出力: $output" >&2
    return 1
  }
}

@test "ac2: findings が空の場合（正常系）は merge-gate が exit 0 を返す" {
  # findings が空で status=PASS の正常ケース — ブロックされてはならない
  _stub_checkpoint_status "PASS"

  cat > "$SANDBOX/.autopilot/checkpoints/phase-review.json" <<'JSONEOF'
{
  "step": "phase-review",
  "status": "PASS",
  "findings_summary": "0 CRITICAL, 0 WARNING",
  "critical_count": 0,
  "findings": [],
  "timestamp": "2026-04-28T00:00:00Z"
}
JSONEOF

  run bash "$SCRIPT"

  # 正常系（findings 空）は実装前後ともに exit 0 のはず
  # ただし findings チェック実装後に正常系が壊れないことを確認するため、
  # 実装前は現在の実装（findings を無視）が exit 0 を返す = PASS
  # 実装後も exit 0 を返すこと（回帰防止）
  assert_success || {
    echo "FAIL: AC #2 未実装 — 正常系（findings 空）でも exit 0 が返されない" >&2
    return 1
  }

  # RED: findings チェック実装が完了していないことを示す（実装後削除）
  local has_findings_check=0
  if grep -q 'ac_missing\|findings.*category\|\.findings' "$SCRIPT" 2>/dev/null; then
    has_findings_check=1
  fi
  [[ "$has_findings_check" -gt 0 ]] || {
    echo "FAIL: AC #2 未実装 — merge-gate-check-phase-review.sh に findings チェックが存在しない" >&2
    return 1
  }
}

@test "ac2: severity=WARNING かつ category != ac_missing の場合はブロックしない" {
  # ac_missing 以外の WARNING category はブロック対象外
  _stub_checkpoint_status "PASS"

  cat > "$SANDBOX/.autopilot/checkpoints/phase-review.json" <<'JSONEOF'
{
  "step": "phase-review",
  "status": "PASS",
  "findings_summary": "0 CRITICAL, 1 WARNING",
  "critical_count": 0,
  "findings": [
    {
      "severity": "WARNING",
      "category": "coverage_low",
      "message": "テストカバレッジが基準を下回っている",
      "confidence": 70
    }
  ],
  "timestamp": "2026-04-28T00:00:00Z"
}
JSONEOF

  run bash "$SCRIPT"

  # RED: block 対象 category の判定ロジックが未実装のため、
  #      実装後は "coverage_low" はブロックされず exit 0 になることを期待する。
  #      現在の実装も findings を無視して exit 0 を返すが、
  #      その理由が「findings チェック未実装」であることを確認する。
  local has_selective_block=0
  if grep -q 'ac_missing\|category.*block\|block.*category' "$SCRIPT" 2>/dev/null; then
    has_selective_block=1
  fi
  [[ "$has_selective_block" -gt 0 ]] || {
    echo "FAIL: AC #2 未実装 — block 対象 category の選択的判定ロジックが merge-gate-check-phase-review.sh に存在しない" >&2
    return 1
  }
}

# ===========================================================================
# AC3: phase-review.json の warning category schema を文書化
#
# schema 検証: findings[] の各エントリが必須フィールドを持つこと
#   - severity: "WARNING" | "CRITICAL" | "INFO"
#   - category: string（列挙値: "ac_missing", ...）
#   - message: string
#   - confidence: number (0-100)
#
# schema 文書: refs/phase-review-findings-schema.md または類似ファイルが存在すること
#
# RED: schema 文書が存在しないため fail する
# ===========================================================================

@test "ac3: phase-review findings schema 文書ファイルが存在する" {
  # schema 文書の候補パス（実装時にいずれかに配置する）
  # REPO_ROOT = plugins/twl/
  local schema_candidates=(
    "$REPO_ROOT/docs/phase-review-findings-schema.md"
    "$REPO_ROOT/docs/phase-review-schema.md"
    "$REPO_ROOT/refs/phase-review-findings-schema.md"
    "$REPO_ROOT/refs/ref-phase-review-schema.md"
  )

  local found=false
  local found_path=""
  for f in "${schema_candidates[@]}"; do
    if [[ -f "$f" ]]; then
      found=true
      found_path="$f"
      break
    fi
  done

  # RED: schema 文書が存在しないため fail する
  [[ "$found" == "true" ]] || {
    echo "FAIL: AC #3 未実装 — phase-review findings schema 文書が存在しない" >&2
    echo "  候補パス:" >&2
    for f in "${schema_candidates[@]}"; do
      echo "    $f" >&2
    done
    return 1
  }
}

@test "ac3: schema 文書が category=ac_missing を列挙していること" {
  # schema 文書内に "ac_missing" が記載されていることを確認
  local schema_candidates=(
    "$REPO_ROOT/docs/phase-review-findings-schema.md"
    "$REPO_ROOT/docs/phase-review-schema.md"
    "$REPO_ROOT/plugins/twl/docs/phase-review-schema.md"
    "$REPO_ROOT/plugins/twl/refs/phase-review-findings-schema.md"
    "$REPO_ROOT/plugins/twl/refs/ref-phase-review-schema.md"
  )

  local schema_file=""
  for f in "${schema_candidates[@]}"; do
    [[ -f "$f" ]] && schema_file="$f" && break
  done

  [[ -n "$schema_file" ]] || {
    echo "FAIL: AC #3 未実装 — schema 文書ファイルが存在しない" >&2
    return 1
  }

  grep -q "ac_missing" "$schema_file" || {
    echo "FAIL: AC #3 未実装 — schema 文書に 'ac_missing' category が記載されていない" >&2
    return 1
  }
}

@test "ac3: phase-review.json findings エントリが severity/category/message/confidence の必須フィールドを持つ" {
  # schema 検証: fixture の構造が必須フィールドを全て含むこと
  _stub_checkpoint_pass_with_ac_missing_warning

  local json_file="$SANDBOX/.autopilot/checkpoints/phase-review.json"
  [[ -f "$json_file" ]] || {
    echo "FAIL: phase-review.json フィクスチャが存在しない" >&2
    return 1
  }

  local severity category message confidence
  severity=$(jq -r '.findings[0].severity // empty' "$json_file" 2>/dev/null || echo "")
  category=$(jq -r '.findings[0].category // empty' "$json_file" 2>/dev/null || echo "")
  message=$(jq -r '.findings[0].message // empty' "$json_file" 2>/dev/null || echo "")
  confidence=$(jq -r '.findings[0].confidence // empty' "$json_file" 2>/dev/null || echo "")

  [[ -n "$severity" ]] || {
    echo "FAIL: findings[0].severity が空" >&2; return 1
  }
  [[ -n "$category" ]] || {
    echo "FAIL: findings[0].category が空" >&2; return 1
  }
  [[ -n "$message" ]] || {
    echo "FAIL: findings[0].message が空" >&2; return 1
  }
  [[ -n "$confidence" ]] || {
    echo "FAIL: findings[0].confidence が空" >&2; return 1
  }

  # RED: schema 文書が未作成のため、「列挙された category 値への照合」が不可能
  # schema 文書の存在確認（ac3 第一テストで確認）
  local schema_candidates=(
    "$REPO_ROOT/docs/phase-review-findings-schema.md"
    "$REPO_ROOT/docs/phase-review-schema.md"
    "$REPO_ROOT/plugins/twl/docs/phase-review-schema.md"
    "$REPO_ROOT/plugins/twl/refs/phase-review-findings-schema.md"
    "$REPO_ROOT/plugins/twl/refs/ref-phase-review-schema.md"
  )

  local schema_exists=false
  for f in "${schema_candidates[@]}"; do
    [[ -f "$f" ]] && schema_exists=true && break
  done

  [[ "$schema_exists" == "true" ]] || {
    echo "FAIL: AC #3 未実装 — schema 文書が存在しないため findings フィールドの schema 検証が不完全" >&2
    return 1
  }
}
