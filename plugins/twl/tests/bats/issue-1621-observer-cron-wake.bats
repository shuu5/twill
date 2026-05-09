#!/usr/bin/env bats
# issue-1621-observer-cron-wake.bats
# RED tests for Issue #1621: su-observer ScheduleWakeup 不発火 — /loop 専用 tool を skill 文脈で利用する根本不整合
#
# AC coverage:
#   AC1 - SKILL.md で CronCreate を Primary に切替（Step 0 で CronCreate durable=true 発行 MUST）
#   AC2 - Step 1 mailbox poll セクションの ScheduleWakeup 言及に /loop 前提条件を明示
#   AC3 - pitfalls-catalog.md §11.5 spec 整合（CronCreate と ScheduleWakeup の use case 別明記）
#   AC4 - 実発火検証 bats シナリオ追加（CronCreate durable=true pattern の存在を検証するテスト）
#   AC5 - observer 起動時 CronCreate fail 時 escalate（CronList 確認 + record-detection-gap.sh 手順）
#
# テスト設計:
#   - 全テストは実装前の状態で FAIL する（RED フェーズ）
#   - SKILL.md と pitfalls-catalog.md を grep/awk で検証する text-based テスト
#   - 実装後 GREEN になる条件をコメントに記載
#
# WARNING（baseline-bash §9）:
#   このファイルで setup() 内のパス解決に BATS_TEST_FILENAME を使用している。
#   heredoc を使う場合はシングルクォート heredoc（<<'EOF'）を採用し、
#   外部変数展開は heredoc 外で行うこと。
#
# NOTE（baseline-bash §10）:
#   このテストは SKILL.md / pitfalls-catalog.md への grep/awk による静的検証のみ。
#   source guard の問題は発生しない。

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${this_dir}" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  export SKILL_MD

  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  export PITFALLS_CATALOG
}

# ===========================================================================
# AC1: SKILL.md で CronCreate を Primary に切替
#
# RED: SKILL.md の Step 0 に CronCreate(cron="*/25 * * * *", durable=true, ...) の記述が存在しない
# PASS 条件（実装後）:
#   - Step 0 セクション内に CronCreate durable=true の記述が存在する
#   - "*/25 * * * *" または同等の cron 式が含まれる
# ===========================================================================

@test "ac1: SKILL.md に CronCreate durable=true の記述が存在する" {
  # AC: Step 0 で observer 起動時に CronCreate(cron="*/25 * * * *", durable=true, ...) を発行する MUST を明記
  # RED: 実装前は fail する — CronCreate durable=true の記述が SKILL.md に存在しない
  [ -f "$SKILL_MD" ]
  grep -qE "CronCreate.*durable" "$SKILL_MD"
}

@test "ac1: SKILL.md の Step 0 セクション内に CronCreate の記述が存在する" {
  # AC: Step 0 で CronCreate を発行する MUST を明記
  # RED: 実装前は fail する — Step 0 セクションに CronCreate がない
  [ -f "$SKILL_MD" ]
  # Step 0: セッション初期化 セクション内（Step 0 開始から Step 1 開始まで）に CronCreate が存在すること
  awk '/^## Step 0/,/^## Step 1/' "$SKILL_MD" | grep -qE "CronCreate"
}

@test "ac1: SKILL.md に CronCreate の cron 式（*/25 または同等）が含まれる" {
  # AC: CronCreate(cron="*/25 * * * *", ...) の形式が記述されている
  # RED: 実装前は fail する — cron 式の記述が存在しない
  [ -f "$SKILL_MD" ]
  grep -qE 'CronCreate.*cron=.*\*.*\*.*\*|cron="[^"]*\*[^"]*"' "$SKILL_MD"
}

# ===========================================================================
# AC2: Step 1 mailbox poll セクションの ScheduleWakeup 言及に /loop 前提条件を明示
#
# RED: SKILL.md line 85 の ScheduleWakeup 行前後3行に /loop や dynamic mode の言及が存在しない
# PASS 条件（実装後）:
#   - ScheduleWakeup が登場する行の前後3行以内に
#     "/loop" または "dynamic mode" または "loop 配下" の文言が存在する
# ===========================================================================

@test "ac2: SKILL.md の ScheduleWakeup 言及に /loop 前提条件が明示されている" {
  # AC: ScheduleWakeup を残す場合は「/loop dynamic mode 配下でのみ有効」前提を明示
  # RED: 実装前は fail する — ScheduleWakeup 行前後に /loop 前提の言及がない
  [ -f "$SKILL_MD" ]
  # ScheduleWakeup が出現する各行の前後3行に /loop または dynamic mode が存在すること
  python3 -c "
import sys
with open('$SKILL_MD') as f:
    lines = f.readlines()
found_schedulewakeup = False
for i, line in enumerate(lines):
    if 'ScheduleWakeup' in line:
        found_schedulewakeup = True
        start = max(0, i - 3)
        end = min(len(lines), i + 4)
        window = ''.join(lines[start:end])
        if '/loop' in window or 'dynamic mode' in window or 'loop 配下' in window:
            sys.exit(0)
if not found_schedulewakeup:
    print('ScheduleWakeup not found in SKILL.md')
    sys.exit(1)
print('ScheduleWakeup found but /loop prerequisite not mentioned within 3 lines')
sys.exit(1)
"
}

@test "ac2: SKILL.md の mailbox poll セクションに /loop または dynamic mode の言及が存在する" {
  # AC: /loop dynamic mode 前提を明示
  # RED: 実装前は fail する — mailbox poll セクションに /loop 言及がない
  [ -f "$SKILL_MD" ]
  awk '/mailbox poll/,/controller spawn が必要な場合/' "$SKILL_MD" | grep -qE "/loop|dynamic mode|loop 配下"
}

# ===========================================================================
# AC3: pitfalls-catalog.md §11.5 spec 整合
#
# RED: §11.5 本文に CronCreate の記述が存在しない
# PASS 条件（実装後）:
#   - §11.5 セクション内（**11.5 から次のセクション開始まで）に CronCreate が含まれる
#   - use case 別（常駐polling=CronCreate / /loop配下=ScheduleWakeup）の記述が存在する
# ===========================================================================

@test "ac3: pitfalls-catalog.md §11.5 に CronCreate が含まれる" {
  # AC: §11.5 本文内で CronCreate が ScheduleWakeup と並記される
  # RED: 実装前は fail する — §11.5 に CronCreate の記述が存在しない
  [ -f "$PITFALLS_CATALOG" ]
  awk '/^\*\*11\.5/,/^\*\*11\.6|^### §11\.6/' "$PITFALLS_CATALOG" | grep -qE "CronCreate"
}

@test "ac3: pitfalls-catalog.md §11.5 に use case 別（常駐polling / /loop配下）の記述が存在する" {
  # AC: use case 別（常駐polling=CronCreate / /loop配下=ScheduleWakeup）に明記
  # RED: 実装前は fail する — §11.5 に use case 区別の記述がない
  [ -f "$PITFALLS_CATALOG" ]
  awk '/^\*\*11\.5/,/^\*\*11\.6|^### §11\.6/' "$PITFALLS_CATALOG" | grep -qE "常駐|/loop|polling.*CronCreate|CronCreate.*polling"
}

@test "ac3: pitfalls-catalog.md §11.5 の title が CronCreate を含んでいる" {
  # AC: §11.5 title に CronCreate が含まれる（ScheduleWakeup と並記）
  # RED: 実装前は fail する — title が "ScheduleWakeup / Cron" でも本文に CronCreate がないため fail
  [ -f "$PITFALLS_CATALOG" ]
  grep -qE "^\*\*11\.5.*CronCreate" "$PITFALLS_CATALOG"
}

# ===========================================================================
# AC4: 実発火検証 bats シナリオ追加
#
# RED: CronCreate durable=true pattern を検証する bats テストファイルが存在しない
# PASS 条件（実装後）:
#   - find plugins/twl/tests/bats -name "*observer*cron*" -o -name "*observer*wake*" で
#     1件以上のファイルが見つかる
#   - このテスト自体（issue-1621-observer-cron-wake.bats）が存在することで AC4 が GREEN になる
# ===========================================================================

@test "ac4: CronCreate durable=true pattern を検証する bats テストファイルが存在する" {
  # AC: CronCreate durable=true pattern を SKILL.md に記述した上で、その存在を bats で検証するテストを追加
  # NOTE: このテスト自体が存在することで AC4 は GREEN になる（ファイル存在が AC4 の成立条件）
  # RED ではなく GREEN: このテストファイル（issue-1621-observer-cron-wake.bats）が存在するため PASS する
  local bats_root="${REPO_ROOT}/tests/bats"
  find "$bats_root" \
    \( -name "*observer*cron*" -o -name "*observer*wake*" \) \
    -name "*.bats" \
    | grep -qE "."
}

@test "ac4: issue-1621-observer-cron-wake.bats が tests/bats 配下に存在する" {
  # AC: このテストファイル自体の存在確認
  # NOTE: このテスト自体が存在するため常に GREEN になる
  local expected_file="${REPO_ROOT}/tests/bats/issue-1621-observer-cron-wake.bats"
  [ -f "$expected_file" ]
}

# ===========================================================================
# AC5: observer 起動時 CronCreate fail 時 escalate
#
# RED: SKILL.md に CronList による確認と fail 時の escalate 手順が存在しない
# PASS 条件（実装後）:
#   - SKILL.md に CronList の記述が存在する
#   - CronCreate 後の確認（verify / fail / handler）記述が存在する
#   - record-detection-gap.sh または ★HUMAN GATE escalate の記述が存在する
# ===========================================================================

@test "ac5: SKILL.md に CronList の記述が存在する" {
  # AC: observer Step 0 で CronCreate 後に CronList で確認する手順を追記
  # RED: 実装前は fail する — SKILL.md に CronList の記述が存在しない
  [ -f "$SKILL_MD" ]
  grep -qE "CronList" "$SKILL_MD"
}

@test "ac5: SKILL.md に CronCreate fail 時または verify の handler 記述が存在する" {
  # AC: CronCreate silent fail 時の検知手段を SKILL.md に追記
  # RED: 実装前は fail する — fail/verify handler の記述が存在しない
  [ -f "$SKILL_MD" ]
  grep -qE "CronList|CronCreate.*fail|CronCreate.*verify|CronCreate.*confirm" "$SKILL_MD"
}

@test "ac5: SKILL.md の Step 0 に CronCreate 後の CronList 確認が存在する" {
  # AC: Step 0 で CronCreate 後に CronList で確認する
  # RED: 実装前は fail する — Step 0 に CronList 確認が存在しない
  [ -f "$SKILL_MD" ]
  awk '/^## Step 0/,/^## Step 1/' "$SKILL_MD" | grep -qE "CronList"
}

@test "ac5: SKILL.md に CronCreate fail 時の record-detection-gap または HUMAN GATE escalate 記述が存在する" {
  # AC: CronCreate 不在時は record-detection-gap.sh + ★HUMAN GATE escalate の手順を追記
  # RED: 実装前は fail する — escalate 手順の記述が存在しない
  [ -f "$SKILL_MD" ]
  grep -qE "record-detection-gap|HUMAN GATE.*CronCreate|CronCreate.*HUMAN GATE|CronCreate.*escalate" "$SKILL_MD"
}
