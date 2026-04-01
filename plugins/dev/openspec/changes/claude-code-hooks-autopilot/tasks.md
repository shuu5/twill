## 1. PreToolUse AskUserQuestion 自動応答

- [x] 1.1 scripts/hooks/pre-tool-use-ask-user-question.sh を作成（stdin JSON 解析、questions からの自動応答生成、updatedInput 出力）
- [x] 1.2 hooks/hooks.json の PreToolUse セクションに AskUserQuestion matcher エントリを追加
- [x] 1.3 AskUserQuestion hook の動作確認（選択肢付き / open-ended の両パターン）

## 2. PostCompact チェックポイント

- [x] 2.1 scripts/hooks/post-compact-checkpoint.sh を作成（AUTOPILOT_DIR 判定、state-write.sh で last_compact_at 記録）
- [x] 2.2 hooks/hooks.json に PostCompact セクション + エントリを追加
- [x] 2.3 PostCompact hook の動作確認（autopilot 配下 / 通常セッションの両パターン）

## 3. PermissionRequest 自動承認

- [x] 3.1 scripts/hooks/permission-request-auto-approve.sh を作成（AUTOPILOT_DIR 判定、allow 応答出力）
- [x] 3.2 hooks/hooks.json に PermissionRequest セクション + エントリを追加
- [x] 3.3 PermissionRequest hook の動作確認（autopilot 配下 / 通常セッションの両パターン）

## 4. CLAUDE_AUTOCOMPACT_PCT_OVERRIDE 確認

- [x] 4.1 claude --help や最新リリースノートで CLAUDE_AUTOCOMPACT_PCT_OVERRIDE の存在を確認
- [x] 4.2 存在する場合: commands/autopilot-launch.md Step 5 の Worker 環境変数に追加（N/A: 存在しない）
- [x] 4.3 存在しない場合: Issue #81 にコメントしてスキップを記録

## 5. 検証・整合性

- [x] 5.1 loom check が PASS することを確認
- [x] 5.2 deps.yaml に新規 hook スクリプトの登録が必要か判定し、必要なら追加（不要: 既存 hook も未登録）
