## Why

autopilot Wave 実行中の phase-review で検出された bash スクリプトの rule-gap（正規表現ハイフン配置・for-loop local 宣言・set -u 初期化）が worker-code-reviewer の baseline ルールに含まれておらず、同種の誤りが繰り返されるリスクがある。

## What Changes

- `plugins/twl/refs/baseline-bash.md` を新規作成（3 パターン + IFS パース問題を `baseline-coding-style.md` から移設して 4 セクション構成）
- `plugins/twl/agents/worker-code-reviewer.md` の「Baseline 参照（MUST）」セクションに `baseline-bash.md` への参照を 3 番目として追加
- `plugins/twl/deps.yaml` に `baseline-bash` エントリを追加（C-3 セクション、type: reference）
- `plugins/twl/deps.yaml` の `phase-review` および `merge-gate` の calls に `- reference: baseline-bash` を `baseline-input-validation` 直後に追加
- `plugins/twl/refs/baseline-coding-style.md` の Bash IFS セクション（L156-178）を `baseline-bash.md` への相互参照に置換

## Capabilities

### New Capabilities

- `baseline-bash.md` による 4 パターンの BAD/GOOD 対比ガイドライン（character class ハイフン配置・for-loop local 宣言・local set -u 初期化・IFS パース）
- worker-code-reviewer および phase-review が bash baseline を参照してレビューできる

### Modified Capabilities

- `worker-code-reviewer.md` の Baseline 参照リストが 2 エントリ → 3 エントリに拡張
- `baseline-coding-style.md` の IFS セクションが `baseline-bash.md` への相互参照に置換（実体の重複排除）

## Impact

- `plugins/twl/refs/baseline-bash.md`: 新規作成
- `plugins/twl/agents/worker-code-reviewer.md`: Baseline 参照リストに 1 行追加
- `plugins/twl/deps.yaml`: `baseline-bash` エントリ追加 + `phase-review` / `merge-gate` calls 更新
- `plugins/twl/refs/baseline-coding-style.md`: IFS セクション置換（L156-178）
