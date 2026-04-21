## Why

ADR-015（DeltaSpec 自動初期化）は Proposed 状態で停滞しているが、その Decision の核心部分はすでに `chain.py:step_init()` と `change-propose.md:Step 0` に実装済みである。設計判断を正式に Accept して設計正当性を確定させ、既実装コードのテストカバレッジを追加することで、ADR と実装の乖離を解消する。

## What Changes

- ADR-015 の Status を `Proposed` → `Accepted` に更新
- Accept 判断基準（互換性・実装コスト・運用影響・テスト容易性）を ADR に明文化
- `chain.py:step_init()` の `auto_init` パスに docstring/コメントを補強
- `change-propose.md:Step 0` の auto_init ロジックに根拠コメントを追記
- 既実装の `step_init()` auto_init 挙動を pytest でテスト追加
- 既実装の `change-propose.md:Step 0` フロー を bats でテスト追加

## Capabilities

### New Capabilities

- `step_init()` の auto_init 挙動が公式に保証された設計仕様として文書化される
- テストスイートが `auto_init=True` ケースをカバー（`deltaspec/` 不在時の `recommended_action=propose` 返却）

### Modified Capabilities

- ADR-015 が Accepted になり、後続 Issue（#786 等）が本 ADR の Accept を前提として着手可能になる
- `change-propose.md:Step 0` の分岐条件が ADR-015 に準拠したものとして正式化される

## Impact

- `plugins/twl/architecture/decisions/ADR-015-deltaspec-auto-init.md` — Status 更新 + Accept 判断基準追記
- `cli/twl/src/twl/autopilot/chain.py` — `step_init()` の auto_init ブロックに docstring 補強
- `plugins/twl/commands/change-propose.md` — Step 0 の auto_init 分岐に根拠コメント追記
- `cli/twl/tests/` — pytest: `step_init()` auto_init ケース追加
- `plugins/twl/tests/bats/` — bats: `change-propose` Step 0 auto_init ケース追加
