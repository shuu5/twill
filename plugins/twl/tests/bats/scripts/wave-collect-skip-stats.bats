#!/usr/bin/env bats
# wave-collect-skip-stats.bats — RED tests for Issue #998
#
# AC1: wave-collect stdout に skipped=${SKIPPED_COUNT} が含まれる
# AC2: skip 理由が 3 カテゴリ enum で集計され ## skip 内訳 セクションに出力される
# AC3: ## 概要統計 表に 完遂率 行が追加され done/(total - state_file_missing - dependency_failed) で計算される
# AC4: skip 0件 / 1件 / 全件 skip の 3 fixture でサマリ表+echo出力を比較、
#      skip 理由カテゴリの一意性、完遂率分母除外ルール
# AC5: externalization-schema.md の wave-{N}-summary.md テンプレートに ## skip 内訳 セクションが存在する
# AC6: externalization-schema.md の配置パスが .supervisor/ に統一されている
# AC7: glossary.md に 5 用語 (skipped / intentional skip / state_file_missing /
#      dependency_failed / status_other) が存在する

load '../helpers/common'

# ---------------------------------------------------------------------------
# Test-wide constants
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # REPO_ROOT is defined by common.bash as plugins/twl/
  WAVE_COLLECT_MD="${REPO_ROOT}/commands/wave-collect.md"
  GLOSSARY_MD="${REPO_ROOT}/architecture/domain/glossary.md"
  EXTERNALIZATION_SCHEMA_MD="${REPO_ROOT}/refs/externalization-schema.md"

  # Create .supervisor directory inside sandbox (wave-collect writes there)
  mkdir -p "$SANDBOX/.supervisor"

  # Helper: extract all bash code blocks from wave-collect.md and write to a
  # runnable script. We concatenate Step 1-3 blocks (skip Step 4 audit).
  _extract_wave_collect_script
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _extract_wave_collect_script
# Extracts bash code blocks from wave-collect.md (Steps 1-3) and writes them
# into $SANDBOX/scripts/wave-collect-extracted.sh.
# Returns non-zero if the source file does not exist.
_extract_wave_collect_script() {
  local md_file="${WAVE_COLLECT_MD}"
  local out="$SANDBOX/scripts/wave-collect-extracted.sh"

  mkdir -p "$SANDBOX/scripts"

  if [[ ! -f "$md_file" ]]; then
    # The source file must exist — tests will fail at run-time if it is absent.
    return 1
  fi

  # Extract content inside ```bash ... ``` blocks, skip Step 4 specialist-audit
  # block (identified by the _audit_log variable).
  python3 - "$md_file" "$out" <<'PYEOF'
import sys, re

src = sys.argv[1]
dst = sys.argv[2]

with open(src) as f:
    content = f.read()

# Find all ```bash ... ``` blocks
blocks = re.findall(r'```bash\n(.*?)```', content, re.DOTALL)

with open(dst, 'w') as f:
    f.write('#!/usr/bin/env bash\nset -euo pipefail\n\n')
    for block in blocks:
        # Skip the specialist-audit block (Step 4)
        if '_audit_log=' in block or 'specialist-audit.sh' in block:
            continue
        f.write(block)
        f.write('\n')
PYEOF
  chmod +x "$out"
}

# _create_plan_yaml <issues_space_separated>
# Writes a plan.yaml with a single Phase 1 containing given issues.
# Uses the standard autopilot-plan.sh format ("    - N") parsed by awk in wave-collect.
_create_plan_yaml() {
  local issues=($@)
  {
    echo "session_id: \"test-998\""
    echo "repo_mode: \"worktree\""
    echo "project_dir: \"$SANDBOX\""
    echo "phases:"
    echo "  - phase: 1"
    for iss in "${issues[@]}"; do
      echo "    - $iss"
    done
    echo "dependencies:"
  } > "$SANDBOX/.autopilot/plan.yaml"
}

# _run_wave_collect
# Sources the extracted script with required env variables pointing to sandbox.
_run_wave_collect() {
  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    PLAN_FILE="$SANDBOX/.autopilot/plan.yaml" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-extracted.sh"
}

# _read_summary
# Reads the generated wave-1-summary.md from .supervisor/
_summary_file() {
  echo "$SANDBOX/.supervisor/wave-1-summary.md"
}

# ---------------------------------------------------------------------------
# AC1: stdout 統計 echo に skipped=${SKIPPED_COUNT} が含まれる
# ---------------------------------------------------------------------------

@test "ac1: wave-collect stdout echo contains skipped=N" {
  # RED: 現在の echo line は skipped= を含まない
  # 実装後: "[wave-collect] 統計: total=..., ..., skipped=N, ..."
  _create_plan_yaml 10 11

  # Issue #10: done, Issue #11: state_file_missing (no JSON)
  create_issue_json 10 "done"
  # Issue #11 has no state file → triggers state_file_missing skip

  _run_wave_collect

  # Assert stdout contains skipped= field
  assert_output --partial "skipped="
}

# ---------------------------------------------------------------------------
# AC2: ## skip 内訳 セクションが 3 カテゴリ enum で出力される
# ---------------------------------------------------------------------------

@test "ac2: summary md contains ## skip 内訳 section with 3-column table" {
  # RED: 現在のサマリには ## skip 内訳 セクションが存在しない
  _create_plan_yaml 20 21 22

  # Issue #20: done
  create_issue_json 20 "done"
  # Issue #21: state_file_missing (no JSON)
  # Issue #22: dependency_failed — simulate via status field
  create_issue_json 22 "failed" '.failure = "dependency_failed"'

  _run_wave_collect

  local summary
  summary="$(_summary_file)"

  # Section header must exist
  run grep -F "## skip 内訳" "$summary"
  assert_success

  # Table must contain the 3 category columns
  run grep -E "理由.*件数.*該当 Issue|理由 \| 件数 \| 該当" "$summary"
  assert_success
}

@test "ac2: skip 内訳 table lists state_file_missing category" {
  # RED: state_file_missing カテゴリが skip 内訳に現れない
  _create_plan_yaml 30 31

  create_issue_json 30 "done"
  # Issue #31: no state file → state_file_missing

  _run_wave_collect

  run grep -F "state_file_missing" "$(_summary_file)"
  assert_success
}

@test "ac2: skip 内訳 table lists dependency_failed category" {
  # RED: dependency_failed カテゴリが skip 内訳に現れない
  _create_plan_yaml 40 41

  create_issue_json 40 "done"
  create_issue_json 41 "skipped" '.failure = "dependency_failed"'

  _run_wave_collect

  run grep -F "dependency_failed" "$(_summary_file)"
  assert_success
}

@test "ac2: skip 内訳 table lists status_other category" {
  # RED: status_other カテゴリが skip 内訳に現れない
  _create_plan_yaml 50 51

  create_issue_json 50 "done"
  create_issue_json 51 "skipped"  # status_other (not missing, not dependency_failed)

  _run_wave_collect

  run grep -F "status_other" "$(_summary_file)"
  assert_success
}

# ---------------------------------------------------------------------------
# AC3: ## 概要統計 に 完遂率 行が存在し、分母ルールが正しい
# ---------------------------------------------------------------------------

@test "ac3: summary md contains 完遂率 row in 概要統計 table" {
  # RED: 現在の ## 概要統計 には 完遂率 行が存在しない
  _create_plan_yaml 60

  create_issue_json 60 "done"

  _run_wave_collect

  run grep -F "完遂率" "$(_summary_file)"
  assert_success
}

@test "ac3: 完遂率 excludes state_file_missing and dependency_failed from denominator" {
  # RED: 完遂率の分母除外ルールが未実装
  # fixture: total=4, done=2, state_file_missing=1, dependency_failed=1, status_other=0
  # expected: 完遂率 = 2 / (4 - 1 - 1) = 2/2 = 100%
  _create_plan_yaml 70 71 72 73

  create_issue_json 70 "done"
  create_issue_json 71 "done"
  # Issue #72: state_file_missing (no JSON)
  create_issue_json 73 "skipped" '.failure = "dependency_failed"'

  _run_wave_collect

  # The 完遂率 value must reflect 100% (2/2) not 50% (2/4)
  run grep -E "完遂率.*100" "$(_summary_file)"
  assert_success
}

@test "ac3: status_other remains in 完遂率 denominator" {
  # RED: status_other が分母に残ることの確認（除外されてはならない）
  # fixture: total=3, done=1, state_file_missing=0, dependency_failed=0, status_other=2
  # expected: 完遂率 = 1 / (3 - 0 - 0) = 1/3 ≒ 33%
  _create_plan_yaml 80 81 82

  create_issue_json 80 "done"
  create_issue_json 81 "skipped"  # status_other
  create_issue_json 82 "skipped"  # status_other

  _run_wave_collect

  # Must NOT show 100% — status_other is in denominator so rate < 100%
  run grep -E "完遂率.*100" "$(_summary_file)"
  # This grep must FAIL (status_other is NOT excluded)
  assert_failure
}

# ---------------------------------------------------------------------------
# AC4: 3 fixture シナリオ検証
# ---------------------------------------------------------------------------

@test "ac4: skip 0件 fixture - skipped=0 in echo and no skip section needed" {
  # RED: skipped=0 がecho に含まれない
  _create_plan_yaml 90 91

  create_issue_json 90 "done"
  create_issue_json 91 "done"

  _run_wave_collect

  assert_output --partial "skipped=0"
}

@test "ac4: skip 1件 fixture - skipped=1 in echo and summary contains skip breakdown" {
  # RED: skipped=1 がechoに含まれない、かつ ## skip 内訳 が欠落
  _create_plan_yaml 100 101

  create_issue_json 100 "done"
  # Issue #101: state_file_missing

  _run_wave_collect

  # echo must contain skipped=1
  assert_output --partial "skipped=1"

  # Summary must have skip section
  run grep -F "## skip 内訳" "$(_summary_file)"
  assert_success
}

@test "ac4: 全件 skip fixture - skipped equals total" {
  # RED: 全件スキップ時に skipped=N がechoに含まれない
  _create_plan_yaml 110 111

  # Both issues have no state file → state_file_missing

  _run_wave_collect

  assert_output --partial "skipped=2"
}

@test "ac4: skip 理由カテゴリの一意性 - 重複カウント禁止" {
  # RED: 同一 Issue が複数カテゴリでカウントされる可能性がある（現状未実装）
  # fixture: Issue #120 は state_file_missing のみ（dependency_failed でもない）
  _create_plan_yaml 120 121

  # Issue #120: no file → state_file_missing only
  create_issue_json 121 "done"

  _run_wave_collect

  local summary
  summary="$(_summary_file)"

  # Extract count for state_file_missing — must be exactly 1
  # The table row format: | state_file_missing | 1 | #120 |
  run grep -E "state_file_missing.*\| *1 *\|" "$summary"
  assert_success

  # dependency_failed count must be 0 (Issue #120 must NOT appear there)
  run grep -E "dependency_failed.*\| *[1-9][0-9]* *\|" "$summary"
  assert_failure
}

@test "ac4: 完遂率分母除外ルール - state_file_missing と dependency_failed は除外" {
  # RED: 完遂率の分母が正しく計算されない
  # total=5, done=2, state_file_missing=1, dependency_failed=1, status_other=1
  # denominator = 5 - 1 - 1 = 3, rate = 2/3 ≒ 66.7%
  _create_plan_yaml 130 131 132 133 134

  create_issue_json 130 "done"
  create_issue_json 131 "done"
  # Issue #132: state_file_missing (no file)
  create_issue_json 133 "skipped" '.failure = "dependency_failed"'
  create_issue_json 134 "skipped"  # status_other

  _run_wave_collect

  local summary
  summary="$(_summary_file)"

  # 完遂率 must contain 66 or 67 (2/3 ≒ 66.7%)
  run grep -E "完遂率.*(66|67)" "$summary"
  assert_success
}

# ---------------------------------------------------------------------------
# AC5: externalization-schema.md に ## skip 内訳 セクションが存在する
# ---------------------------------------------------------------------------

@test "ac5: externalization-schema.md wave-summary template contains ## skip 内訳" {
  # RED: 現在の externalization-schema.md には ## skip 内訳 テンプレートがない
  run grep -F "## skip 内訳" "$EXTERNALIZATION_SCHEMA_MD"
  assert_success
}

@test "ac5: externalization-schema.md skip 内訳 template has 理由/件数/該当Issue columns" {
  # RED: skip 内訳 テンプレートに必要な列定義がない
  run grep -E "理由.*件数.*該当|理由 \| 件数 \| 該当" "$EXTERNALIZATION_SCHEMA_MD"
  assert_success
}

# ---------------------------------------------------------------------------
# AC6: externalization-schema.md の配置パスが .supervisor/ に統一される
# ---------------------------------------------------------------------------

@test "ac6: externalization-schema.md wave-summary path is .supervisor/ not .autopilot/" {
  # RED: 現在の schema は .autopilot/wave-{N}-summary.md と記述されている
  # 実装後: .supervisor/wave-{N}-summary.md に変更される
  run grep -F ".supervisor/wave-" "$EXTERNALIZATION_SCHEMA_MD"
  assert_success
}

@test "ac6: externalization-schema.md does not use .autopilot/ for wave-summary path" {
  # RED: .autopilot/wave-{N}-summary.md の記述が残ってはならない
  # NOTE: この grep が成功する（.autopilot/ が残っている）= RED = 未実装の証拠
  run grep -F ".autopilot/wave-" "$EXTERNALIZATION_SCHEMA_MD"
  assert_failure
}

# ---------------------------------------------------------------------------
# AC7: glossary.md に 5 用語が追加される
# ---------------------------------------------------------------------------

@test "ac7: glossary.md contains term 'skipped'" {
  # RED: 現在の glossary.md に 'skipped' 用語が存在しない
  run grep -w "skipped" "$GLOSSARY_MD"
  assert_success
}

@test "ac7: glossary.md contains term 'intentional skip'" {
  # RED: 現在の glossary.md に 'intentional skip' 用語が存在しない
  run grep -F "intentional skip" "$GLOSSARY_MD"
  assert_success
}

@test "ac7: glossary.md contains term 'state_file_missing'" {
  # RED: 現在の glossary.md に 'state_file_missing' 用語が存在しない
  run grep -F "state_file_missing" "$GLOSSARY_MD"
  assert_success
}

@test "ac7: glossary.md contains term 'dependency_failed'" {
  # RED: 現在の glossary.md に 'dependency_failed' 用語が存在しない
  run grep -F "dependency_failed" "$GLOSSARY_MD"
  assert_success
}

@test "ac7: glossary.md contains term 'status_other'" {
  # RED: 現在の glossary.md に 'status_other' 用語が存在しない
  run grep -F "status_other" "$GLOSSARY_MD"
  assert_success
}
