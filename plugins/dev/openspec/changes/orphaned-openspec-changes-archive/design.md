## Context

`openspec/changes/` に 89 件の change が蓄積しており、その大半は実装完了済みと推定される。deltaspec archive の autopilot 統合（#235）が未実装のため、自動クリーンアップが行われていなかった。shuu5/deltaspec#1 の構文エラーにより `deltaspec list` が信頼できないため、手動トリアージ方式を採用する。

## Goals / Non-Goals

**Goals:**

- `openspec/changes/` 内の全 change を調査してトリアージリスト（アーカイブ対象 / 保留 / 要調査）を作成する
- ユーザー承認後、対象 change を `openspec/changes/archive/YYYY-MM-DD-<name>/` へ移動する
- 既存 `archive/` 内 17 件の命名を `YYYY-MM-DD-<name>` 形式に統一する

**Non-Goals:**

- archive 自動化の実装（#235 で対応）
- deltaspec の構文エラー修正（shuu5/deltaspec#1 で対応）
- openspec/changes/ 以外のファイル変更

## Decisions

**D1: 完了判定は tasks.md ベース**
各 change の `tasks.md` が存在し全タスクが完了済み（`- [x]`）の場合をアーカイブ対象とする。tasks.md が存在しない、または未完了タスクがある場合は「要調査」とする。

**D2: ブランチ存在チェックで補完**
`git branch -a | grep <change-name>` でブランチが残っている場合は「保留」候補とする。作業が進行中の可能性があるため。

**D3: アーカイブ日付は .openspec.yaml の created フィールド優先**
`.openspec.yaml` の `created` フィールドがある場合はその日付（YYYY-MM-DD）を使用。なければ `git log --follow --diff-filter=A -- openspec/changes/<name>` で初回コミット日を取得。

**D4: deltaspec コマンドが使えない場合は手動 mv**
shuu5/deltaspec#1 未修正の場合、`deltaspec archive` の代わりに `mv openspec/changes/<name> openspec/changes/archive/<date>-<name>` で移動する。

**D5: 既存 archive の日付は git log で補完**
既存 17 件のうち `.openspec.yaml` に `created` がないものは `git log` で初回コミット日を取得。それも取れない場合は `1970-01-01` プレフィックスで識別可能にする。

## Risks / Trade-offs

- **誤アーカイブリスク**: tasks.md が存在しない change を「要調査」に分類することで誤アーカイブを防ぐ。ユーザー承認が最終防衛線。
- **deltaspec 依存**: `deltaspec archive` コマンドのバグにより手動 mv フォールバックが必要。日付プレフィックスの正確性が低下する可能性があるが許容範囲。
- **既存 archive 命名変更**: git history で追跡しにくくなるが、openspec ファイルは仕様文書であり git blame よりも内容の可読性を優先する。
