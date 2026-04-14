## Context

worker-code-reviewer は bash スクリプトレビュー時に `baseline-coding-style.md` と `baseline-input-validation.md` を参照するが、bash 固有パターン（character class のハイフン配置、for-loop の local 宣言、set -u 環境での local 初期化）がカバーされていない。これらは autopilot Wave 実行中の phase-review で実際に検出された rule-gap であり、Issue #513, #528, #586 でそれぞれ記録・統合された。

また `baseline-coding-style.md` に IFS パース問題の記述が存在するが、bash 固有問題として `baseline-bash.md` に移設することで関心事の分離を図る。

## Goals / Non-Goals

**Goals:**

- `plugins/twl/refs/baseline-bash.md` を新規作成し 4 パターンを記述する（character class ハイフン・for-loop local・local set -u 初期化・IFS パース）
- `worker-code-reviewer.md` の Baseline 参照リストに `baseline-bash.md` を 3 番目として追加する
- `deps.yaml` に `baseline-bash` エントリを追加し、`phase-review` / `merge-gate` の calls から参照する
- `baseline-coding-style.md` の IFS セクション（L156-178）を `baseline-bash.md` への相互参照に置換して内容を重複排除する

**Non-Goals:**

- 3 パターン + IFS 移設以外の新規パターン追加
- worker-code-reviewer のレビューロジック変更（参照追加のみ）
- 他の baseline ファイルの変更

## Decisions

- **baseline-bash.md の frontmatter**: 既存の `baseline-coding-style.md` と同一形式（`name`, `description`, `type: reference`, `disable-model-invocation: true`）を採用。type: reference ファイルはモデルに直接呼び出されず参照データとして読み込まれる。
- **変更後の参照順序**: `baseline-coding-style.md` → `baseline-input-validation.md` → `baseline-bash.md`（追加は末尾、既存順序を維持）
- **deps.yaml 挿入位置**: `baseline-input-validation` エントリの直後に `baseline-bash` を追加（Issue #513 AC 指定通り）
- **IFS セクション置換**: `baseline-coding-style.md` に `→ baseline-bash.md を参照` のリンクノートを残し、実体は `baseline-bash.md` に移設する（削除ではなく相互参照に置換）

## Risks / Trade-offs

- `deps.yaml` の `phase-review` / `merge-gate` への追加順序誤りはレビュー漏れを引き起こすため、`baseline-input-validation` 直後であることを確認する
- `baseline-coding-style.md` の行番号（L156-178）は将来変更されうるが、この Issue では確認済みの現行位置で作業する
