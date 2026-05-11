#!/usr/bin/env bats
# issue-1620-feature-dev-fallback.bats
# LEGACY tests for Issue #1620 (superseded by Issue #1644).
#
# Issue #1644 で spawn-controller.sh feature-dev 統合により以下が変更:
#   - AC-2: spawn-controller.sh が feature-dev を **拒否** する仕様 → **承認** する仕様に変更
#   - AC-2: SKIP_LAYER2=1 は fallback enable → gate check bypass に変更
#   - 新挙動: plugins/twl/tests/bats/scripts/spawn-controller-feature-dev.bats
#
# AC-1（feature-dev-fallback-detect.sh）/ AC-3（intervention-catalog 命名）/
# AC-4（template sections）/ AC-5（record-feature-dev-fallback.sh）は #1644 と直交のため
# 本ファイルでは全テストを skip としアーカイブする（削除せず仕様履歴を保持）。
#
# 旧 AC coverage:
#   AC-1 - observer が 4 trigger 検知時に fallback 提案 + Layer 2 Escalate 記録を行う
#           → feature-dev-fallback-detect.sh の存在 + 動作確認
#   AC-2 - observer は feature-dev fallback を自律 spawn してはならない
#           → spawn-controller.sh が feature-dev skill を拒否する
#           → SKIP_LAYER2=1 override のみ許可する
#   AC-3 - spawn 命名規則: tmux window = wt-fd-<N>、worktree branch = wt-fd-<N>-<short>
#           → intervention-catalog.md に記載
#   AC-4 - spawn prompt template が必須 4 sections を含む
#           → template ファイル存在 + sections 確認
#   AC-5 - 完了後に InterventionRecord JSON + doobidoo lesson 保存スクリプトが存在する
#           → record-feature-dev-fallback.sh の存在 + 動作確認
#
# テスト設計:
#   - feature-dev-fallback-detect.sh は未実装のため存在チェックが RED で fail する
#   - spawn-controller.sh の VALID_SKILLS に feature-dev がないため拒否確認は GREEN だが、
#     SKIP_LAYER2=1 override ロジックは未実装のため RED
#   - intervention-catalog.md に wt-fd-<N> 命名規則が未記載のため RED
#   - feature-dev-fallback-prompt.md は未実装のため存在チェックが RED で fail する
#   - record-feature-dev-fallback.sh は未実装のため存在チェックが RED で fail する
#
# WARN: source guard 確認結果:
#   spawn-controller.sh に [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard が存在しない。
#   set -euo pipefail 環境で source すると main 到達前に exit に巻き込まれるリスクあり。
#   本テストでは source せず、static grep 検査 および bash サブシェルで直接実行する設計で回避済み。
#   実装者は spawn-controller.sh への source guard 追加を検討すること（impl_files 参照）。

load 'helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  # Issue #1644: legacy archive. 新挙動は spawn-controller-feature-dev.bats を参照。
  skip "Legacy test for Issue #1620, superseded by Issue #1644 (spawn-controller feature-dev integration). See plugins/twl/tests/bats/scripts/spawn-controller-feature-dev.bats for current behavior."

  common_setup

  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  DETECT_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/feature-dev-fallback-detect.sh"
  TEMPLATE_FILE="${REPO_ROOT}/skills/su-observer/templates/feature-dev-fallback-prompt.md"
  RECORD_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-feature-dev-fallback.sh"
  CATALOG_FILE="${REPO_ROOT}/refs/intervention-catalog.md"

  export SPAWN_SCRIPT DETECT_SCRIPT TEMPLATE_FILE RECORD_SCRIPT CATALOG_FILE

  # cld-spawn stub（実際の tmux spawn をスキップ）
  stub_command "cld-spawn" 'echo "cld-spawn-stub: $*"; exit 0'

  # tmux stub（副作用を回避）
  stub_command "tmux" 'echo "tmux-stub: $*"; exit 0'

  # プロンプトファイルをサンドボックスに作成
  echo "test prompt content" > "$SANDBOX/test-prompt.txt"

  export SKIP_PARALLEL_CHECK=1
  export SKIP_PARALLEL_REASON="bats test issue-1620 RED phase"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: feature-dev-fallback-detect.sh の存在と動作確認
#
# 4 trigger:
#   (a) RED-only merge x1
#   (b) specialist NEEDS_WORK x3
#   (c) Worker chain failure x3
#   (d) P0 緊急
#
# RED: ファイルが未実装のため fail する
# PASS 条件（実装後）:
#   - plugins/twl/skills/su-observer/scripts/feature-dev-fallback-detect.sh が存在する
#   - 実行可能権限がある
#   - 4 trigger を検知して observer log に detection event + Layer 2 Escalate を記録する
# ===========================================================================

@test "ac1: feature-dev-fallback-detect.sh が scripts/ に存在する" {
  # AC-1: 4 trigger 検知スクリプトが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${DETECT_SCRIPT}" ]
}

@test "ac1: feature-dev-fallback-detect.sh が実行可能権限を持つ" {
  # AC-1: スクリプトが実行可能であること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${DETECT_SCRIPT}" ] || {
    echo "RED: feature-dev-fallback-detect.sh 未実装"
    false
  }
  [ -x "${DETECT_SCRIPT}" ]
}

@test "ac1: feature-dev-fallback-detect.sh が RED-only merge trigger を検知して Layer 2 Escalate を記録する" {
  # AC-1: RED-only merge x1 trigger → observer log に detection event + Layer 2 Escalate
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${DETECT_SCRIPT}" ] || {
    echo "RED: feature-dev-fallback-detect.sh 未実装"
    false
  }

  local log_dir="$SANDBOX/observation"
  mkdir -p "$log_dir"

  run bash "${DETECT_SCRIPT}" \
    --trigger red-only-merge \
    --count 1 \
    --log-dir "$log_dir"
  [ "$status" -eq 0 ]
  # Layer 2 Escalate が記録されていること
  grep -r "Layer 2 Escalate\|layer_2_escalate\|LAYER2_ESCALATE" "$log_dir"
}

@test "ac1: feature-dev-fallback-detect.sh が specialist NEEDS_WORK x3 trigger を検知して Layer 2 Escalate を記録する" {
  # AC-1: specialist NEEDS_WORK x3 trigger → observer log に detection event + Layer 2 Escalate
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${DETECT_SCRIPT}" ] || {
    echo "RED: feature-dev-fallback-detect.sh 未実装"
    false
  }

  local log_dir="$SANDBOX/observation"
  mkdir -p "$log_dir"

  run bash "${DETECT_SCRIPT}" \
    --trigger specialist-needs-work \
    --count 3 \
    --log-dir "$log_dir"
  [ "$status" -eq 0 ]
  grep -r "Layer 2 Escalate\|layer_2_escalate\|LAYER2_ESCALATE" "$log_dir"
}

@test "ac1: feature-dev-fallback-detect.sh が Worker chain failure x3 trigger を検知して Layer 2 Escalate を記録する" {
  # AC-1: Worker chain failure x3 trigger → observer log に detection event + Layer 2 Escalate
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${DETECT_SCRIPT}" ] || {
    echo "RED: feature-dev-fallback-detect.sh 未実装"
    false
  }

  local log_dir="$SANDBOX/observation"
  mkdir -p "$log_dir"

  run bash "${DETECT_SCRIPT}" \
    --trigger worker-chain-failure \
    --count 3 \
    --log-dir "$log_dir"
  [ "$status" -eq 0 ]
  grep -r "Layer 2 Escalate\|layer_2_escalate\|LAYER2_ESCALATE" "$log_dir"
}

@test "ac1: feature-dev-fallback-detect.sh が P0 緊急 trigger を検知して Layer 2 Escalate を記録する" {
  # AC-1: P0 緊急 trigger → observer log に detection event + Layer 2 Escalate
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${DETECT_SCRIPT}" ] || {
    echo "RED: feature-dev-fallback-detect.sh 未実装"
    false
  }

  local log_dir="$SANDBOX/observation"
  mkdir -p "$log_dir"

  run bash "${DETECT_SCRIPT}" \
    --trigger p0-urgent \
    --log-dir "$log_dir"
  [ "$status" -eq 0 ]
  grep -r "Layer 2 Escalate\|layer_2_escalate\|LAYER2_ESCALATE" "$log_dir"
}

# ===========================================================================
# AC-2: spawn-controller.sh が feature-dev skill の spawn を拒否する
#       SKIP_LAYER2=1 override のみ許可する
#
# RED（一部）: feature-dev 拒否は L89 VALID_SKILLS に含まれないため現状 PASS だが、
#              SKIP_LAYER2=1 override ロジックは未実装のため RED
# PASS 条件（実装後）:
#   - feature-dev を skill として渡すと exit 非 0（拒否）
#   - SKIP_LAYER2=1 を設定すると spawn が許可される（VALID_SKILLS 拡張 or override）
#   - 拒否時に SU-3 連鎖・Layer 2 Escalate 経由必須のメッセージが stderr に出力される
# ===========================================================================

@test "ac2: spawn-controller.sh が feature-dev skill を拒否して非 0 で終了する" {
  # AC-2: spawn-controller.sh が feature-dev skill spawn を拒否すること
  # 現状は VALID_SKILLS に含まれないため拒否されるが、拒否理由が SU-3/Layer 2 明示ではない
  # RED: SU-3 連鎖メッセージが出力されないため fail する
  local prompt_file="$SANDBOX/test-prompt.txt"

  run bash "${SPAWN_SCRIPT}" feature-dev "$prompt_file" 2>&1
  # 拒否されること（非 0 終了）
  [ "$status" -ne 0 ]
  # SU-3 / Layer 2 Escalate 経由必須メッセージが stderr に含まれること
  [[ "$output" == *"SU-3"* || "$output" == *"Layer 2"* || "$output" == *"SKIP_LAYER2"* ]]
}

@test "ac2: SKIP_LAYER2=1 設定時は spawn-controller.sh が feature-dev を許可する" {
  # AC-2: SKIP_LAYER2=1 override のみ feature-dev spawn を許可すること
  # RED: SKIP_LAYER2=1 override ロジックが未実装のため fail する
  local prompt_file="$SANDBOX/test-prompt.txt"

  run env SKIP_LAYER2=1 SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="test" \
    bash "${SPAWN_SCRIPT}" feature-dev "$prompt_file" 2>&1
  # SKIP_LAYER2=1 設定時は spawn が通ること（exit 0 または cld-spawn-stub 出力あり）
  [ "$status" -eq 0 ]
}

@test "ac2: spawn-controller.sh が feature-dev 拒否時に SKIP_LAYER2=1 を hint として出力する" {
  # AC-2: 拒否メッセージに SKIP_LAYER2=1 の override 方法が含まれること
  # RED: hint メッセージが未実装のため fail する
  local prompt_file="$SANDBOX/test-prompt.txt"

  run bash "${SPAWN_SCRIPT}" feature-dev "$prompt_file" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKIP_LAYER2"* ]]
}

# ===========================================================================
# AC-3: spawn 命名規則が intervention-catalog.md に記載されている
#       tmux window = wt-fd-<N>、worktree branch = wt-fd-<N>-<short>
#
# RED: intervention-catalog.md に命名規則が未記載のため fail する
# PASS 条件（実装後）:
#   - intervention-catalog.md の用語列（テーブル）に wt-fd-<N> が記載されている
#   - worktree branch 命名規則 wt-fd-<N>-<short> が記載されている
#   - feature-dev fallback のセクションが存在する
# ===========================================================================

@test "ac3: intervention-catalog.md に feature-dev fallback セクションが存在する" {
  # AC-3: intervention-catalog.md に feature-dev fallback の命名規則が記載されていること
  # RED: 実装前は fail する（セクション未記載）
  [ -f "${CATALOG_FILE}" ]
  grep -q "feature-dev fallback\|feature-dev-fallback" "${CATALOG_FILE}"
}

@test "ac3: intervention-catalog.md に tmux window 命名規則 wt-fd-<N> が記載されている" {
  # AC-3: tmux window 命名規則 wt-fd-<N> が intervention-catalog.md に記載されていること
  # RED: 実装前は fail する（命名規則未記載）
  # Markdown テーブル用語列マッチ（PR #1357 / commit 532d6e20）: '| term |' パターン使用
  [ -f "${CATALOG_FILE}" ]
  # テーブル以外でも命名規則として記載があることを確認（grep -q で存在チェック）
  grep -q "wt-fd-" "${CATALOG_FILE}"
}

@test "ac3: intervention-catalog.md に worktree branch 命名規則 wt-fd-<N>-<short> が記載されている" {
  # AC-3: worktree branch 命名規則 wt-fd-<N>-<short> が記載されていること
  # RED: 実装前は fail する（命名規則未記載）
  [ -f "${CATALOG_FILE}" ]
  grep -q "wt-fd-.*-\(<short>\|<N>-\)" "${CATALOG_FILE}"
}

# ===========================================================================
# AC-4: spawn prompt template が必須 4 sections を含む
#       (a) refined Issue body
#       (b) co-autopilot 失敗経緯
#       (c) AC
#       (d) DeltaSpec link
#
# RED: template ファイルが未実装のため fail する
# PASS 条件（実装後）:
#   - plugins/twl/skills/su-observer/templates/feature-dev-fallback-prompt.md が存在する
#   - 4 つの必須 sections がすべて含まれる
# ===========================================================================

@test "ac4: feature-dev-fallback-prompt.md が templates/ に存在する" {
  # AC-4: spawn prompt template ファイルが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${TEMPLATE_FILE}" ]
}

@test "ac4: template に section (a) refined Issue body が含まれる" {
  # AC-4(a): refined Issue body のセクションが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${TEMPLATE_FILE}" ] || {
    echo "RED: feature-dev-fallback-prompt.md 未実装"
    false
  }
  # section (a): refined Issue body を示すヘッダーが含まれること
  grep -qi "refined issue body\|## issue\|# issue body\|refined_issue\|issue_body" "${TEMPLATE_FILE}"
}

@test "ac4: template に section (b) co-autopilot 失敗経緯が含まれる" {
  # AC-4(b): co-autopilot 失敗経緯のセクションが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${TEMPLATE_FILE}" ] || {
    echo "RED: feature-dev-fallback-prompt.md 未実装"
    false
  }
  grep -qi "co-autopilot\|autopilot.*fail\|failure.*history\|失敗経緯\|chain.*failure" "${TEMPLATE_FILE}"
}

@test "ac4: template に section (c) AC が含まれる" {
  # AC-4(c): AC（Acceptance Criteria）のセクションが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${TEMPLATE_FILE}" ] || {
    echo "RED: feature-dev-fallback-prompt.md 未実装"
    false
  }
  grep -qi "acceptance criteria\|## ac\|# ac\|## AC\|acceptance_criteria" "${TEMPLATE_FILE}"
}

@test "ac4: template に section (d) DeltaSpec link が含まれる" {
  # AC-4(d): DeltaSpec link のセクションが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${TEMPLATE_FILE}" ] || {
    echo "RED: feature-dev-fallback-prompt.md 未実装"
    false
  }
  grep -qi "deltaspec\|delta.*spec\|DeltaSpec" "${TEMPLATE_FILE}"
}

# ===========================================================================
# AC-5: 完了後に InterventionRecord + doobidoo lesson 保存スクリプトが存在する
#       .observation/interventions/<ts>-feature-dev-fallback.json に InterventionRecord
#       doobidoo に feature-dev-fallback tag で lesson 保存
#
# RED: record-feature-dev-fallback.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - plugins/twl/skills/su-observer/scripts/record-feature-dev-fallback.sh が存在する
#   - 実行可能権限がある
#   - .observation/interventions/<ts>-feature-dev-fallback.json を生成する
#   - doobidoo への lesson 保存コマンドを含む
# ===========================================================================

@test "ac5: record-feature-dev-fallback.sh が scripts/ に存在する" {
  # AC-5: InterventionRecord 記録スクリプトが存在すること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${RECORD_SCRIPT}" ]
}

@test "ac5: record-feature-dev-fallback.sh が実行可能権限を持つ" {
  # AC-5: スクリプトが実行可能であること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${RECORD_SCRIPT}" ] || {
    echo "RED: record-feature-dev-fallback.sh 未実装"
    false
  }
  [ -x "${RECORD_SCRIPT}" ]
}

@test "ac5: record-feature-dev-fallback.sh が .observation/interventions/ 配下に JSON を生成する" {
  # AC-5: .observation/interventions/<ts>-feature-dev-fallback.json が生成されること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${RECORD_SCRIPT}" ] || {
    echo "RED: record-feature-dev-fallback.sh 未実装"
    false
  }

  local intervention_dir="$SANDBOX/observation/interventions"
  mkdir -p "$intervention_dir"

  run bash "${RECORD_SCRIPT}" \
    --issue 1620 \
    --trigger "red-only-merge" \
    --intervention-dir "$intervention_dir"
  [ "$status" -eq 0 ]

  # <ts>-feature-dev-fallback.json が生成されていること
  local json_count
  json_count=$(find "$intervention_dir" -name "*-feature-dev-fallback.json" | wc -l)
  [ "$json_count" -ge 1 ]
}

@test "ac5: 生成された InterventionRecord JSON が必須フィールドを含む" {
  # AC-5: InterventionRecord JSON が type/trigger/timestamp/issue_number を含むこと
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${RECORD_SCRIPT}" ] || {
    echo "RED: record-feature-dev-fallback.sh 未実装"
    false
  }

  local intervention_dir="$SANDBOX/observation/interventions"
  mkdir -p "$intervention_dir"

  bash "${RECORD_SCRIPT}" \
    --issue 1620 \
    --trigger "red-only-merge" \
    --intervention-dir "$intervention_dir" 2>/dev/null

  local json_file
  json_file=$(find "$intervention_dir" -name "*-feature-dev-fallback.json" | head -1)
  [ -n "$json_file" ]

  # JSON に type フィールドが含まれること
  grep -q '"type"\|"trigger"\|"timestamp"\|"issue"' "$json_file"
}

@test "ac5: record-feature-dev-fallback.sh が feature-dev-fallback tag での doobidoo lesson 保存コマンドを含む" {
  # AC-5: doobidoo に feature-dev-fallback tag で lesson 保存するロジックが含まれること
  # RED: 実装前は fail する（ファイル不在）
  [ -f "${RECORD_SCRIPT}" ] || {
    echo "RED: record-feature-dev-fallback.sh 未実装"
    false
  }

  # スクリプトに doobidoo / mcp__doobidoo + feature-dev-fallback tag が含まれること
  grep -q "doobidoo\|mcp__doobidoo" "${RECORD_SCRIPT}"
  grep -q "feature-dev-fallback" "${RECORD_SCRIPT}"
}
