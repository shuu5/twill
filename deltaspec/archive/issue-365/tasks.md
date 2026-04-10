## 1. su-observer SKILL.md Step 6 詳細化

- [ ] 1.1 `plugins/twl/skills/su-observer/SKILL.md` の Step 6 セクションを確認する
- [ ] 1.2 Step 6 の NOTE プレースホルダー（「後続 Issue で詳細実装される」）を削除する
- [ ] 1.3 su-compact コマンドへの委譲フローを Step 6 に追加する（`Skill(twl:su-compact)` 呼び出し）
- [ ] 1.4 呼出シグネチャ（`compact`・`compact --wave`・`compact --task`・`compact --full`）を記述する
- [ ] 1.5 SU-5 制約（context 50% 到達時の自動提案）を Step 6 内に記述する
- [ ] 1.6 SU-6 制約（Wave 完了時の su-compact 実行）を Step 6 内に記述する

## 2. 禁止事項セクション更新

- [ ] 2.1 `## 禁止事項（MUST NOT）` セクションを確認する
- [ ] 2.2 「context 50% 到達を無視してはならない（SU-5）」を追記する
- [ ] 2.3 「Wave 完了後の su-compact を省略してはならない（SU-6）」を追記する

## 3. 検証

- [ ] 3.1 `git diff` で変更ファイルが `plugins/twl/skills/su-observer/SKILL.md` のみであることを確認する
- [ ] 3.2 Step 6 に su-compact コマンドの呼出シグネチャが明記されていることを確認する
- [ ] 3.3 SU-5・SU-6 制約の記述が存在することを確認する
