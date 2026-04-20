## Context

`/twl:test-project-init` は orphan branch `test-target/main` に `test-fixtures/minimal-plugin/` を展開し、ローカルで co-self-improve の再現環境を構築するコマンド。現状は GitHub 連携を一切行わないため、co-autopilot が前提とする「GitHub Issue + PR の実体」が存在せず、chain 遷移の E2E 再現が不可能。

ADR-016 (#477) により、専用 GitHub リポ（test-target リポ）を用いた `real-issues` モードが設計決定された。本 Issue はその第 1 フェーズとして、test-project-init コマンドへのモード分岐追加と設定永続化を実装する。

## Goals / Non-Goals

**Goals:**
- `--mode real-issues --repo <owner>/<name>` CLI 引数の追加と処理
- リポ存在確認・空リポ検証（コミット数 == 0 かつブランチ数 <= 1）・push パーミッション確認
- 存在しないリポの gh CLI 自動作成（private / empty / 指定 owner）
- `.test-target/config.json` への設定永続化
- `--mode local` / 未指定時の既存動作維持（デフォルト = local）
- `observation.md` の `TestProject` エンティティ拡張（mode / repo / loaded_issues_file フィールド追加）
- `test-project-init.md` 禁止事項の条件付き化
- 既存 bats テストへの `--mode local` 明示

**Non-Goals:**
- 実 Issue 起票（#480 スコープ）
- co-self-improve 側の real-issues 分岐（#481 スコープ）
- ADR-016 のリポ命名規則策定（#477 完了前提）

## Decisions

### D1: `.test-target/config.json` スキーマ

```json
{
  "mode": "local | real-issues",
  "repo": "<owner>/<name> | null",
  "initialized_at": "<ISO 8601>",
  "worktree_path": "<絶対パス>",
  "branch": "test-target/main"
}
```

`repo` は `mode == 'real-issues'` 時のみ必須。`loaded_issues_file` は #480 で追記されるため、初期スキーマには含めない（`TestProject` エンティティには定義するが、config.json への書き込みは #480 が担当）。

**理由**: 2 段階の責務分離（config.json の初期化 = #479、Issue データの注入 = #480）。

### D2: 「空リポ」の定義

コミット数 == 0 かつブランチ数 <= 1 を空リポとみなす。gh CLI で `git ls-remote` を実行し HEAD が存在しない場合も空と判定。

### D3: モード引数のデフォルト

`--mode` 未指定 = `local`。既存の動作と完全互換。

### D4: 禁止事項の条件付き化

`test-project-init.md` の「git push してはならない」を「`--mode local` では git push してはならない」に変更。`--mode real-issues` では gh CLI 経由のリモート操作を許可する。

## Risks / Trade-offs

- **リポ作成競合**: 同名リポが他ユーザーに存在する場合は明確なエラーメッセージを返す
- **ADR-016 依存**: リポ命名規則が #477 完了前に変わる可能性があるが、`--repo <owner>/<name>` を引数で受け取る設計のため柔軟性を担保
- **既存テストへの影響**: bats テストに `--mode local` を追加するだけで既存動作は維持される
