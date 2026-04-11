## Why

Issue 数が多い場合（5+）、LLM がコンテキスト圧迫で迷走し spec-review の forward progression gate deny を繰り返す非効率が残る。`autopilot-orchestrator.sh` で確立済みの「Bash ループで N 回の tmux cld セッション spawn → ポーリング → 結果収集」パターンを spec-review に適用し、LLM のループ判断を完全に排除する。

## What Changes

- 新規 `plugins/twl/scripts/spec-review-orchestrator.sh`: Issue リストディレクトリ → N 個の tmux cld セッション spawn → 完了ポーリング → 結果収集
- `plugins/twl/skills/workflow-issue-refine/SKILL.md`: Step 3b をオーケストレーター呼び出しに変更（既存の LLM ループから Bash ループへ）
- `plugins/twl/deps.yaml` 更新: spec-review-orchestrator を script エントリとして追加、workflow-issue-refine の calls に追加

## Capabilities

### New Capabilities

- `spec-review-orchestrator.sh --issues-dir DIR --output-dir DIR`: Issue ごとの JSON ファイルを読み込み、各 Issue に対し tmux 新ウィンドウを起動して `/twl:issue-spec-review` を独立実行する
- `MAX_PARALLEL` 環境変数によるバッチ制御（デフォルト: 3）
- 全セッション完了検知とポーリングループ

### Modified Capabilities

- `workflow-issue-refine` Step 3b: N Issue の spec-review を、LLM ループではなく `spec-review-orchestrator.sh` 呼び出しに委譲する

## Impact

- **追加ファイル**: `plugins/twl/scripts/spec-review-orchestrator.sh`
- **変更ファイル**: `plugins/twl/skills/workflow-issue-refine/SKILL.md`, `plugins/twl/deps.yaml`
- **依存**: #446（PreToolUse gate は fallback として引き続き機能）、`autopilot-orchestrator.sh`（借用パターン）
- **非対象**: autopilot-orchestrator.sh 本体, PreToolUse gate 導入（#446 対応済み）
