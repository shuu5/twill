## Why

autopilot Worker は「1 Issue = 1 worktree = 1 リポ」の前提で動作するため、複数リポにまたがる Issue（例: #108 の 3 リポ配置）を単一 Worker が完全実装できない。Issue 粒度でリポ単位に分割するのが最も堅牢な解決策。

## What Changes

- co-issue Phase 2（分解判断）にクロスリポ検出ロジックを追加
- 検出時に AskUserQuestion でリポ単位分割を提案
- 承認時に parent Issue + 各リポの子 Issue を一括作成（Phase 4 拡張）
- 分割拒否時は従来通り単一 Issue として作成

## Capabilities

### New Capabilities

- **クロスリポ検出**: Issue スコープ内のファイルパスやキーワード（「3リポ」「全リポ」等）からリポ横断を検出
- **リポ単位分割提案**: 検出時にユーザーへ分割確認を提示
- **parent + 子 Issue パターン生成**: parent Issue（仕様定義）と各リポの子 Issue（実装）を構造化して生成
- **子 Issue の parent 参照**: 子 Issue body に parent Issue URL を自動挿入

### Modified Capabilities

- **Phase 2 分解判断**: 既存の単一/複数分解判断に加え、クロスリポ判断ロジックを追加
- **Phase 4 一括作成**: parent + 子 Issue の一括作成フローに対応（issue-bulk-create 拡張）

## Impact

- **skills/co-issue/SKILL.md**: Phase 2 にクロスリポ検出ステップ追加、Phase 4 に parent/子 Issue 作成フロー追加
- **commands/issue-structure.md**: クロスリポ Issue 用のテンプレート対応（parent Issue 形式）
- **commands/issue-bulk-create.md**: parent + 子 Issue の依存関係を持つ一括作成に対応
- **references/ref-issue-template-feature.md**: parent Issue テンプレートの追加検討
- **references/ref-project-model.md**: loom-dev-ecosystem 3 リポのデフォルト対象定義
