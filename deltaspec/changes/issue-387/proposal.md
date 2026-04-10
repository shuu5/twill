## Why

co-autopilot の Pilot が毎セッション同じ3パターンのエラーを繰り返してから正常動作に至る。SKILL.md のプロンプト指示が不正確なため、LLM が毎回同じ試行錯誤を強いられている。

## What Changes

- `plugins/twl/skills/co-autopilot.md`: Step 1〜4 に以下を追記
  - `autopilot-plan.sh` の引数フォーマット明示（スペース区切り、カンマ不可、`--project-dir` / `--repo-mode` 必須）
  - Step 3 冒頭に `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh"` の指示を追加
  - `orchestrator --session-file` に `$AUTOPILOT_DIR/session.json` 絶対パスを使う例を明示

## Capabilities

### Modified Capabilities

- Pilot が起動時にエラー0回で `plan.yaml` 生成 → session 初期化 → orchestrator 起動まで到達できる

## Impact

- `plugins/twl/skills/co-autopilot.md`（Step 1〜4 の指示修正）
