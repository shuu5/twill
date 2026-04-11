## 1. test-scenario-catalog スキーマ拡張

- [x] 1.1 `plugins/twl/refs/test-scenario-catalog.md` の scenario YAML フォーマットに `bug_target:` フィールドを追加
- [x] 1.2 level enum を `smoke | regression | load | bug` に更新
- [x] 1.3 `## bug level シナリオ` セクションを新規追加

## 2. bug 再現シナリオ追加（test-scenario-catalog）

- [x] 2.1 `bug-469-chain-stall` シナリオを追加（level: bug, bug_target: 469）
- [x] 2.2 `bug-470-state-path` シナリオを追加（level: bug, bug_target: 470）
- [x] 2.3 `bug-471-refspec` シナリオを追加（level: bug, bug_target: 471）
- [x] 2.4 `bug-472-monitor-stall` シナリオを追加（level: bug, bug_target: 472）
- [x] 2.5 `bug-combo-469-472` シナリオを追加（level: bug, bug_target: null, issues_count: 3, expected_conflicts: 0, expected_duration_max: 60）

## 3. observation-pattern-catalog bug-* パターン追加

- [x] 3.1 `bug-469-chain-end` パターンを追加（related_issue: "469"）
- [x] 3.2 `bug-470-state-path` パターンを追加（related_issue: "470"）
- [x] 3.3 `bug-471-refspec` パターンを追加（related_issue: "471"）
- [x] 3.4 `bug-472-monitor-stall` パターンを追加（related_issue: "472"）

## 4. bats 検証ケース追加

- [x] 4.1 `plugins/twl/tests/bats/refs/observation-references.bats` に bug-469/470/471/472 パターンの検証ケースを追加
- [x] 4.2 既存 `bug_count -ge 3` 閾値を `bug_count -ge 7` に引き上げ
- [x] 4.3 `test-scenario-catalog: bug-469-chain-stall defined` テストケースを追加
- [x] 4.4 bats テストを実行して全ケースがパスすること確認

## 5. GitHub Issue コメント追記

- [x] 5.1 Issue #442 に「本 Issue (#483) で未達 AC を補完した」コメントを追記
- [x] 5.2 Issue #443 に「本 Issue (#483) で未達 AC を補完した」コメントを追記
