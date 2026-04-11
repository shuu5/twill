## Context

`test-project-reset.md` は現在 `--mode local` 相当の動作（worktree を initial タグに git reset）のみを持つ。real-issues モードでは GitHub 上のリソース（PR/Issue/branch）が専用リポに作成されるため、git reset では対応できない。クリーンアップには GitHub API（`gh` CLI）を使用して PR close → Issue close → remote branch 削除を行う必要がある。

クリーンアップ対象は `.test-target/loaded-issues.json`（Issue #480 が生成）に記録されたエントリで確定する。専用リポの特定は `.test-target/config.json`（Issue #479）の `repo` フィールドから行う。

## Goals / Non-Goals

**Goals:**
- `test-project-reset --real-issues` で loaded-issues.json の全 PR/Issue/branch を削除
- `--older-than <duration>` で `loaded_at` フィールドによる経過時間フィルタリング
- `--dry-run` でドライランモード（実操作なし、削除予定リスト出力のみ）
- `--mode local` と `--real-issues` の相互排他チェック
- 既存 `--mode local` 動作の維持（Step 4: ユーザー確認、Step 5: git reset）

**Non-Goals:**
- 専用リポ自体の削除
- local モードのリセットロジック変更

## Decisions

**D1: コマンド引数の拡張方針**
既存フローを `--mode local`（または引数なし）として維持し、`--real-issues` フラグを新規追加。両フラグが同時指定された場合はエラー終了する。

**D2: `--older-than` パース方式**
`date -d "-<value><unit>" +%s` コマンドで Epoch 変換を行う。単位: `d`（日）, `w`（週）, `m`（月）。パース失敗時はエラー出力して終了。

**D3: 削除順序**
PR close → Issue close → branch 削除の順で実行。PR が null の場合は PR close をスキップ。

**D4: loaded-issues.json のフィルタリング**
`--older-than` 指定時は `loaded_at` フィールドと比較して Epoch 以前のエントリのみを対象とする。

## Risks / Trade-offs

- `gh pr close` / `gh issue close` の失敗時は警告を出力して続行（既に close 済みの場合などに対応）
- `loaded-issues.json` が存在しない場合は `"loaded-issues.json が見つかりません"` エラーで終了
- `--older-than` の `m`（月）は GNU date 依存。非 GNU 環境では動作しない可能性あり（Linux 環境を前提）
