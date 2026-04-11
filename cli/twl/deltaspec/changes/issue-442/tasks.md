## 1. シナリオ追加

- [x] 1.1 regression-003（full-chain）シナリオを test-scenario-catalog.md に追加する
- [x] 1.2 regression-004（Bug #436 再現）シナリオを test-scenario-catalog.md に追加する
- [x] 1.3 regression-005（Bug #438 再現）シナリオを test-scenario-catalog.md に追加する
- [x] 1.4 regression-006（Bug #439 再現）シナリオを test-scenario-catalog.md に追加する

## 2. 検証

- [x] 2.1 各シナリオの YAML フォーマットが既存の schema（level, description, issues_count, expected_duration_min/max, expected_conflicts, expected_pr_count, observer_polling_interval, issue_templates）に準拠していることを確認する
- [x] 2.2 各 issue_template に Bug 再現条件が明記されていることを確認する
