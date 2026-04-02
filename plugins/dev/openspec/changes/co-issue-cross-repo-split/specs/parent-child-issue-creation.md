## ADDED Requirements

### Requirement: parent Issue の生成

クロスリポ分割承認時、Phase 4 は parent Issue を現在のリポに作成しなければならない（MUST）。parent Issue は仕様定義のみを含み、実装スコープを持たない。

#### Scenario: parent Issue を作成する
- **WHEN** クロスリポ分割が承認され Phase 4 に到達する
- **THEN** 現在のリポに parent Issue が作成され、タイトルに `[Feature]` プレフィックスが付き、body に「概要」「子 Issue」セクションが含まれる

#### Scenario: parent Issue に子 Issue チェックリストを追記する
- **WHEN** 全ての子 Issue 作成が完了する
- **THEN** parent Issue の body 内「子 Issue」セクションに `- [ ] owner/repo#N` 形式のチェックリストが追記される

### Requirement: 子 Issue のリポ別作成

各対象リポに対して子 Issue を `gh issue create -R owner/repo` で作成しなければならない（SHALL）。

#### Scenario: 3リポに子 Issue を作成する
- **WHEN** 対象リポが loom, loom-plugin-dev, loom-plugin-session の3つである
- **THEN** 各リポに1つずつ子 Issue が作成され、合計3つの子 Issue が存在する

#### Scenario: 子 Issue の body に parent 参照を含める
- **WHEN** 子 Issue が作成される
- **THEN** 子 Issue の body に `Parent: owner/repo#N` 形式で parent Issue への参照が含まれる

#### Scenario: 子 Issue のタイトルにリポ名を含める
- **WHEN** 子 Issue が作成される
- **THEN** 子 Issue のタイトルに対象リポ名が含まれ、parent Issue タイトルとの関連が明確である

## MODIFIED Requirements

### Requirement: Phase 4 一括作成フローの拡張

Phase 4 はクロスリポ分割時に parent + 子 Issue パターンをサポートしなければならない（MUST）。既存の単一 Issue / 同一リポ複数 Issue の作成フローは変更しない。

#### Scenario: クロスリポ分割時の作成順序
- **WHEN** クロスリポ分割が承認されている
- **THEN** parent Issue → 子 Issue（リポ順）→ parent Issue へのチェックリスト追記の順で実行される

#### Scenario: 子 Issue 作成失敗時のフォールバック
- **WHEN** 特定リポへの子 Issue 作成が失敗する（権限不足等）
- **THEN** エラーを警告として表示し、残りのリポへの子 Issue 作成を継続する。parent Issue のチェックリストには成功した子 Issue のみを記載する

#### Scenario: 分割なしの場合は従来動作
- **WHEN** クロスリポ分割が行われていない
- **THEN** 既存の Phase 4 フロー（issue-create / issue-bulk-create）がそのまま使用される
