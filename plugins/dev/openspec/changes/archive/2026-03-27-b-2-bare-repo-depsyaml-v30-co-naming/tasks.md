## 1. プラグイン基盤ファイル

- [x] 1.1 `.claude-plugin/plugin.json` を作成（name: "dev", version, description）
- [x] 1.2 `.gitignore` を作成（.self-improve/, .code-review-graph/）

## 2. ディレクトリ構造

- [x] 2.1 `commands/`, `agents/`, `refs/` ディレクトリを作成（.gitkeep 配置）
- [x] 2.2 `scripts/hooks/` ディレクトリを作成
- [x] 2.3 `skills/co-autopilot/SKILL.md` を placeholder で作成
- [x] 2.4 `skills/co-issue/SKILL.md` を placeholder で作成
- [x] 2.5 `skills/co-project/SKILL.md` を placeholder で作成
- [x] 2.6 `skills/co-architect/SKILL.md` を placeholder で作成

## 3. deps.yaml v3.0

- [x] 3.1 `deps.yaml` を作成（version: "3.0", plugin: dev, entry_points x4, controller x4 定義）

## 4. hooks

- [x] 4.1 `scripts/hooks/post-tool-use-validate.sh` を作成（Edit/Write 後の loom validate 実行）
- [x] 4.2 `scripts/hooks/post-tool-use-bash-error.sh` を作成（Bash エラー → .self-improve/errors.jsonl 記録）
- [x] 4.3 `hooks.json` を作成（PostToolUse 定義）

## 5. CLAUDE.md 更新

- [x] 5.1 CLAUDE.md に bare repo 構造検証ルール（3条件）を追記
- [x] 5.2 CLAUDE.md にセッション起動ルール（main/ 必須）を追記

## 6. 検証

- [x] 6.1 `loom check` が pass することを確認
- [x] 6.2 `loom validate` が新規 violation 0 件であることを確認
