## ADDED Requirements

### Requirement: Session ID 保存

su-observer セッション起動時に Claude Code session ID を `.supervisor/session.json` の `claude_session_id` フィールドに保存しなければならない（SHALL）。

#### Scenario: 新規 observer セッション起動時の session ID 保存
- **WHEN** `su-observer` SKILL.md Step 0 で SupervisorSession を新規作成するとき
- **THEN** Claude Code session ID が `.supervisor/session.json` の `claude_session_id` フィールドに書き込まれること

#### Scenario: observer セッション復帰時の session ID 更新
- **WHEN** `su-observer` SKILL.md Step 0 で status=active の既存セッションに復帰するとき
- **THEN** 既存の `claude_session_id` が検証され、変更がある場合は更新されること

### Requirement: SupervisorSession エンティティ拡張

`supervision.md` の `SupervisorSession` エンティティに `claude_session_id` フィールドを追加しなければならない（SHALL）。

#### Scenario: アーキテクチャドキュメントへのフィールド追加
- **WHEN** `plugins/twl/architecture/domain/contexts/supervision.md` を参照するとき
- **THEN** `SupervisorSession` エンティティのフィールド一覧に `claude_session_id: string | null` が含まれること

### Requirement: cld --observer フラグ

`cld` スクリプトは `--observer` フラグを認識し、`.supervisor/session.json` に保存された session ID で `claude --resume` を実行しなければならない（MUST）。

#### Scenario: 有効な observer session への resume
- **WHEN** `cld --observer` を実行し、有効な session ID と tmux window が存在するとき
- **THEN** `claude --resume <claude_session_id>` が実行されること

#### Scenario: session.json が存在しない場合のエラー
- **WHEN** `cld --observer` を実行し、`.supervisor/session.json` が存在しないとき
- **THEN** `"No active observer session. Start one with: cld → /su-observer"` メッセージが表示されること

#### Scenario: session ID が空の場合のエラー
- **WHEN** `cld --observer` を実行し、`claude_session_id` が null または空のとき
- **THEN** `"Observer session found but no Claude session ID recorded"` メッセージが表示されること

#### Scenario: tmux window が存在しない場合のエラー
- **WHEN** `cld --observer` を実行し、対応する tmux window が存在しないとき
- **THEN** `"Observer window not found. Session may have ended"` メッセージが表示されること

#### Scenario: Claude Code プロセスが終了している場合のエラー
- **WHEN** `cld --observer` を実行し、Claude Code プロセスが exited 状態のとき
- **THEN** `"Observer session has ended. Start a new one with: cld → /su-observer"` メッセージが表示されること

#### Scenario: 既存フラグの互換性維持
- **WHEN** `cld` を `--observer` フラグなしで実行するとき
- **THEN** 既存動作（全引数を `claude` にパススルー）に影響がないこと

### Requirement: Compaction 後の Session ID 更新

compaction 後も session ID が正しく維持されなければならない（SHALL）。ID が変わる場合は `su-postcompact.sh` で更新する。

#### Scenario: compaction 後の session ID 更新（ID 変更ケース）
- **WHEN** Claude Code の `/compact` 実行後に session ID が変わったとき
- **THEN** `su-postcompact.sh` が新しい session ID を取得し `.supervisor/session.json` を更新すること
