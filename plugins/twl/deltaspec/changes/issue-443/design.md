## Context

`plugins/twl/refs/observation-pattern-catalog.md` は `workflow-observe-loop` の `problem-detect` atomic が参照する rule-based パターン定義ファイル。現在は汎用エラー（error-\*）、警告（warn-\*）、情報（info-\*）、過去インシデント（hist-\*）の 4 セクションを持つ。

Bug #436（deltaspec archive 失敗）、#438（chain 遷移停止）、#439（phase-review スキップ）は再発性バグであり、rule-based 検出パターンがあれば早期に自動検知できる。既存 YAML フォーマットに従い `bug-` プレフィックスで新セクションを追加する。

`tests/bats/refs/observation-references.bats` の Case 3 は prefix 別のパターン数をカウントしており、`bug-` プレフィックスの追加に対応するテストを追加する必要がある。

## Goals / Non-Goals

**Goals:**
- `bug-deltaspec-archive`、`bug-chain-stall`、`bug-phase-review-skip` の 3 パターンを追加
- 各パターンの regex を `grep -E` で検証済み
- `tests/bats/refs/observation-references.bats` のテストを `bug-` プレフィックス対応に更新

**Non-Goals:**
- `commands/problem-detect.md` のスタブパターンリスト更新（カタログ参照で自動反映されるため不要）
- `observer-evaluator` の LLM 判定パターン追加
- `test-scenario-catalog.md` へのシナリオ追加（別 Issue）

## Decisions

### 1. 新セクション `## bug-reproduction patterns`

既存セクション末尾（`## 拡張ガイド` の直前）に新セクションを挿入。`## historical patterns` との区別として、過去インシデントではなく再現可能な既知バグを対象とする。

### 2. パターン設計（各 Bug の failure message に基づく）

**`bug-deltaspec-archive`（#436）:**
- 対象: deltaspec archive コマンド実行失敗時のエラーメッセージ
- regex: `'archive.*fail|fail.*archive|Error.*archive|deltaspec.*archive.*error'`
- severity: error
- category: `deltaspec-archive-failure`

**`bug-chain-stall`（#438）:**
- 対象: chain 遷移停止 / polling timeout メッセージ
- regex: `'chain.*stall|polling.*timeout|transition.*stop|chain.*stop'`
- severity: error
- category: `chain-transition-stall`

**`bug-phase-review-skip`（#439）:**
- 対象: phase-review スキップ / phase-review.json 不在のメッセージ
- regex: `'phase.review.*skip|phase.review\.json.*not found|skip.*phase.review'`
- severity: warning
- category: `phase-review-skip`

### 3. bats テスト更新

`observation-references.bats` の Case 3 テスト `has at least 9 patterns across all categories` に `bug-` prefix カウント（1+）を追加し、total 閾値を 12 以上に更新する。

## Risks / Trade-offs

- **regex の精度**: Bug の実際のエラーメッセージに依存するため、false positive/negative が発生する可能性がある。初期は broad な regex で検出し、false positive が多い場合は refinement する
- **bats テストの脆弱性**: total 閾値を固定値にするため、将来のパターン削除時にテストが壊れる可能性がある。閾値を追加後の実数に設定することで対応
