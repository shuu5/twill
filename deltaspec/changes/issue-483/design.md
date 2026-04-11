## Context

Wave 1-5 で発見された 4 つの autopilot バグ（#469/#470/#471/#472）は個別に修正されたが、それぞれの再現シナリオが test-scenario-catalog に存在しない。また observation-pattern-catalog の `bug-*` セクションには Wave 1-3 由来の 3 パターンのみで、Wave 4-5 由来のパターンが欠落している。

現在 `test-scenario-catalog.md` のシナリオ YAML スキーマには `bug_target` フィールドが定義されておらず、`level` enum も `smoke | regression | load` の 3 値しかない。`observation.md` の `LoadScenario` エンティティが `bug_target` を参照しているにも関わらず catalog 側に定義がないため不整合がある。

## Goals / Non-Goals

**Goals:**
- test-scenario-catalog のスキーマに `bug_target` フィールドと `bug` level を追加
- 5 シナリオ（bug-469/470/471/472/combo）を catalog に追加
- 対応する `bug-*` パターン 5 件を observation-pattern-catalog に追加（`related_issue` 紐付き）
- `observation-references.bats` に検証ケースを追加
- #442/#443 に補完コメントを追記

**Non-Goals:**
- 各バグ（#469-#472）自体の修正
- su-observer 介入ロジックの改修（#475）
- real-issues モードでの実際の再現確認（CI は catalog 構造の静的検証のみ）

## Decisions

**bug level の追加**: `smoke | regression | load | bug` の 4 値に拡張する。`regression` は並列実行の conflict 検証、`bug` は特定の chain 遷移・stall パターン検証、と明確に責務を分ける。

**bug_target フィールド**: null 許容（汎用シナリオは null）。bug 再現シナリオは対象 Bug Issue 番号（整数または null）を格納する。

**combo シナリオの定義**: `bug-combo-469-472` は `issues_count: 3, expected_conflicts: 0, expected_duration_max: 60` で定義し、#469 と #472 の複合 stall パターンを再現する。`bug_target: null` で description に両 Issue を参照。

**bats テスト戦略**: 既存の `observation-references.bats` に新規テストケースを追加する（Case 5: bug-4xx パターン検証）。パターン数要件も `bug_count >= 3` を `bug_count >= 7` に引き上げる。

**パターン命名**: `bug-469-*`, `bug-470-*`, `bug-471-*`, `bug-472-*` の形式。既存の `bug-chain-stall` (#438) と区別するため Issue 番号を埋め込む。

## Risks / Trade-offs

- bats のテスト数を増やすことで CI 実行時間が増加するが、ref catalog の静的検証なので影響は軽微
- `level: bug` を追加した場合、既存の `level: load` テスト（`load_definitions -eq 0` 前提）との兼ね合いを確認する必要があるが、`bug` level は別カウントなので影響なし
- 既存 bats で `bug_count -ge 3` の閾値テストがあるため、新規追加後に閾値を引き上げる必要がある
