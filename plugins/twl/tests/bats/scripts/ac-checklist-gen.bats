#!/usr/bin/env bats
# ac-checklist-gen.bats - unit tests for scripts/ac-checklist-gen.sh
#
# Spec: Issue #167 — AC 矮小化: PR 外副作用（Issue コメント・ドキュメント更新）の verify 漏れ
#
# Coverage:
#   1. 正常系: 標準的な AC リスト (4 項目) を抽出し checkbox 形式で出力する
#   2. 副作用検出: 「Issue にコメント」を含む AC 項目に [!] マーカーが付与される
#   3. 副作用検出: 「README」を含む AC 項目に [!] マーカーが付与される
#   4. フォールバック: `## 受け入れ基準` セクション不在の Issue に対し非ゼロ exit + stderr メッセージ

load '../helpers/common'

setup() {
  common_setup

  # Copy ac-checklist-gen.sh into sandbox scripts
  cp "$REPO_ROOT/scripts/ac-checklist-gen.sh" "$SANDBOX/scripts/"
  chmod +x "$SANDBOX/scripts/ac-checklist-gen.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Test 1: 正常系 — 標準的な AC リスト (4 項目) を checkbox 形式で出力する
# ---------------------------------------------------------------------------

@test "正常系: 4 項目の AC を checkbox 形式で出力する" {
  stub_command "gh" '
    echo "## 受け入れ基準"
    echo ""
    echo "- [ ] スクリプトが作成される"
    echo "- [ ] テストが追加される"
    echo "- [ ] deps.yaml が更新される"
    echo "- [ ] twl check が PASS する"
  '

  run bash "$SANDBOX/scripts/ac-checklist-gen.sh" 167
  assert_success
  assert_output --partial "# AC Checklist for Issue #167"
  assert_output --partial "- [ ] スクリプトが作成される"
  assert_output --partial "- [ ] テストが追加される"
  assert_output --partial "- [ ] deps.yaml が更新される"
  assert_output --partial "- [ ] twl check が PASS する"
}

# ---------------------------------------------------------------------------
# Test 2: 副作用検出 — 「Issue にコメント」を含む AC 項目に [!] マーカーが付与される
# ---------------------------------------------------------------------------

@test "副作用検出: 「Issue にコメント」を含む項目に [!] マーカーが付与される" {
  stub_command "gh" '
    echo "## 受け入れ基準"
    echo ""
    echo "- [ ] 通常の実装を行う"
    echo "- [ ] triage 表を本 Issue にコメントとして添付する"
  '

  run bash "$SANDBOX/scripts/ac-checklist-gen.sh" 142
  assert_success
  # 副作用ありの行に [!] が付与される
  assert_output --partial "[!]"
  assert_output --partial "Issue にコメント"
  # 通常項目には [!] が付かない
  echo "$output" | grep "通常の実装" | grep -qv "\[!\]"
}

# ---------------------------------------------------------------------------
# Test 3: 副作用検出 — 「README」を含む AC 項目に [!] マーカーが付与される
# ---------------------------------------------------------------------------

@test "副作用検出: 「README」を含む項目に [!] マーカーが付与される" {
  stub_command "gh" '
    echo "## 受け入れ基準"
    echo ""
    echo "- [ ] 機能を実装する"
    echo "- [ ] README を更新する"
  '

  run bash "$SANDBOX/scripts/ac-checklist-gen.sh" 100
  assert_success
  assert_output --partial "[!]"
  assert_output --partial "README"
}

# ---------------------------------------------------------------------------
# Test 4: フォールバック — `## 受け入れ基準` 不在で非ゼロ exit + stderr メッセージ
# ---------------------------------------------------------------------------

@test "フォールバック: 受け入れ基準セクション不在で非ゼロ exit と stderr メッセージ" {
  stub_command "gh" '
    echo "## 概要"
    echo ""
    echo "特に AC なし。"
  '

  run bash "$SANDBOX/scripts/ac-checklist-gen.sh" 999
  assert_failure
  # stderr にエラーメッセージが出力される
  assert_output --partial "受け入れ基準"
}
