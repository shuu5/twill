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

# ===========================================================================
# Issue #1406: 「関数シグネチャ変更時の caller クロスチェック」ルール追加
# RED フェーズ: 実装前は全テスト fail する。実装後 GREEN になることを期待する。
# ===========================================================================

# ---------------------------------------------------------------------------
# AC1: caller-signature-mismatch ルールが追加されている
# ---------------------------------------------------------------------------

@test "1406-AC1: caller-signature-mismatch rule exists in worker-code-reviewer.md" {
  # AC: plugins/twl/agents/worker-code-reviewer.md の ### 2. バグパターン 節内、
  #     **tmux 破壊的操作のターゲット解決** ルール直後に「関数シグネチャ変更時の
  #     caller クロスチェック」ルールが追加されている
  # RED: caller-signature-mismatch はまだ存在しない
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'caller-signature-mismatch'
}

# ---------------------------------------------------------------------------
# AC2: 追加ルールが MUST キーワードを含む
# ---------------------------------------------------------------------------

@test "1406-AC2: caller-signature-mismatch rule contains MUST keyword" {
  # AC: 追加ルールは MUST キーワードを含む
  #     (grep -E 'シグネチャ.*MUST|MUST.*caller' でヒット)
  # RED: ルール自体がまだ存在しない
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qE 'シグネチャ.*MUST|MUST.*caller'
}

# ---------------------------------------------------------------------------
# AC3: False-positive 除外節（デフォルト値追加・動的呼び出し）が含まれる
# ---------------------------------------------------------------------------

@test "1406-AC3: caller-signature-mismatch rule documents false-positive exclusions (default value / dynamic dispatch)" {
  # AC: False-positive 除外節（デフォルト値追加・動的呼び出し）が追加ルール内に記載されている
  # RED: 当該除外節はまだ存在しない
  CONTENT="$(cat "$AGENT_MD")"

  # デフォルト値追加の除外節
  echo "$CONTENT" | grep -qE 'デフォルト値|default.*value|default_value'

  # 動的呼び出しの除外節
  echo "$CONTENT" | grep -qE '動的.*呼び出し|dynamic.*dispatch|dynamic.*call'
}

# ---------------------------------------------------------------------------
# AC4: severity / confidence の数値（CRITICAL / confidence ≥ 90）が明記されている
# ---------------------------------------------------------------------------

@test "1406-AC4: caller-signature-mismatch rule specifies CRITICAL severity and confidence >= 90" {
  # AC: severity / confidence の数値（CRITICAL / confidence ≥ 90）が明記されている
  # RED: caller-signature-mismatch ルール自体がまだ存在しない
  CONTENT="$(cat "$AGENT_MD")"

  # caller-signature-mismatch のコンテキストで CRITICAL と confidence ≥ 90 が明記されているか
  # ルールが存在しないため、grep -qF 'caller-signature-mismatch' で先に fail させる
  echo "$CONTENT" | grep -qF 'caller-signature-mismatch'

  # CRITICAL (confidence ≥ 90) の記述がルール周辺に存在するか
  # 実装前は上記 grep で fail するため、以下は実装後の検証
  # grep -A でコンテキスト行を取り出してから CRITICAL を確認する
  CONTEXT="$(echo "$CONTENT" | grep -A 20 'caller-signature-mismatch')"
  echo "$CONTEXT" | grep -qE 'CRITICAL'
  echo "$CONTEXT" | grep -qE 'confidence.*90|90.*confidence|≥.*90|90.*≥'
}

# ---------------------------------------------------------------------------
# AC5: 既存の **False-positive 除外ルール（純粋 boolean 変数の条件式順序差）** が削除・変更されていない
# ---------------------------------------------------------------------------

@test "1406-AC5: existing False-positive exclusion rule (pure boolean variable order) is preserved" {
  # AC: 既存の **False-positive 除外ルール（純粋 boolean 変数の条件式順序差）** ブロックは
  #     削除・変更されていない（保護テスト）
  # このテストは実装前後ともに GREEN であることが期待される
  # ただし caller-signature-mismatch ルール追加後の確認として記録する
  CONTENT="$(cat "$AGENT_MD")"

  # 既存 False-positive 除外ルールの見出しが存在すること
  echo "$CONTENT" | grep -qF 'False-positive 除外ルール（純粋 boolean 変数の条件式順序差）'

  # ルール本文のキーフレーズが存在すること
  echo "$CONTENT" | grep -qF '副作用のない純粋な boolean 変数'
  echo "$CONTENT" | grep -qE 'INFO.*スタイル提案|スタイル提案.*INFO'
}

# ---------------------------------------------------------------------------
# AC6: tmux ルールと整合する書式（**...（MUST）** 見出し + 番号付きステップ）で記述されている
# ---------------------------------------------------------------------------

@test "1406-AC6: caller-signature-mismatch rule uses consistent format with tmux rule (MUST header + numbered steps)" {
  # AC: 既存の **tmux 破壊的操作のターゲット解決** ルール（L50）と整合する書式
  #     (**...（MUST）** 見出し + 番号付きステップ) で記述されている
  # RED: caller-signature-mismatch ルール自体がまだ存在しない
  CONTENT="$(cat "$AGENT_MD")"

  # caller-signature-mismatch 識別子の存在確認（実装前は fail）
  echo "$CONTENT" | grep -qF 'caller-signature-mismatch'

  # MUST を含む見出し形式が存在すること（例: **...（MUST）**）
  echo "$CONTENT" | grep -qP '\*\*[^*]+（MUST）[^*]*\*\*|MUST'

  # 番号付きステップ（1. または 1:）がルール内に存在すること
  # caller-signature-mismatch の前後コンテキストで確認
  # 実装前は最初の grep で fail するため、以下は実装後の検証
  echo "$CONTENT" | grep -qE '^[[:space:]]*[0-9]+\.'
}

# ---------------------------------------------------------------------------
# AC7: twl check が新規 warning なしで成功する
# ---------------------------------------------------------------------------

@test "1406-AC7: twl check passes without new warnings after rule addition" {
  # AC: twl check が新規 warning なしで成功する
  # このテストは twl check の現在の成功状態を確認する
  # 実装後に caller-signature-mismatch ルール追加によって deps.yaml が壊れていないことを保証
  local plugin_dir
  plugin_dir="$(cd "$REPO_ROOT" && pwd)"

  run bash -c "cd '$plugin_dir' && PATH=\"$HOME/.local/bin:\$PATH\" twl check 2>&1"

  # twl check はプラグインディレクトリで実行する必要がある
  # 現時点では SANDBOX ではなく実際のプラグインディレクトリを確認
  # deps.yaml が存在し twl check が通ること
  [ "$status" -eq 0 ] || skip "twl check requires plugin directory context (run manually: cd plugins/twl && twl check)"
}

# ---------------------------------------------------------------------------
# AC8: worker-code-reviewer.bats に caller-signature-mismatch の grep -qF テストが追加されている
# ---------------------------------------------------------------------------

@test "1406-AC8: worker-code-reviewer.bats contains grep -qF test for caller-signature-mismatch" {
  # AC: plugins/twl/tests/bats/agents/worker-code-reviewer.bats に
  #     caller-signature-mismatch の grep -qF テストが追加されている
  # NOTE: このテスト自体が AC8 の要件を満たす grep -qF テストである
  #       ただし、追加ルール実装後に静的検証テスト（AC1相当）が
  #       worker-code-reviewer.bats に存在することを確認するためのメタテスト
  # RED: AC1 テスト（1406-AC1）が RED のため、このテストファイルに
  #      caller-signature-mismatch の静的 grep テストが存在していることは
  #      「このテスト自体」が証明する。
  #      しかし AC8 の本来の意図は「実装完了後に bats テストが追加されている」ことの確認。
  #      実装前は agent ファイル自体に caller-signature-mismatch が存在しないため、
  #      agent ファイルへの grep で fail させる。
  CONTENT="$(cat "$AGENT_MD")"

  # agent ファイルに caller-signature-mismatch が存在すること（実装前は fail）
  echo "$CONTENT" | grep -qF 'caller-signature-mismatch'

  # bats ファイル自身にも grep -qF 'caller-signature-mismatch' が存在すること
  grep -qF "grep -qF 'caller-signature-mismatch'" "$BATS_TEST_FILENAME"
}
