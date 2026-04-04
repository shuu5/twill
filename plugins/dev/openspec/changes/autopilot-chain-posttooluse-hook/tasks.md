## 1. autopilot-launch.sh の AUTOPILOT_DIR export 確認

- [ ] 1.1 `scripts/autopilot-launch.sh` を読み込み、`AUTOPILOT_DIR` を Worker セッションに export しているか確認する
- [ ] 1.2 未設定の場合は `export AUTOPILOT_DIR=<path>` を追記する（`cld` コマンド実行前）

## 2. state-write.sh の last_hook_nudge_at フィールド対応確認

- [ ] 2.1 `scripts/state-write.sh` を読み込み、未知フィールドの取り扱いを確認する
- [ ] 2.2 `last_hook_nudge_at` フィールドが拒否される場合は許可リストに追加する

## 3. post-skill-chain-nudge.sh 作成

- [ ] 3.1 `scripts/hooks/` ディレクトリを作成する（未存在の場合）
- [ ] 3.2 `scripts/hooks/post-skill-chain-nudge.sh` を新規作成する（設計の D2-D6 に従う）
  - `AUTOPILOT_DIR` 未設定 → exit 0
  - ブランチから Issue 番号抽出
  - `state-read.sh` で `current_step` 取得
  - `chain-runner.sh next-step` で次ステップ決定
  - `"done"` / 空 → exit 0
  - それ以外 → stdout に `[chain-continuation]` メッセージ出力
  - `state-write.sh` で `last_hook_nudge_at` 記録
  - エラー時は stderr ログ + exit 0
- [ ] 3.3 スクリプトに実行権限を付与する（`chmod +x`）

## 4. settings.json への hook 登録

- [ ] 4.1 `~/.claude/settings.json` を読み込み、`PostToolUse` 配列の現在の内容を確認する
- [ ] 4.2 `matcher: "Skill"` で `post-skill-chain-nudge.sh` を呼び出す hook エントリを追加する（timeout: 5000）
- [ ] 4.3 hook のスクリプトパスが worktree/main どちらからでも解決できることを確認する

## 5. orchestrator check_and_nudge 修正

- [ ] 5.1 `scripts/autopilot-orchestrator.sh` の `check_and_nudge()` 関数を読み込む
- [ ] 5.2 `last_hook_nudge_at` を `state-read.sh` で取得するロジックを追加する
- [ ] 5.3 現在時刻との差分が `NUDGE_TIMEOUT`（30s）以内なら tmux nudge をスキップする条件分岐を追加する
- [ ] 5.4 `last_hook_nudge_at` が存在しない場合は従来動作（nudge 実行）にフォールバックする

## 6. deps.yaml 更新

- [ ] 6.1 `deps.yaml` に `post-skill-chain-nudge` script コンポーネントエントリを追加する
- [ ] 6.2 `loom check` を実行して整合性を確認する
- [ ] 6.3 `loom update-readme` を実行する

## 7. 動作確認

- [ ] 7.1 `AUTOPILOT_DIR` 未設定の状態でスクリプトを実行し、何も出力されないことを確認する
- [ ] 7.2 dummy の `issue-{N}.json` と `chain-steps.sh` を用意し、hook が正しいメッセージを stdout に出力することを確認する
- [ ] 7.3 `last_hook_nudge_at` が `issue-{N}.json` に記録されることを確認する
- [ ] 7.4 エラーケース（state-read.sh 失敗）で exit 0 になることを確認する
