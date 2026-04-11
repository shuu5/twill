## 1. regex 検証

- [x] 1.1 `bug-deltaspec-archive` regex を `echo "test" | grep -E "$REGEX"` で検証する
- [x] 1.2 `bug-chain-stall` regex を `echo "test" | grep -E "$REGEX"` で検証する
- [x] 1.3 `bug-phase-review-skip` regex を `echo "test" | grep -E "$REGEX"` で検証する

## 2. observation-pattern-catalog.md 更新

- [x] 2.1 `## bug-reproduction patterns` セクションを `## 拡張ガイド` の直前に追加する
- [x] 2.2 `bug-deltaspec-archive` パターン（category: `deltaspec-archive-failure`, related_issue: "436"）を追加する
- [x] 2.3 `bug-chain-stall` パターン（category: `chain-transition-stall`, related_issue: "438"）を追加する
- [x] 2.4 `bug-phase-review-skip` パターン（category: `phase-review-skip`, related_issue: "439"）を追加する

## 3. bats テスト更新

- [x] 3.1 `observation-references.bats` に `bug-` プレフィックスカウント検証（3+）を追加する
- [x] 3.2 total パターン数の閾値を 12 以上に更新する
- [x] 3.3 `observation-references.bats` を実行して全テスト PASS を確認する
