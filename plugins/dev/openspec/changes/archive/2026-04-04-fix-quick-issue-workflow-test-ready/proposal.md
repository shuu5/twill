## Why

autopilot で quick ラベル付き Issue を実行した際、workflow-setup が `is_quick=true` を正しく判定して軽量 chain を案内しても、Worker LLM がその後 `/dev:workflow-test-ready` を呼び出してフルチェーンが走る。原因は SKILL.md の指示順序の問題、orchestrator の nudge、launch プロンプトの 3 箇所に存在する。

## What Changes

- `skills/workflow-setup/SKILL.md`: quick かつ IS_AUTOPILOT=true の場合に workflow-test-ready を MUST NOT で禁止。quick 専用フロー指示を通常フロー指示より先に配置
- `scripts/autopilot-orchestrator.sh`: `_nudge_command_for_pattern()` に quick Issue 判定を追加し、"setup chain 完了" パターンに test-ready を送信しないよう分岐
- `scripts/autopilot-launch.sh`: quick ラベルを検出した場合に専用プロンプト（quick 分岐指示付き）を使用
- `skills/workflow-test-ready/SKILL.md`: quick 判定ガードを追加（defense-in-depth）

## Capabilities

### New Capabilities

- quick Issue フローの確実な分離: LLM 指示・orchestrator nudge・launch プロンプトの 3 層で test-ready 呼び出しをブロック

### Modified Capabilities

- workflow-setup: quick + autopilot 分岐が最優先・禁止句付きで明示
- autopilot-orchestrator: nudge が Issue の quick ラベルを考慮して送信内容を切り替え
- autopilot-launch: launch プロンプトが quick ラベル有無で分岐
- workflow-test-ready: 実行時に quick Issue かを確認し、quick なら即時終了

## Impact

- 影響ファイル: `skills/workflow-setup/SKILL.md`, `skills/workflow-test-ready/SKILL.md`, `scripts/autopilot-orchestrator.sh`, `scripts/autopilot-launch.sh`
- 既存の通常 Issue フローに変更なし
- Board 更新・Issue close 修正は含まない（別 Issue スコープ）
