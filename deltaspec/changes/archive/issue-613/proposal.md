## Why

su-observer セッションは長時間常駐するが、ユーザーが observer ウィンドウに戻ろうとしたときに Claude Code session ID がわからず `cld --resume <session-id>` での復帰が困難。現状は `.jsonl` ファイル名から手動で推定するしかない。

## What Changes

- `su-observer SKILL.md` Step 0 で Claude Code session ID を取得し `.supervisor/session.json` の `claude_session_id` フィールドに保存するロジックを追加
- `cld` スクリプトに `--observer` フラグを追加し、保存された session ID で自動的に `claude --resume` を実行
- `su-postcompact.sh` に compaction 後の session ID 更新ロジックを追加（AC-0 検証結果に依存）
- `supervision.md` の `SupervisorSession` エンティティに `claude_session_id` フィールドを追加
- `plugins/twl/tests/scenarios/` に session resume のテストを追加

## Capabilities

### New Capabilities

- `cld --observer` コマンドで observer セッションに即座に resume できる
- su-observer セッションの Claude Code session ID が `.supervisor/session.json` に自動保存される
- session ID の有効性確認（tmux window 存在・プロセス生存チェック）

### Modified Capabilities

- `su-observer SKILL.md` Step 0 が session ID を取得・保存するようになる
- `cld` スクリプトが `--observer` フラグを認識し、引数ループで intercept する

## Impact

- `plugins/twl/skills/su-observer/SKILL.md`: Step 0 に `claude_session_id` 保存ロジック追加
- `plugins/session/scripts/cld`: `--observer` フラグ追加、引数パースロジック挿入
- `plugins/twl/scripts/su-postcompact.sh`: compaction 後の session ID 更新（AC-0 依存）
- `plugins/twl/architecture/domain/contexts/supervision.md`: `SupervisorSession` エンティティに `claude_session_id` 追加
- `plugins/twl/deps.yaml`: su-observer の dependencies に session plugin エンティティを追加
- `plugins/twl/tests/scenarios/su-observer-session-resume.test.sh`: 新規 bats テスト
