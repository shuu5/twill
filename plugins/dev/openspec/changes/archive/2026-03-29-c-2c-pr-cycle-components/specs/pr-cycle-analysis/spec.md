## ADDED Requirements

### Requirement: PR-cycle パターン分析

PR-cycle 完了後のセッションスナップショットを分析し、4 カテゴリ（prompt-quality, rule-gap, false-positive, autofix-repeat）で改善機会を検出しなければならない（SHALL）。

#### Scenario: パターン検出と信頼度算出
- **WHEN** セッションスナップショットにレビュー結果・テスト結果・fix 結果が含まれる
- **THEN** 4 カテゴリで分析し、各パターンに信頼度（0-100）を算出する

#### Scenario: スナップショット不在時のエラー処理
- **WHEN** セッションスナップショットが見つからない
- **THEN** 警告を出力し空結果で終了する（PR-cycle の成否に影響しない）

### Requirement: 重複排除

doobidoo 検索と GitHub Issues 検索の二段階で重複チェックしなければならない（MUST）。

#### Scenario: doobidoo でヒット時のスキップ
- **WHEN** 重複排除キーが doobidoo に既存
- **THEN** 該当パターンをスキップする

#### Scenario: GitHub Issues でヒット時のスキップ
- **WHEN** doobidoo にない が GitHub Issues に同一 dedup_key の Issue が存在
- **THEN** 該当パターンをスキップし doobidoo にキャッシュする

### Requirement: self-improve Issue 自動起票

信頼度 70 以上かつ重複なしのパターンについて Issue を起票しなければならない（SHALL）。

#### Scenario: 高信頼度パターンの Issue 起票
- **WHEN** パターンの confidence >= 70 かつ重複なし
- **THEN** `self-improve` ラベル付きで Issue を起票する

#### Scenario: 低信頼度パターンの doobidoo キャッシュ
- **WHEN** パターンの confidence < 70
- **THEN** Issue 起票せず doobidoo キャッシュのみ保存する

### Requirement: PR-cycle 非依存

本コマンドの失敗は PR-cycle の成否に影響してはならない（SHALL NOT）。

#### Scenario: API エラー時の継続
- **WHEN** doobidoo 接続失敗や GitHub API エラーが発生
- **THEN** 警告を出力し、可能な範囲で処理を継続する
