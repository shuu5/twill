## Why

loom-plugin-dev には各 change で生成された 40 本のシェルテスト（~17K 行）が存在するが、フレームワーク未統一（独自 assert 関数）で run-all.sh も特定 change 名がハードコードされている。bats ベースの統一テストスイートを構築し、全スクリプト・構造・不変条件を体系的に検証可能にする。

## What Changes

- bats-core + bats-assert + bats-support をテストフレームワークとして導入
- 25 本の scripts/ に対する単体テスト（sandbox 方式）を新規作成
- Autopilot 不変条件 9 件（A〜I）のテストカバレッジを確保
- merge-gate 判定ロジックのテスト
- chain 定義の整合性テスト（loom chain validate の補完）
- deps.yaml 構造テスト
- `run-tests.sh` を bats 対応に刷新
- 既存 40 本のテストシナリオは bats 形式に段階移行せず、別ディレクトリで共存

## Capabilities

### New Capabilities

- bats テストフレームワークによる統一テスト実行環境
- scripts/ 全 25 本に対する単体テストスイート
- Autopilot 不変条件 9 件（状態一意性、Worktree 削除 pilot 専任、Worker マージ禁止、依存先 fail skip 伝播、merge-gate リトライ制限、rebase 禁止、クラッシュ検知保証、deps.yaml 変更排他性、循環依存拒否）のテスト
- merge-gate 3 段階判定（init → execute → issues）のテスト
- chain 定義と deps.yaml の構造整合性テスト

### Modified Capabilities

- run-tests.sh: bats テスト実行 + 結果集約に刷新
- tests/ ディレクトリ構造: scenarios/（既存）+ bats/（新規）の 2 層構成

## Impact

- 新規ファイル: tests/bats/ 配下にテストファイル群、tests/helpers/ に共通ヘルパー
- 依存追加: bats-core, bats-assert, bats-support（git submodule）
- 既存 tests/scenarios/ は変更なし（共存）
- run-tests.sh を書き換え（bats + 既存 scenarios 両方を実行）
