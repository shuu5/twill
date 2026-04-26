#!/usr/bin/env bats
# su-observer-984-ac-checks.bats - Issue #984 AC 機械的検証テスト（TDD RED フェーズ）
#
# Issue #984: tech-debt: su-observer SKILL.md split / refs 移動
#
# このファイルは実装前（RED）状態で全テストが fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。
#
# Coverage: AC1〜AC8 機械的検証項目

load '../helpers/common'

SKILL_MD=""
REFS_DIR=""

setup() {
  common_setup
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
  REFS_DIR="$REPO_ROOT/skills/su-observer/refs"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: su-observer SKILL.md の supervisor token_bloat トークン数が 2000 以下
# ===========================================================================
# RED 理由: 現在 SKILL.md は 6542 トークン。split 前なので fail する。
# ===========================================================================

@test "ac1: SKILL.md の token 数が 2000 以下であること（supervisor token_bloat）" {
  # audit.py count_tokens(SKILL.md) で計測
  # 実装前: 6542 tok → RED
  local token_count
  token_count=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/../../../cli/twl/src')
from pathlib import Path
from twl.core.plugin import count_tokens
print(count_tokens(Path('$SKILL_MD')))
" 2>/dev/null) || {
    # twl CLI 経由でも試みる
    token_count=$(python3 -c "
import sys, subprocess
result = subprocess.run(['python3', '-c', '''
import sys; sys.path.insert(0, \"$REPO_ROOT/../../../cli/twl/src\")
from pathlib import Path; from twl.core.plugin import count_tokens
print(count_tokens(Path(\"$SKILL_MD\")))
'''], capture_output=True, text=True)
print(result.stdout.strip())
" 2>/dev/null) || token_count=""
  }

  # フォールバック: wc -w による近似（1 word ≈ 0.75 tok, 粗い）
  if [[ -z "$token_count" || "$token_count" == "None" ]]; then
    fail "token 計測に失敗: PYTHONPATH 設定か count_tokens 関数を確認してください"
  fi

  [[ "$token_count" =~ ^[0-9]+$ ]] \
    || fail "token_count が数値でない: '$token_count'"

  [[ "$token_count" -le 2000 ]] \
    || fail "SKILL.md token 数が 2000 超過: ${token_count} tok（AC1 未達: split が必要）"
}

# ===========================================================================
# AC2: refs/ 配下の全 .md ファイルが SKILL.md の Read 指示から 1:1 参照
#      （新規 4 ref が存在し、かつ SKILL.md から参照されていること）
# ===========================================================================
# RED 理由: 新規 4 ref ファイルがまだ存在しない → fail する。
# ===========================================================================

@test "ac2: 新規 ref su-observer-supervise-channels.md が存在し SKILL.md から参照される" {
  local ref_file="$REFS_DIR/su-observer-supervise-channels.md"

  # ファイル存在チェック（実装前は存在しない）
  [[ -f "$ref_file" ]] \
    || fail "新規 ref が存在しない: $ref_file（AC2 未達: ref ファイル作成が必要）"

  # SKILL.md からの Read 参照チェック
  grep -qE "refs/su-observer-supervise-channels\.md" "$SKILL_MD" \
    || fail "SKILL.md に refs/su-observer-supervise-channels.md への Read 参照がない"
}

@test "ac2: 新規 ref su-observer-controller-spawn-playbook.md が存在し SKILL.md から参照される" {
  local ref_file="$REFS_DIR/su-observer-controller-spawn-playbook.md"

  [[ -f "$ref_file" ]] \
    || fail "新規 ref が存在しない: $ref_file（AC2 未達: ref ファイル作成が必要）"

  grep -qE "refs/su-observer-controller-spawn-playbook\.md" "$SKILL_MD" \
    || fail "SKILL.md に refs/su-observer-controller-spawn-playbook.md への Read 参照がない"
}

@test "ac2: 新規 ref su-observer-wave-management.md が存在し SKILL.md から参照される" {
  local ref_file="$REFS_DIR/su-observer-wave-management.md"

  [[ -f "$ref_file" ]] \
    || fail "新規 ref が存在しない: $ref_file（AC2 未達: ref ファイル作成が必要）"

  grep -qE "refs/su-observer-wave-management\.md" "$SKILL_MD" \
    || fail "SKILL.md に refs/su-observer-wave-management.md への Read 参照がない"
}

@test "ac2: 新規 ref su-observer-security-gate.md が存在し SKILL.md から参照される" {
  local ref_file="$REFS_DIR/su-observer-security-gate.md"

  [[ -f "$ref_file" ]] \
    || fail "新規 ref が存在しない: $ref_file（AC2 未達: ref ファイル作成が必要）"

  grep -qE "refs/su-observer-security-gate\.md" "$SKILL_MD" \
    || fail "SKILL.md に refs/su-observer-security-gate.md への Read 参照がない"
}

@test "ac2: refs/ 配下の新規 4 ref と参照必須の既存 ref が SKILL.md から参照されている" {
  # pilot-completion-signals.md は実装前から SKILL.md 未参照（現状維持 = 参照なしが正）
  # 本テストは新規 4 ref + 参照必須の既存 ref（monitor-channel-catalog / pitfalls-catalog / proxy-dialog-playbook）を対象とする
  local -a required_refs=(
    "su-observer-supervise-channels.md"
    "su-observer-controller-spawn-playbook.md"
    "su-observer-wave-management.md"
    "su-observer-security-gate.md"
    "monitor-channel-catalog.md"
    "pitfalls-catalog.md"
    "proxy-dialog-playbook.md"
  )

  local unreferenced_count=0
  local unreferenced_list=""
  for ref_name in "${required_refs[@]}"; do
    if ! grep -qE "refs/${ref_name}" "$SKILL_MD"; then
      unreferenced_count=$((unreferenced_count + 1))
      unreferenced_list="${unreferenced_list} ${ref_name}"
    fi
  done

  [[ "$unreferenced_count" -eq 0 ]] \
    || fail "SKILL.md に Read 参照のない必須 ref が ${unreferenced_count} 件存在する:${unreferenced_list}"
}

# ===========================================================================
# AC3: SKILL.md 本体から intervention-catalog.md への直接 Read 指示が 1-hop で残る
# ===========================================================================
# RED 理由: 移動後に intervention-catalog が 2-hop に埋もれた場合に fail させる。
#            現状は pass するが、実装中に誤って削除された場合の退行防止テスト。
#            「RED テスト」として: 現状では pass のため、この AC は実装後 GREEN が継続する
#            ことを保証するガード。実装が誤っていれば fail する。
# NOTE: AC3 は移動後も維持されるべき不変条件。現在は PASS するが実装後の退行を検知する。
# ===========================================================================

@test "ac3: SKILL.md 本体から intervention-catalog への直接 Read 参照が 1 件以上存在する" {
  # grep "intervention-catalog" skills/su-observer/SKILL.md で 1 件以上 hit
  local hit_count
  hit_count=$(grep -c "intervention-catalog" "$SKILL_MD" 2>/dev/null || echo "0")

  [[ "$hit_count" =~ ^[0-9]+$ ]] \
    || fail "grep 結果が数値でない: '$hit_count'"

  [[ "$hit_count" -ge 1 ]] \
    || fail "SKILL.md に 'intervention-catalog' の直接参照が 0 件（AC3: 1-hop 参照が消失している）"
}

# ===========================================================================
# AC4: 新規 4 ref ファイルそれぞれが 200 lines 以下（1 トピック原則）
# ===========================================================================
# RED 理由: 新規 ref ファイルが存在しない → [[ -f ]] で fail する。
# ===========================================================================

@test "ac4: su-observer-supervise-channels.md が 200 lines 以下" {
  local ref_file="$REFS_DIR/su-observer-supervise-channels.md"

  [[ -f "$ref_file" ]] \
    || fail "ref ファイルが存在しない: $ref_file（AC4 未達: ファイル作成が必要）"

  local line_count
  line_count=$(wc -l < "$ref_file")

  [[ "$line_count" -le 200 ]] \
    || fail "su-observer-supervise-channels.md が 200 lines 超過: ${line_count} lines（1 トピック原則違反）"
}

@test "ac4: su-observer-controller-spawn-playbook.md が 200 lines 以下" {
  local ref_file="$REFS_DIR/su-observer-controller-spawn-playbook.md"

  [[ -f "$ref_file" ]] \
    || fail "ref ファイルが存在しない: $ref_file（AC4 未達: ファイル作成が必要）"

  local line_count
  line_count=$(wc -l < "$ref_file")

  [[ "$line_count" -le 200 ]] \
    || fail "su-observer-controller-spawn-playbook.md が 200 lines 超過: ${line_count} lines（1 トピック原則違反）"
}

@test "ac4: su-observer-wave-management.md が 200 lines 以下" {
  local ref_file="$REFS_DIR/su-observer-wave-management.md"

  [[ -f "$ref_file" ]] \
    || fail "ref ファイルが存在しない: $ref_file（AC4 未達: ファイル作成が必要）"

  local line_count
  line_count=$(wc -l < "$ref_file")

  [[ "$line_count" -le 200 ]] \
    || fail "su-observer-wave-management.md が 200 lines 超過: ${line_count} lines（1 トピック原則違反）"
}

@test "ac4: su-observer-security-gate.md が 200 lines 以下" {
  local ref_file="$REFS_DIR/su-observer-security-gate.md"

  [[ -f "$ref_file" ]] \
    || fail "ref ファイルが存在しない: $ref_file（AC4 未達: ファイル作成が必要）"

  local line_count
  line_count=$(wc -l < "$ref_file")

  [[ "$line_count" -le 200 ]] \
    || fail "su-observer-security-gate.md が 200 lines 超過: ${line_count} lines（1 トピック原則違反）"
}

# ===========================================================================
# AC5: twl check --deps-integrity が 0 errors
# ===========================================================================
# RED 理由: 新規 4 ref が deps.yaml に未追加 → Missing ファイル検知で fail する
#           （ただし現状は新規 ref ファイル自体が存在しないため、
#            deps.yaml に calls: 追記後に Missing error が発生する状態を検知する）
# RED テスト実装: 新規 4 ref の deps.yaml 登録チェック（calls: + references: 両方）
# ===========================================================================

@test "ac5: deps.yaml の su-observer calls に新規 4 ref が登録されている" {
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # su-observer-supervise-channels が calls に存在するか
  grep -qE "reference:\s*su-observer-supervise-channels" "$deps_yaml" \
    || fail "deps.yaml su-observer.calls に 'reference: su-observer-supervise-channels' がない（AC5 未達）"

  # su-observer-controller-spawn-playbook が calls に存在するか
  grep -qE "reference:\s*su-observer-controller-spawn-playbook" "$deps_yaml" \
    || fail "deps.yaml su-observer.calls に 'reference: su-observer-controller-spawn-playbook' がない（AC5 未達）"

  # su-observer-wave-management が calls に存在するか
  grep -qE "reference:\s*su-observer-wave-management" "$deps_yaml" \
    || fail "deps.yaml su-observer.calls に 'reference: su-observer-wave-management' がない（AC5 未達）"

  # su-observer-security-gate が calls に存在するか
  grep -qE "reference:\s*su-observer-security-gate" "$deps_yaml" \
    || fail "deps.yaml su-observer.calls に 'reference: su-observer-security-gate' がない（AC5 未達）"
}

@test "ac5: deps.yaml の components.references に新規 4 ref が登録されている" {
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # components.references セクションに各 ref が存在するか
  grep -qE "^\s+su-observer-supervise-channels:" "$deps_yaml" \
    || fail "deps.yaml components.references に 'su-observer-supervise-channels:' がない（AC5 未達）"

  grep -qE "^\s+su-observer-controller-spawn-playbook:" "$deps_yaml" \
    || fail "deps.yaml components.references に 'su-observer-controller-spawn-playbook:' がない（AC5 未達）"

  grep -qE "^\s+su-observer-wave-management:" "$deps_yaml" \
    || fail "deps.yaml components.references に 'su-observer-wave-management:' がない（AC5 未達）"

  grep -qE "^\s+su-observer-security-gate:" "$deps_yaml" \
    || fail "deps.yaml components.references に 'su-observer-security-gate:' がない（AC5 未達）"
}

@test "ac5: twl check --deps-integrity が 0 errors（Missing ファイルなし）" {
  local output
  output=$(cd "$REPO_ROOT" && twl check --deps-integrity 2>&1)
  local exit_code=$?

  # Missing: 0 が含まれること（新規 ref 未追加の場合は Missing > 0 になる）
  echo "$output" | grep -qE "Missing:\s*0" \
    || fail "twl check --deps-integrity で Missing ファイルが検出された（AC5 未達）: $output"

  # 全体が errors なしで完了すること
  echo "$output" | grep -qiE "error|Error" \
    && fail "twl check --deps-integrity でエラーが検出された: $output" || true
}

# ===========================================================================
# AC6: twl update-readme 後 README.md に新構造（refs/ 追加）が反映される
# ===========================================================================
# 実装: README.md の Refs コンポーネント数が 23 以上になること（19 + 4 新規 ref）
#       + deps.yaml と連動した docs/*.dot に新規 ref 名が記録されること
# ===========================================================================

@test "ac6: README.md の Refs コンポーネント数が 23 以上に更新されている" {
  local readme="$REPO_ROOT/README.md"

  [[ -f "$readme" ]] \
    || fail "README.md が見つからない: $readme"

  # Refs 行に 23 以上の数字が記載されているか
  local refs_count
  refs_count=$(grep -E "^\| Refs \|" "$readme" | grep -oE '\| [0-9]+ \|' | grep -oE '[0-9]+' | head -1)

  [[ -n "$refs_count" ]] \
    || fail "README.md に Refs コンポーネント数の記載が見つからない"

  [[ "$refs_count" -ge 23 ]] \
    || fail "README.md の Refs 数が ${refs_count}（期待: ≥ 23 = 既存 19 + 新規 4）（AC6: twl update-readme 後の新構造反映が必要）"
}

@test "ac6: deps.dot に su-observer-supervise-channels が記録されている" {
  local deps_dot="$REPO_ROOT/docs/deps.dot"

  [[ -f "$deps_dot" ]] \
    || fail "docs/deps.dot が見つからない"

  grep -q "su-observer.*supervise.channels\|su_observer_supervise_channels" "$deps_dot" \
    || fail "docs/deps.dot に 'su-observer-supervise-channels' が記録されていない（AC6: twl update-readme 後の反映確認）"
}

@test "ac6: deps.dot に su-observer-controller-spawn-playbook が記録されている" {
  local deps_dot="$REPO_ROOT/docs/deps.dot"

  [[ -f "$deps_dot" ]] \
    || fail "docs/deps.dot が見つからない"

  grep -q "su_observer_controller_spawn_playbook\|controller.spawn.playbook" "$deps_dot" \
    || fail "docs/deps.dot に 'su-observer-controller-spawn-playbook' が記録されていない（AC6: twl update-readme 後の反映確認）"
}

@test "ac6: deps.dot に su-observer-wave-management が記録されている" {
  local deps_dot="$REPO_ROOT/docs/deps.dot"

  [[ -f "$deps_dot" ]] \
    || fail "docs/deps.dot が見つからない"

  grep -q "su_observer_wave_management\|wave.management" "$deps_dot" \
    || fail "docs/deps.dot に 'su-observer-wave-management' が記録されていない（AC6: twl update-readme 後の反映確認）"
}

@test "ac6: deps.dot に su-observer-security-gate が記録されている" {
  local deps_dot="$REPO_ROOT/docs/deps.dot"

  [[ -f "$deps_dot" ]] \
    || fail "docs/deps.dot が見つからない"

  grep -q "su_observer_security_gate\|security.gate" "$deps_dot" \
    || fail "docs/deps.dot に 'su-observer-security-gate' が記録されていない（AC6: twl update-readme 後の反映確認）"
}

# ===========================================================================
# AC7: su-observer-security-gate.bats の grep 対象が refs/ ファイルを含む
# ===========================================================================
# RED 理由: 現在の bats は sed -n '/Security gate/,/^## /p' "$SKILL_MD" で
#           SKILL.md 本体を直接 grep している。refs/ ファイルへの変更が未実施。
# ===========================================================================

@test "ac7: su-observer-security-gate.bats の grep 対象が refs/ ファイルを含む" {
  local gate_bats="$REPO_ROOT/tests/bats/scripts/su-observer-security-gate.bats"

  [[ -f "$gate_bats" ]] \
    || fail "su-observer-security-gate.bats が見つからない: $gate_bats"

  # refs/su-observer-security-gate.md への参照が bats 内に存在するか
  grep -qE "refs/su-observer-security-gate\.md" "$gate_bats" \
    || fail "su-observer-security-gate.bats が refs/su-observer-security-gate.md を参照していない（AC7: bats refactor が必要）"
}

@test "ac7: su-observer-security-gate.bats が SKILL.md 本体のみを直接 grep していない" {
  local gate_bats="$REPO_ROOT/tests/bats/scripts/su-observer-security-gate.bats"

  [[ -f "$gate_bats" ]] \
    || fail "su-observer-security-gate.bats が見つからない: $gate_bats"

  # sed -n '/Security gate/,/^## /p' "$SKILL_MD" パターンが残っていないこと
  # refactor 後は refs/ ファイルを参照しているはずなので、
  # 旧パターンの SKILL_MD 直接 sed が 0 件であること
  local old_pattern_count=0
  if grep -qE "sed.*Security gate.*SKILL_MD|SKILL_MD.*Security gate" "$gate_bats" 2>/dev/null; then
    old_pattern_count=$(grep -cE "sed.*Security gate.*SKILL_MD|SKILL_MD.*Security gate" "$gate_bats" 2>/dev/null)
  fi

  [[ "$old_pattern_count" -eq 0 ]] \
    || fail "su-observer-security-gate.bats に旧 grep パターン（SKILL_MD 直接 sed）が ${old_pattern_count} 件残存（AC7: refs/ へのリダイレクトが必要）"
}

# ===========================================================================
# AC8: 7 件の su-observer bats ファイルが全て存在すること（smoke）
# ===========================================================================
# RED 理由: AC7 の bats refactor が完了していない現状では
#           su-observer-security-gate.bats の内容が不整合。
#           smoke として全ファイル存在チェックを実装。
# ===========================================================================

@test "ac8: smoke: su-observer-heartbeat-watcher.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-heartbeat-watcher.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer-pilot-signals.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-pilot-signals.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer-pr-merge-query.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-pr-merge-query.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer-security-gate.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-security-gate.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer-specialist-audit-grep.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-specialist-audit-grep.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer-step0-ambient.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-step0-ambient.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer-window-check.bats が存在する" {
  local bats_file="$REPO_ROOT/tests/bats/scripts/su-observer-window-check.bats"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: $bats_file（AC8: smoke check 失敗）"
}

@test "ac8: smoke: su-observer bats ファイルが合計 7 件存在する" {
  local -a expected_bats=(
    "su-observer-heartbeat-watcher.bats"
    "su-observer-pilot-signals.bats"
    "su-observer-pr-merge-query.bats"
    "su-observer-security-gate.bats"
    "su-observer-specialist-audit-grep.bats"
    "su-observer-step0-ambient.bats"
    "su-observer-window-check.bats"
  )
  local bats_dir="$REPO_ROOT/tests/bats/scripts"
  local missing_count=0
  local missing_list=""

  for bats_file in "${expected_bats[@]}"; do
    if [[ ! -f "$bats_dir/$bats_file" ]]; then
      missing_count=$((missing_count + 1))
      missing_list="${missing_list} ${bats_file}"
    fi
  done

  [[ "$missing_count" -eq 0 ]] \
    || fail "su-observer bats ファイルが ${missing_count} 件欠損:${missing_list}"
}

@test "ac8: smoke: su-observer-security-gate.bats が refs/ 対応済みであること（AC7 と整合）" {
  local gate_bats="$REPO_ROOT/tests/bats/scripts/su-observer-security-gate.bats"

  [[ -f "$gate_bats" ]] \
    || fail "su-observer-security-gate.bats が存在しない（AC8 前提条件未達）"

  # AC7 と同じ判定: refs/ 参照が存在すること
  grep -qE "refs/su-observer-security-gate\.md" "$gate_bats" \
    || fail "su-observer-security-gate.bats が refs/ 対応未完了（AC8: AC7 の refactor と整合しない）"
}
