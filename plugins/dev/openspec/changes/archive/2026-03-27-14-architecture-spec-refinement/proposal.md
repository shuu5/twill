## Why

architecture/ ディレクトリの各ファイルは B-1 (#3) で設計判断が文書化されたが、ref-architecture-spec.md の仕様レベルとして自己完結するには精緻化が不足している。具体的には vision.md の設計哲学境界の詳細化、model.md の spawning 関係図示、glossary.md の旧→新用語対応、contexts/ の Key Entities 列挙と controller/workflow マッピング、phases/ の依存関係完全記載が未完了。

## What Changes

- **vision.md**: 「機械 vs LLM」境界の詳細記述、旧 plugin 複雑性回避策の明記、Non-Goals 展開
- **domain/model.md**: Controller spawning 関係図、状態ファイルスキーマ統合、Chain 実行フロー図の追加
- **domain/glossary.md**: 旧→新用語対応表の追加、廃止概念（--auto, 6種マーカー, direct パス等）の明記
- **domain/contexts/*.md**: Key Entities 具体列挙、controller/workflow/command マッピング追加
- **domain/contexts/loom-integration.md**: loom CLI コマンド対応表の拡充
- **phases/01.md, 02.md**: Issue 間依存関係の完全記載、Implementation Status 列の追加

## Capabilities

### New Capabilities

- 旧→新用語の完全な対応表（glossary.md）
- Controller spawning 関係の視覚化（model.md Mermaid 図）
- 各 Context の Key Entities 一覧と controller/workflow マッピング
- Phase 依存関係グラフと実装ステータス追跡

### Modified Capabilities

- vision.md: 概要レベル → 設計哲学の詳細境界定義
- model.md: 状態機械図 → 状態機械 + spawning + Chain フロー統合図
- contexts/*.md: 1段落説明 → 自己完結した仕様書レベルの記述
- phases/*.md: Issue リスト → 依存関係付き実装計画

## Impact

- **影響範囲**: `architecture/` ディレクトリ内のファイルのみ。コード変更なし
- **依存関係**: B-1 (#3) の成果物が入力。本変更は後続 Issue の設計参照として使用される
- **リスク**: 低。ドキュメント変更のみで、既存コードやランタイムへの影響なし
