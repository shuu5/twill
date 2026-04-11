## 1. SKILL.md Step 1 拡張

- [x] 1.1 `plugins/twl/skills/co-self-improve/SKILL.md` Step 1 冒頭にフラグ解析ステップを追加（`--real-issues` / `--repo` / `--local` の解析）
- [x] 1.2 `--real-issues` + `--repo` あり時のフロー分岐を記述（test-project-init に `--mode real-issues --repo` を委譲）
- [x] 1.3 `--real-issues` + `--repo` なし時の AskUserQuestion ステップを追加
- [x] 1.4 フラグなし / ambiguous 時の AskUserQuestion ステップを追加（local vs real-issues 選択）
- [x] 1.5 local モード時は従来の init 呼び出し（フラグなし）を継続することを明記
- [x] 1.6 Step 4 の scenario-load 呼び出しに `--real-issues` フラグ委譲を追記
- [x] 1.7 Step 5 の session:spawn に `-- /twl:co-autopilot` 起動の明文化を追記

## 2. 動作検証

- [x] 2.1 `--real-issues --repo` フラグなしでの実行が従来通り local モードで動作することを確認
- [x] 2.2 `--real-issues --repo <owner>/<name>` フラグありでの呼び出しが init / scenario-load に正しく委譲されることを確認（SKILL.md レビューレベル）
