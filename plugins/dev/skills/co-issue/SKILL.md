---
name: dev:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase 構成: 問題探索 → 分解判断 → Per-Issue 精緻化 → 一括作成。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
spawnable_by:
- user
---

# co-issue

要望→Issue 変換ワークフロー（4 Phase 構成）。Non-implementation controller（chain-driven 不要）。

## explore-summary 検出（起動時チェック）

`.controller-issue/explore-summary.md` の存在を確認。存在時は「前回の探索結果が残っています。継続しますか？」と確認:
- [A] 継続する → Phase 1（探索）をスキップし Phase 2 から再開
- [B] 最初から → explore-summary.md を削除し Phase 1 から開始

存在しない場合は通常の Phase 1 から開始（既存動作に影響なし）。self-improve-review 出力も同一パスで検出される。

## Phase 1: 問題探索

TaskCreate 「Phase 1: 問題探索」(status: in_progress)

`/dev:explore` を Skill tool で呼び出し、「問題空間の理解に集中。Issue 化や実装方法は意識しない」と注入。

探索完了後、`.controller-issue/explore-summary.md` に書き出し: 問題の本質（1-3文）、影響範囲、関連コンテキスト、探索で得た洞察。Phase 1 完了前に Issue 構造化を開始してはならない。

TaskUpdate Phase 1 → completed

## Phase 2: 分解判断

TaskCreate 「Phase 2: 分解判断」(status: in_progress)

explore-summary.md を読み込み、単一/複数 Issue を判断。複数の場合は AskUserQuestion で分解内容を確認: [A] この分解で進める [B] 調整 [C] 単一のまま続行。

TaskUpdate Phase 2 → completed

## Phase 3: Per-Issue 精緻化ループ

TaskCreate 「Phase 3: 精緻化（N件）」(status: in_progress)

各 Issue 候補に対して順に:

1. **曖昧点検出**: `/dev:issue-dig` → PASS で次へ、WARN/FAIL は質問提示後続行（最大1回再実行）
2. **構造化**: `/dev:issue-structure` でテンプレート適用（bug/feature）
3. **推奨ラベル抽出**: issue-structure 出力の `## 推奨ラベル` セクションから `ctx/<name>` を抽出し recommended_labels に記録（セクションなし→空）
4. **品質評価**: `/dev:issue-assess` → completeness < 100% は補完再評価（最大1回）、duplicates は [A] 統合 [B] Related [C] 無関係、needs_split は候補追加
5. **tech-debt 棚卸し**（該当時のみ）: `/dev:issue-tech-debt-absorb` → Phase 4 で使用

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

1. **ユーザー確認（MUST）**: 全候補を提示、承認後に作成
2. **作成**: 単一→`/dev:issue-create`、複数→`/dev:issue-bulk-create`。tech-debt 吸収時は Related セクション付加。recommended_labels がある場合は `--label` 引数に追加
3. **Project Board 同期**: 各 Issue 後 `/dev:project-board-sync N`（失敗は警告のみ）
4. **クリーンアップ**: `.controller-issue/` を削除（中止時も同様）
5. **完了通知**: Issue URL 表示、`/dev:workflow-setup #N` で開発開始を案内

TaskUpdate Phase 4 → completed

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
