## 1. co-autopilot SKILL.md 修正

- [ ] 1.1 `plugins/twl/skills/co-autopilot.md` の Step 1 に `autopilot-plan.sh` 引数フォーマット例を追記（スペース区切り、カンマ不可、`--project-dir` 必須）
- [ ] 1.2 `plugins/twl/skills/co-autopilot.md` の Step 3 冒頭に `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh"` の指示を追加
- [ ] 1.3 `plugins/twl/skills/co-autopilot.md` の orchestrator 呼び出し例を `--session-file "${AUTOPILOT_DIR}/session.json"` に修正

## 2. 検証

- [ ] 2.1 `twl --check` を実行して PASS を確認
