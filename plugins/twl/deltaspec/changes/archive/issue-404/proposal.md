## Why

不変条件 C（Worker マージ禁止）は autopilot.md に定義されているが、Worker が実際に参照する workflow-pr-merge/SKILL.md と Worker 起動コンテキストに明示的禁止が記載されていない。その結果 Worker が `gh pr merge --squash` を直接実行し、ac-verify / merge-gate / auto-merge.sh の全ガードをバイパスするケースが複数発生した。

## What Changes

- `plugins/twl/skills/workflow-pr-merge/SKILL.md`: 禁止事項セクションに「Worker は `gh pr merge` を直接実行してはならない（不変条件 C）」を追記
- `plugins/twl/scripts/autopilot-launch.sh`: Worker 起動コンテキスト注入に `gh pr merge` 直接実行禁止を固定テキストとして追加
- `plugins/twl/skills/co-autopilot/SKILL.md`: 不変条件 C の enforcement 箇所への参照リンクを追記

## Capabilities

### New Capabilities

なし（enforcement 強化のみ）

### Modified Capabilities

- workflow-pr-merge/SKILL.md: 不変条件 C の明示的禁止を追加（Worker が参照するドキュメントにガードを追加）
- autopilot-launch.sh: Worker 起動時の system prompt に merge 禁止コンテキストを注入
- co-autopilot/SKILL.md: 不変条件 C の enforcement 箇所参照リンクを追加

## Impact

- 変更ファイル: 3 ファイル（SKILL.md × 2 + autopilot-launch.sh）
- auto-merge.sh の 4-layer ガードは変更なし（既存ガードを補完する形）
- 動作変更なし（禁止ルールの明文化のみ）
