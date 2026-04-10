## Context

`plugins/twl/skills/co-autopilot.md` の SKILL.md は Pilot（LLM）が参照する実行指示書である。現在 Step 1〜4 の記述が不正確で、以下の3パターンのエラーが毎セッション発生する：

1. `autopilot-plan.sh --issues "342, 323"` → カンマ区切りで parse error
2. `python3 -m twl.autopilot.session` → `PYTHONPATH` 未設定で `ModuleNotFoundError`
3. `orchestrator --session-file <session-id>` → 絶対パス未指定でエラー

## Goals / Non-Goals

**Goals:**
- SKILL.md に `autopilot-plan.sh` の正確な引数フォーマット（スペース区切り）を明記する
- SKILL.md に `source python-env.sh` の指示を追加する
- SKILL.md に `--session-file` の絶対パス例を追記する

**Non-Goals:**
- スクリプト本体（`autopilot-plan.sh`、`orchestrator`）の修正
- SKILL.md の全面リファクタリング

## Decisions

### 1. autopilot-plan.sh 引数フォーマット

Step 1（plan生成）の記述箇所に以下を追記：
```
# 正しい呼び出し形式（スペース区切り、カンマ不可）
bash autopilot-plan.sh --issues "342 323" --project-dir "$PROJECT_DIR"
```

### 2. python-env.sh の source

Step 3 冒頭に以下を追記：
```
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh"
```
これにより `PYTHONPATH=cli/twl/src:$PYTHONPATH` が設定され `twl.autopilot` モジュールが解決される。

### 3. orchestrator --session-file 絶対パス

orchestrator 呼び出し例を以下に修正：
```
--session-file "${AUTOPILOT_DIR}/session.json"
```
`$AUTOPILOT_DIR` は絶対パスが保証されているため、これで絶対パス要件を満たす。

## Risks / Trade-offs

- SKILL.md への追記のみのため、既存フローへの破壊的変更はない
- LLM が指示通りに読み取ることが前提であり、スクリプト自体の堅牢性は変わらない
