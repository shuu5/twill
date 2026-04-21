## 1. ADR-015 ドキュメント更新

- [ ] 1.1 `ADR-015-deltaspec-auto-init.md` の `Status` を `Proposed` → `Accepted` に変更する
- [ ] 1.2 ADR-015 に `## Accept 判断基準` セクションを追加し、互換性・実装コスト・運用影響・テスト容易性の4軸評価を記載する
- [ ] 1.3 ADR-015 の `Decision 1` テキストを現実装（`deltaspec_dir.is_dir()` チェック維持 + `propose+auto_init` 返却）に合わせて更新する

## 2. コードコメント補強

- [ ] 2.1 `chain.py:step_init()` の `deltaspec/` 不在ブランチ（L277-285）に ADR-015 参照コメントを追加する

## 3. テスト追加

- [ ] 3.1 `cli/twl/tests/test_autopilot_chain.py` の `TestStepInit` クラスに `issue_num` あり auto_init ケースのテスト（`_write_state_field mode=propose` 呼び出し検証）を追加する
- [ ] 3.2 `plugins/twl/tests/bats/commands/change-propose-auto-init.bats` を作成し、`MODE=propose + DELTASPEC_EXISTS=false` の auto_init 判定ロジックをテストする

## 4. 検証

- [ ] 4.1 `cd cli/twl && pytest tests/test_autopilot_chain.py::TestStepInit -v` が全 PASS することを確認する
- [ ] 4.2 新規 bats テストが PASS することを確認する（`bats plugins/twl/tests/bats/commands/change-propose-auto-init.bats`）
- [ ] 4.3 `twl check` が PASS することを確認する
