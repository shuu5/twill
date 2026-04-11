## Why

su-observer（ADR-014 Decision 6）の導入により、controller とは異なる「Supervisor」型コンポーネントが誕生した。vision.md の Controller 操作カテゴリ表が実態と乖離しており、Meta-cognitive カテゴリが co-observer を controller として扱っているため、型の誤解を招く。

## What Changes

- `plugins/twl/architecture/vision.md`
  - Constraints セクション: `co-observer` を一覧から除き、controller 数を7→6に修正（または su-observer を Supervisor 型として別記）
  - Controller 操作カテゴリ表: `Meta-cognitive` 行を `Supervisor` に改名、`co-observer` を `su-observer` に更新
  - `Non-implementation controller は co-autopilot を spawn しない` の説明文で co-observer → su-observer を反映

## Capabilities

### New Capabilities

- **Supervisor カテゴリ**: controller の動作を監視・介入するメタレイヤーを独立カテゴリとして定義

### Modified Capabilities

- **Meta-cognitive → Supervisor**: カテゴリ名変更により su-observer の型的位置づけを明確化
- **controller 数の整合性**: co-observer が controller ではなく Supervisor 型であることを明示

## Impact

- `plugins/twl/architecture/vision.md` のみ変更（コード変更なし）
- CLAUDE.md（plugins/twl/CLAUDE.md）の「Controller は7つ」記述は別 Issue で更新予定
- ADR-014 と整合
