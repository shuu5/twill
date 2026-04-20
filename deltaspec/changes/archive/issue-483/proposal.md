## Why

Wave 1-5 で発見された autopilot バグ（#469/#470/#471/#472）の再現 E2E シナリオが test-scenario-catalog に存在せず、#442/#443 がクローズ済みでも catalog の bug 再現シナリオと observation-pattern-catalog の `bug-*` パターンが未追加のままである。real-issues モードで各バグを再現・検証できる状態を確立し、regression 防止基盤を整備する。

## What Changes

- `plugins/twl/refs/test-scenario-catalog.md`: スキーマに `bug_target` フィールドを追加、level enum に `bug` を追加、5 シナリオ（bug-469/470/471/472/combo）を追加
- `plugins/twl/refs/observation-pattern-catalog.md`: `bug-*` プレフィックスで各バグに対応する検出パターンを追加（`related_issue` 紐付き）
- `tests/bats/refs/observation-references.bats`: bug-* パターンの検証ケースを追加
- #442/#443 の GitHub Issue に「本 Issue で未達 AC を補完」の comment を追記

## Capabilities

### New Capabilities

- **bug 再現シナリオ**: `bug-469-chain-stall`、`bug-470-state-path`、`bug-471-refspec`、`bug-472-monitor-stall`、`bug-combo-469-472` の 5 シナリオが real-issues モードで実行可能になる
- **bug-* 検出パターン**: 各バグの chain 遷移・stall パターンを observation-pattern-catalog で検出できる
- **bats 検証**: observation-references.bats が bug-* パターンの存在を自動検証する

### Modified Capabilities

- **test-scenario-catalog スキーマ**: `bug_target` フィールドと `bug` level が追加され、より豊富なシナリオ分類が可能になる
- **observation-pattern-catalog**: `bug-*` プレフィックスパターンが `hist-*` と並列して管理される

## Impact

- `plugins/twl/refs/test-scenario-catalog.md`（スキーマ拡張 + 5 シナリオ追加）
- `plugins/twl/refs/observation-pattern-catalog.md`（bug-* パターン追加）
- `tests/bats/refs/observation-references.bats`（検証ケース追加）
- #442/#443 Issues（コメント追記）
