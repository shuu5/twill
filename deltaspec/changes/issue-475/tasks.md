## 1. su-observer SKILL.md 拡張（監視チャンネルマトリクス）

- [ ] 1.1 `plugins/twl/skills/su-observer/SKILL.md` Step 1 に「supervise 1 iteration」セクションと5チャンネル監視マトリクスを追加する
- [ ] 1.2 `cld-observe-loop --pattern 'ap-*' --interval 180` による Worker 群 polling の起動手順を Step 1 に追加する
- [ ] 1.3 Monitor tool（Pilot tail streaming）と cld-observe-loop を**並行実行**する手順を SKILL.md に明示する
- [ ] 1.4 state stagnate 検知時の intervention-catalog pattern-7 照合手順を Step 1 に追加する

## 2. observe-once 拡張（state mtime チェック）

- [ ] 2.1 `plugins/twl/commands/observe-once.md` Step 3.5 として state file mtime チェックロジックを追加する（`find .autopilot/issues/ -name "issue-*.json" -mmin +N`）
- [ ] 2.2 `AUTOPILOT_STAGNATE_SEC` 環境変数（デフォルト 600）を参照するよう記述する
- [ ] 2.3 JSON 出力スキーマに `stagnate_files: string[]` フィールドを追加する

## 3. intervention-catalog 拡張（pattern-7）

- [ ] 3.1 `plugins/twl/refs/intervention-catalog.md` に Layer 0 Auto の pattern-7「Worker idle 検知（stagnate + 完了シグナル）」を追加する
- [ ] 3.2 検出条件: `updated_at` が 600s 以上古い AND worker pane に `>>> 実装完了:` を含む
- [ ] 3.3 介入手順: `/twl:workflow-pr-verify --spec issue-<N>` を対象 Worker window に inject
- [ ] 3.4 part 条件（stagnate のみ、完了シグナルなし）は pattern-4（Layer 1 Confirm）へフォールバックする旨を明記する

## 4. テストシナリオ追加

- [ ] 4.1 `tests/scenarios/su-observer-stagnate-detect.md` を作成し、cld-observe-loop 連携 dry-run シナリオを WHEN/THEN 形式で記述する
- [ ] 4.2 state file の mtime を手動操作して observe-once の `stagnate_files` 出力を検証するシナリオを追加する
