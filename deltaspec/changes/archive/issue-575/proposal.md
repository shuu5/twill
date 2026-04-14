## Why

`issue-lifecycle-orchestrator.sh` が spawn する Worker セッション（co-issue 用 specialist レビュー）は sonnet で十分な処理であるにもかかわらず、モデル指定機能がないため高コストな opus で起動されてしまっている。`autopilot-orchestrator.sh` には既に `--model` フラグが存在するが、`issue-lifecycle-orchestrator.sh` には同等の機構がない。

## What Changes

- `issue-lifecycle-orchestrator.sh` に `--model <model>` フラグを追加（デフォルト: `sonnet`）
- `issue-lifecycle-orchestrator.sh` の `spawn_session` から `cld-spawn` に `--model` を伝搬
- `cld-spawn` に `--model` オプションを追加し、ランチャースクリプト内の cld 起動コマンドに反映
- `co-issue SKILL.md` の Phase 3（初回）・Phase 4（retry）の orchestrator 呼び出しに `--model sonnet` を付与

## Capabilities

### New Capabilities

- `issue-lifecycle-orchestrator.sh` がモデルを外部から指定可能になる
- `cld-spawn` が `--model` オプションを受け取り、起動する cld プロセスに転送できる

### Modified Capabilities

- `co-issue SKILL.md` の orchestrator 起動が `--model sonnet` 付きになる（デフォルト動作の変更）

## Impact

- `plugins/twl/scripts/issue-lifecycle-orchestrator.sh`: `--model` フラグ追加、`spawn_session` 変更
- `plugins/session/scripts/cld-spawn`: `--model` オプション追加、ランチャースクリプト生成部変更
- `plugins/twl/skills/co-issue/SKILL.md`: Phase 3・Phase 4 の orchestrator 呼び出し変更
