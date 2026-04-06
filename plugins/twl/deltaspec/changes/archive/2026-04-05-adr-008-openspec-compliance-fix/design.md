## Context

ADR-008 は「Worktree ライフサイクルを Pilot に完全集約する」決定を定義し、PR #234 で実装済み。しかし openspec 内の複数ファイルが旧スタイル（Worker が worktree を作成し main/ で起動）の記述のままとなっている。これはドキュメントとしての正確性の問題であり、実装への影響はない。

## Goals / Non-Goals

**Goals:**
- openspec 内の Worker 起動・worktree 作成に関する記述を ADR-008 準拠に修正
- 修正後に `rg "Worker.*worktree を作成" openspec/` および `rg "main worktree で.*起動" openspec/` が 0 件になること

**Non-Goals:**
- 実装コード（scripts/、skills/）への変更
- ADR-008 自体の変更
- cross-repo-autopilot の全面的な見直し（テキスト修正のみ）

## Decisions

### 置換ルールの適用

以下のルールで機械的にテキストを置換する:

| 旧記述 | 新記述 |
|--------|--------|
| Worker が worktree を作成する | Pilot が worktree を事前作成する |
| main worktree で起動 | Pilot が作成した worktree ディレクトリで起動 |
| Worker は main/ worktree で起動される | Worker は Pilot が作成した worktree ディレクトリで起動される |

### Pilot の main/ 記述は維持

Pilot が main/ で動作するという記述は ADR-008 準拠であり変更不要。

### test-mapping.yaml の verified_by 整合維持

`b-3-autopilot-state-management/test-mapping.yaml` L523 の requirement 修正後、verified_by との整合が崩れないように確認する。

## Risks / Trade-offs

- **コンテキスト依存**: `main worktree で起動` の一部はデザイン判断の文脈で正当な記述である場合があるため、機械的置換後に文脈確認が必要
- **cross-repo-autopilot の特殊性**: cross-repo の場合、各リポジトリの worktree ディレクトリで起動するという記述は技術的に正確。修正後も意味が通るよう注意する
