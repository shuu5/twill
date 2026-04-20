## Why

co-autopilot の Wave 間遷移で session.json 残存・orchestrator ログ残留の 2 問題が毎 Wave 発生し、observer の手動介入なしでは次 Wave が自動開始できない（AC 2 の orchestrator パス修正は commit bf5add9 で既に hotfix 済み）。

## What Changes

- `autopilot-init.sh`: `is_session_completed()=true` の場合に `--force` なしで session.json + issues/issue-*.json を自動削除する分岐を追加（issues 空ガード込み）
- `autopilot-pilot-wakeup-loop.md`: `_ORCH_LOG` ファイル名に `session_id` を付与し Wave 間ログ分離を実現。`session.json` 不在時に警告出力
- `autopilot-orchestrator.sh`: 直接書き込み先のログ命名を wakeup-loop.md と同一規則（session_id 付き）に統一
- `orchestrator-nohup-trace.bats`: 新命名規則に合わせてテストの固定名をワイルドカードに更新
- `autopilot-pilot-wakeup-loop.md`: AC 2 hotfix (L26 絶対パス) の再修正防止コメント・blockquote を追加
- `architecture/domain/contexts/autopilot.md`: ログ path 記述を新命名規則に更新

## Capabilities

### New Capabilities

- Wave 遷移時に完了済み session.json が自動削除されることで、次 Wave の autopilot-init.sh が --force なしで起動可能
- ログファイルが Wave（session_id）ごとに分離され、Monitor が前 Wave の PHASE_COMPLETE を誤検知しない

### Modified Capabilities

- `is_session_completed()`: issues フィールドが空配列の場合は「未完了」と判定（race condition 防止）
- orchestrator ログ命名規則: `orchestrator-phase-${PHASE_NUM}.log` → `orchestrator-phase-${PHASE_NUM}-${SESSION_ID}.log`

## Impact

**変更ファイル:**
- `plugins/twl/scripts/autopilot-init.sh`（L82 周辺: 完了済み自動削除分岐 + is_session_completed 改修）
- `plugins/twl/commands/autopilot-pilot-wakeup-loop.md`（L22-24: SESSION_ID 付きログ名、L21 周辺: HOTFIX コメント）
- `plugins/twl/scripts/autopilot-orchestrator.sh`（L1311 周辺: ログ書き込み先を session_id 付きに変更）
- `plugins/twl/tests/unit/orchestrator-nohup-trace/orchestrator-nohup-trace.bats`（L140, L164-228: ログ名ワイルドカード化）
- `plugins/twl/architecture/domain/contexts/autopilot.md`（L348, L358: ログ path 記述更新）

**不変条件:**
- AC 2 (commit bf5add9): `autopilot-pilot-wakeup-loop.md` L26 の `${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-orchestrator.sh` 絶対パス指定は変更禁止
- AC 1/3/4 は AC 2 適用済みを前提とする。bf5add9 が revert された場合は AC 1/3/4 も同時に revert する
