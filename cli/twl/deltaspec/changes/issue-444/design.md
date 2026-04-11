## Context

autopilot の full chain は GitHub Issue/PR を前提とした chain 遷移を持つ。現在の `--local-only` モードはローカルに Issue ファイルを配置するだけで、Orchestrator の polling → inject_next_workflow → merge-gate のフローを実行できない。

observation.md の不変制約: "test target は実 twill main の git 履歴を絶対に汚染しない"。この制約が分離戦略の選択を決定づける。

## Goals / Non-Goals

**Goals:**
- `--real-issues` モードの設計ドキュメント（ADR-016）を作成する
- 3 選択肢の比較表と選定根拠を明記する
- co-self-improve scenario-run モードとの統合フロー図を記載する
- クリーンアップ設計（Issue/PR/branch の後処理）を記載する
- リポジトリ作成・管理の責務帰属を決定する

**Non-Goals:**
- `--real-issues` モードの実装
- test-scenario-catalog.md のシナリオ追加
- observation-pattern-catalog.md のパターン追加

## Decisions

### Decision 1: リポジトリ分離戦略の選択

3 選択肢の比較:

| 戦略 | 隔離性 | GitHub API 依存 | クリーンアップ複雑度 | 備考 |
|------|--------|----------------|---------------------|------|
| 専用テストリポ | 高 | 中（リポ作成 API） | 低 | 実リポに影響なし、リポ管理コスト発生 |
| 実リポ test ラベル | 低 | 低 | 高 | git 履歴汚染リスク、不変制約に抵触 |
| mock GitHub API | 高 | なし | なし | 実装複雑度高、CI 向きだが現実性低 |

**決定**: 専用テストリポ。observation.md の不変制約（実 main 汚染禁止）を満たす唯一の現実的選択肢。mock は実装コストが高すぎる。

### Decision 2: リポジトリ作成・管理の責務帰属

- **既存コマンド拡張**: `test-project-init` に `--mode real-issues` フラグを追加
- 理由: 新規コマンドより既存コンポーネントの責務を明確に拡張する方が deps.yaml 管理が単純

### Decision 3: co-self-improve 統合フロー

SKILL.md Step 1 への分岐追加:
```
IF --real-issues:
  1. test-project-init --mode real-issues → 専用テストリポ作成（既存なら skip）
  2. GitHub Issue 起票（シナリオに対応する Issue を対象リポに作成）
  3. autopilot start --repo <test-repo> --issue <N>
  4. observe loop（polling）
  5. cleanup（Issue close / PR close / branch 削除）
```

### Decision 4: クリーンアップ設計

テスト完了後（成功・失敗問わず）:
1. 対象 PR をクローズ（マージ済み or 未マージ問わず）
2. 対象 GitHub Issue をクローズ（`test-result: pass/fail` ラベル付与）
3. feature branch 削除（対象テストリポの branch のみ）
4. test-project-init で作成した専用リポは保持（次回テストで再利用）

## Risks / Trade-offs

- 専用テストリポを使うと GitHub Actions の無料枠消費が増える可能性がある
- テストリポが増殖しないよう、テストリポのライフサイクル管理ルールを ADR に明記する必要がある
- クリーンアップが途中で失敗した場合の再実行可否設計が必要（冪等性の担保）
