## Context

#444（CLOSED）の AC として `ADR-016-test-target-real-issues.md` の作成が要求されていたが、実装されないままクローズされた。既存 ADR は ADR-001〜ADR-015（計16ファイル、ADR-014 は 2 ファイル存在）。本変更は 1 ファイルの追加のみであり、既存コードへの影響はない。

ADR の内容（専用テストリポ採用、co-self-improve 統合フロー、クリーンアップ設計）は #444 の議論を踏まえた設計決定を文書化する。

## Goals / Non-Goals

**Goals:**
- `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` を作成する
- 3 選択肢の比較と選定根拠を含める（専用テストリポ採用）
- co-self-improve との統合フロー（`--real-issues` モード）を記述する
- クリーンアップフロー（PR/Issue/branch の後処理）を記述する
- リポジトリ管理の責務帰属（`test-project-init --mode real-issues` 拡張）を決定する

**Non-Goals:**
- 実装コード（Issue C/D/E/F/G で対応）
- シナリオ追加（Issue G で対応）
- テストリポの実際の作成

## Decisions

1. **専用テストリポを採用**: observation.md の不変制約「実 main 汚染禁止」を満たす唯一の現実的選択肢。mock GitHub API より実装コストが低く、chain 遷移テストの信頼性が高い。

2. **既存 `test-project-init` への `--mode real-issues` フラグ追加**: 新規コマンド作成より責務の自然な拡張。deps.yaml 管理が単純になる。

3. **月次リポローテーション（`twill-test-<YYYYMM>`）**: テストリポの増殖防止。同月の既存リポを再利用することでリポ数を管理可能に保つ。

4. **冪等性設計のクリーンアップ**: PR close → Issue close → branch 削除の順序を守り、各ステップを独立して再実行可能とする。

## Risks / Trade-offs

- GitHub API のレートリミットが連続テスト実行に影響する可能性（緩和: テスト間隔の調整）
- クリーンアップ不完全時に孤立 branch/Issue が残る可能性（緩和: 冪等性設計）
- 月次ローテーションにより前月の Issue/PR 履歴が新リポに引き継がれない（許容: テスト記録はローカルに保持）
