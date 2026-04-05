## ADDED Requirements

### Requirement: PostToolUse hook スクリプトの作成

`scripts/hooks/post-skill-chain-nudge.sh` を新規作成し、Skill tool 完了後に autopilot Worker の chain 継続を機械的に注入しなければならない（SHALL）。

スクリプトは以下の処理を順に実行しなければならない（SHALL）:
1. `AUTOPILOT_DIR` 環境変数が未設定の場合、何も出力せずに exit 0 で終了する
2. 現在ブランチから `git branch --show-current | grep -oP '^\w+/\K\d+(?=-)'` で Issue 番号を抽出する
3. Issue 番号が取得できない場合は exit 0 で終了する
4. `state-read.sh --type issue --issue <N> --field current_step` で現在ステップを取得する
5. `chain-runner.sh next-step <N> <current_step>` で次ステップを決定する
6. 次ステップが `"done"` または空の場合は何も出力せずに exit 0 で終了する
7. 次ステップが存在する場合は `[chain-continuation] 次は /twl:<next_step> を Skill tool で実行せよ。停止するな。` を stdout に出力する
8. `state-write.sh --type issue --issue <N> --field last_hook_nudge_at --value <ISO8601>` でタイムスタンプを記録する

エラーが発生した場合は stderr にログ出力し、必ず exit 0 で終了しなければならない（MUST）。

#### Scenario: autopilot Worker が Skill tool 完了後に次ステップを受け取る
- **WHEN** `AUTOPILOT_DIR` が設定された Worker セッションで Skill tool が完了する
- **THEN** hook が stdout に `[chain-continuation] 次は /twl:<next_step> を Skill tool で実行せよ。停止するな。` を出力し、LLM コンテキストに注入される

#### Scenario: 非 autopilot セッションでは hook が透過的に動作する
- **WHEN** `AUTOPILOT_DIR` が未設定の通常セッションで Skill tool が完了する
- **THEN** hook が何も出力せず exit 0 で終了し、通常利用への影響がない

#### Scenario: chain が完了した Worker では hook が何も出力しない
- **WHEN** `chain-runner.sh next-step` が `"done"` を返す
- **THEN** hook が何も出力せず exit 0 で終了する

#### Scenario: hook エラーが発生しても Worker が継続する
- **WHEN** `state-read.sh` や `chain-runner.sh` がエラーを返す
- **THEN** エラーが stderr に記録され、hook が exit 0 で終了し、Worker セッションが停止しない

### Requirement: settings.json への PostToolUse hook 登録

`~/.claude/settings.json` の `PostToolUse` 配列に `post-skill-chain-nudge` hook エントリを追加しなければならない（SHALL）。

エントリ形式:
```json
{
  "matcher": "Skill",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${AUTOPILOT_DIR:-.}/../../main/scripts/hooks/post-skill-chain-nudge.sh",
      "timeout": 5000
    }
  ]
}
```

#### Scenario: Skill tool 完了時に hook が発火する
- **WHEN** Skill tool が完了する（成功・失敗を問わず）
- **THEN** `post-skill-chain-nudge.sh` が実行される

### Requirement: last_hook_nudge_at タイムスタンプ記録

hook が chain 継続を注入するたびに `issue-{N}.json` の `last_hook_nudge_at` フィールドを ISO 8601 形式で更新しなければならない（SHALL）。

#### Scenario: hook 注入後にタイムスタンプが記録される
- **WHEN** hook が `[chain-continuation]` メッセージを stdout に出力する
- **THEN** `issue-{N}.json` の `last_hook_nudge_at` が現在時刻（ISO 8601）に更新される

## MODIFIED Requirements

### Requirement: orchestrator check_and_nudge の二重 nudge 防止

`scripts/autopilot-orchestrator.sh` の `check_and_nudge()` 関数は `last_hook_nudge_at` を参照し、直近 `NUDGE_TIMEOUT`（30s）以内に hook 注入があった場合は tmux nudge をスキップしなければならない（SHALL）。

#### Scenario: hook 注入直後に orchestrator が nudge をスキップする
- **WHEN** `issue-{N}.json` の `last_hook_nudge_at` が現在時刻から 30s 以内である
- **THEN** orchestrator が tmux nudge を送信せず、二重 nudge が発生しない

#### Scenario: hook 注入から 30s 以上経過した場合は orchestrator が nudge を送信する
- **WHEN** `issue-{N}.json` の `last_hook_nudge_at` が 30s 以上前、かつ stall 条件を満たす
- **THEN** orchestrator が通常通り tmux nudge を送信する

#### Scenario: last_hook_nudge_at フィールドが存在しない場合は従来動作
- **WHEN** `issue-{N}.json` に `last_hook_nudge_at` フィールドが存在しない（旧状態）
- **THEN** orchestrator が `last_hook_nudge_at` なしとして扱い、従来の stall 判定で nudge する
