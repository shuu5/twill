## 1. AC-0: Session ID 取得方法の検証

- [ ] 1.1 `CLAUDE_SESSION_ID` 環境変数が su-observer 起動時に利用可能か実測で確認する
- [ ] 1.2 JSONL ファイル推定方式（`~/.claude/projects/<hash>/` 最新ファイル名）の実測確認
- [ ] 1.3 compaction 後に session ID が変わるかどうかを実測確認
- [ ] 1.4 検証結果を Issue コメントまたは PR description に記録する

## 2. アーキテクチャドキュメント更新

- [ ] 2.1 `plugins/twl/architecture/domain/contexts/supervision.md` の `SupervisorSession` エンティティに `claude_session_id: string | null` フィールドを追加する

## 3. su-observer SKILL.md の session ID 保存ロジック追加

- [ ] 3.1 AC-0 で確定した取得方法で session ID を取得するロジックを実装する
- [ ] 3.2 Step 0 新規セッション作成分岐（step 0-2）に `claude_session_id` を `session.json` へ書き込むロジックを追加する
- [ ] 3.3 Step 0 復帰分岐（status=active）に既存 `claude_session_id` の検証・更新ロジックを追加する

## 4. cld --observer フラグの実装

- [ ] 4.1 `plugins/session/scripts/cld` に引数ループで `--observer` を検出するロジックを追加する
- [ ] 4.2 `--observer` 検出時のプロジェクトルート検出ロジックを実装する（`git rev-parse` または bare repo 構造検出）
- [ ] 4.3 `.supervisor/session.json` の存在確認・`claude_session_id` 読み取りロジックを実装する
- [ ] 4.4 `session-state.sh list --json` + `session-state.sh state <window>` で有効性確認ロジックを実装する
- [ ] 4.5 4 エラーケース（session.json 不在・ID 空・window 不在・プロセス終了）のメッセージを実装する
- [ ] 4.6 有効時に `exec claude --resume <claude_session_id>` を実行するロジックを実装する

## 5. su-postcompact.sh の session ID 更新（AC-0 結果に依存）

- [ ] 5.1 AC-0 で compaction 後 ID が変わる場合のみ: session ID 更新ロジックを `su-postcompact.sh` に追加する（明確なセクション分離または別スクリプトに分離）

## 6. deps.yaml 更新

- [ ] 6.1 `plugins/twl/deps.yaml` の su-observer エントリに session plugin への依存を追加する
- [ ] 6.2 `plugins/session/deps.yaml` の cld エントリを `--observer` フラグ追加に合わせて更新する

## 7. テスト追加

- [ ] 7.1 `plugins/twl/tests/scenarios/su-observer-session-resume.test.sh` を bats 形式で新規作成する
- [ ] 7.2 session ID 保存テスト（AC-1）を実装する
- [ ] 7.3 `cld --observer` resume テスト（AC-2）を実装する
- [ ] 7.4 4 エラーケーステスト（AC-3〜AC-6）を実装する
- [ ] 7.5 引数互換性テスト（AC-8）を実装する

## 8. 最終確認

- [ ] 8.1 `twl --check` が PASS することを確認する
- [ ] 8.2 `cld` の既存フラグ（`--help` 等）および引数パススルー動作に影響がないことを確認する
