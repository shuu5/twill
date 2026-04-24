# Code Review: Phase Z Wave A-G1

実施日: 2026-04-24
対象: 62e67a3..b7ad439 (14 PR, cli/twl + plugins/twl)

## CRITICAL (ブロッカー)

なし。

## WARNING (要注意)

### W1: `DIRECT_SKIP_STEPS = frozenset()` — 空の frozenset (潜在的 dead code)

- **場所**: `cli/twl/src/twl/autopilot/chain.py:48`
- **詳細**: `DIRECT_SKIP_STEPS` が空の frozenset として定義されているが、これは `QUICK_SKIP_STEPS` を置き換えたもの。direct モード (scope/direct ラベル) でスキップするステップがない設計になっているが、その意図が明示されていない。
- **影響**: 機能的には harmless (direct モードで全ステップを実行する = quick モード廃止後の正しい動作)
- **推奨**: コメントで意図を明記 (例: `# direct mode: no steps skipped, all steps execute`)
- **Priority**: LOW

### W2: `tdd-red-guard.sh` — `set -uo pipefail` なし `set -e`

- **場所**: `plugins/twl/scripts/tdd-red-guard.sh:9`
- **詳細**: `set -uo pipefail` を使用しているが `set -e` がない。パイプライン内の非ゼロ終了は `pipefail` でキャッチされるが、一部のエラーパターンで予期しない継続動作が起きる可能性。
- **影響**: TDD RED guard の誤った PASS 判定リスク
- **推奨**: `set -euo pipefail` に変更
- **Priority**: MEDIUM → Phase AA follow-up 推奨

## INFO (情報)

### I1: 削除系変更が主体 (59419 削除 vs 12249 追加)
削除後の dead code は最小限。主要 autopilot フロー (chain-runner.sh, orchestrator.py) は正常動作を確認。

### I2: wave-collect.md の is_quick デッドコード (本 Issue で修正済み)
Observer (#919) が wave-collect.md から `is_quick`/`--quick` デッドコードを削除済み。

## 総評

Phase Z の削除系変更は概ね clean。CRITICAL 発見なし。W2 の `tdd-red-guard.sh` の `set -e` 欠落は Phase AA での修正推奨。
全体として Phase Z の目標 (DeltaSpec 除去 + quick 廃止) は達成されている。
