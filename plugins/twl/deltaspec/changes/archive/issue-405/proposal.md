## Why

autopilot.md の不変条件として「autopilot 時のマージ実行責務」が明文化されていないため、設計意図が architecture 層で不明確になっている。また autopilot-orchestrator.sh の fallback パスのコメントが実態と乖離している。

## What Changes

- `architecture/autopilot.md`
  - Constraints セクションに不変条件 L を追加:「autopilot 時のマージ実行は Orchestrator の mergegate.py 経由のみ。Worker chain の auto-merge ステップは merge-ready 宣言のみを行い、マージは実行しない」
- `plugins/twl/scripts/autopilot-orchestrator.sh`
  - line 868 付近の fallback パスのコメントを実態に合わせて修正（「auto-merge.sh にフォールバック」→ 実際は `return 1` のみ）

## Capabilities

### New Capabilities

なし（ドキュメント・コメント修正のみ）

### Modified Capabilities

- **autopilot.md 不変条件**: マージ実行責務が L として明文化される（autopilot 時は Orchestrator の mergegate.py 経由のみ）
- **autopilot-orchestrator.sh**: fallback パスのコメントが実態に即した記述に修正される

## Impact

- 影響コード: `architecture/autopilot.md`, `plugins/twl/scripts/autopilot-orchestrator.sh`
- API/依存変更なし
- auto-merge.sh、mergegate.py、chain-runner.sh は変更なし
