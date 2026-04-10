## 1. workflow-pr-merge/SKILL.md 禁止事項セクション更新

- [x] 1.1 plugins/twl/skills/workflow-pr-merge/SKILL.md の禁止事項セクション先頭に「Worker は `gh pr merge` を直接実行してはならない。マージは必ず `chain-runner.sh auto-merge` 経由で auto-merge.sh のガードを通すこと（不変条件 C）」を追記

## 2. autopilot-launch.sh Worker 起動コンテキスト注入

- [x] 2.1 plugins/twl/scripts/autopilot-launch.sh の quick ラベル注入ブロック（line 232-242）の直後に、merge 禁止テキストを CONTEXT に常時追記するブロックを追加（quick ラベルの有無に関わらず全 Worker 起動時に注入）

## 3. co-autopilot/SKILL.md 不変条件 C 参照更新

- [x] 3.1 plugins/twl/skills/co-autopilot/SKILL.md の不変条件一覧（C=Worker マージ禁止 の記述）に「enforcement: workflow-pr-merge/SKILL.md 禁止事項セクション + autopilot-launch.sh 起動コンテキスト参照」を追記

## 4. 検証

- [x] 4.1 auto-merge.sh の内容が変更されていないことを確認（既存の 4-layer ガードが維持されていること）
- [x] 4.2 workflow-pr-merge/SKILL.md に不変条件 C, E, F が全て記載されていることを確認
- [x] 4.3 autopilot-launch.sh の CONTEXT 変数に merge 禁止テキストが含まれることをコード上で確認
