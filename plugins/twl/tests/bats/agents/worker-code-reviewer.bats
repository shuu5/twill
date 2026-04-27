#!/usr/bin/env bats
# worker-code-reviewer.bats - agent .md の静的検証 (3 test cases)
# Issue #950: AC 整合性 (existing-behavior-preserve) セクション追加
#
# RED フェーズ: 実装前は全テスト fail する。
# 実装後 GREEN になることを期待する。

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/worker-code-reviewer.md"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# A1: 「### 4. AC 整合性 (existing-behavior-preserve)」サブセクション存在確認
# ---------------------------------------------------------------------------

@test "worker-code-reviewer has subsection '### 4. AC 整合性 (existing-behavior-preserve)' under レビュー観点" {
  # AC: 「## レビュー観点」セクションに新サブセクション
  #     「### 4. AC 整合性 (existing-behavior-preserve)」を追加する
  CONTENT="$(cat "$AGENT_MD")"

  echo "$CONTENT" | grep -qF '### 4. AC 整合性 (existing-behavior-preserve)'
}

# ---------------------------------------------------------------------------
# A2: 新サブセクション内にキーワード・3ステップ・False-positive 除外規則が存在するか
# ---------------------------------------------------------------------------

@test "worker-code-reviewer AC 整合性 subsection documents required keywords and 3-step check" {
  # AC: 新サブセクション内に以下を MUST として明記する:
  #   - キーワード検出リスト（維持/保持/のまま/変えない/踏襲/preserve/remain/still/keep unchanged/no change）
  #   - 整合性チェック 3 ステップ（AC 条件構造化 → diff 関連実装の Grep 特定 → 逆転・削除・上書きの確認）
  #   - False-positive 除外規則（既存動作への言及が無い AC は対象外）
  CONTENT="$(cat "$AGENT_MD")"

  # キーワード検出リスト（日本語・英語の代表例を確認）
  echo "$CONTENT" | grep -qF '維持'
  echo "$CONTENT" | grep -qF '保持'
  echo "$CONTENT" | grep -qF 'preserve'
  echo "$CONTENT" | grep -qF 'remain'
  echo "$CONTENT" | grep -qF 'keep'
  echo "$CONTENT" | grep -qF 'no change'

  # 整合性チェック 3 ステップ（キーフレーズ確認）
  echo "$CONTENT" | grep -qE 'AC.*条件.*構造化|条件.*構造化'
  echo "$CONTENT" | grep -qE 'Grep|grep'
  echo "$CONTENT" | grep -qE '逆転|削除|上書き'

  # False-positive 除外規則
  echo "$CONTENT" | grep -qE 'False.positive|false.positive|偽陽性'
  echo "$CONTENT" | grep -qE '対象外|除外'
}

# ---------------------------------------------------------------------------
# A3: 信頼度スコアリング部に existing-behavior-preserve 違反の CRITICAL 報告明記
# ---------------------------------------------------------------------------

@test "worker-code-reviewer confidence scoring documents existing-behavior-preserve as CRITICAL confidence>=90" {
  # AC: 信頼度スコアリング部に
  #     「existing-behavior-preserve 違反は CRITICAL (confidence >= 90) で報告」を明記する
  CONTENT="$(cat "$AGENT_MD")"

  # existing-behavior-preserve という識別子が信頼度スコアリングのコンテキストで言及されているか
  echo "$CONTENT" | grep -qF 'existing-behavior-preserve'

  # CRITICAL と confidence >= 90 (または 90) が同一ドキュメント内に存在するか
  echo "$CONTENT" | grep -qE 'CRITICAL'
  echo "$CONTENT" | grep -qE 'confidence.*90|90.*confidence'
}
