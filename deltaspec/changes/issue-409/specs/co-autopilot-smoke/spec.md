## ADDED Requirements

### Requirement: co-autopilot smoke test スクリプト

`plugins/twl/tests/scenarios/co-autopilot-smoke.test.sh` を追加し、Pilot 起動フローのランタイム動作を検証しなければならない（SHALL）。テストは依存ツールが不在の場合 SKIP でグレースフルに終了しなければならない（SHALL）。

#### Scenario: plan.yaml 生成の smoke test
- **WHEN** `autopilot-plan.sh --explicit "409" --project-dir TMPDIR --repo-mode single` を実行し、`gh` コマンドが認証済みの場合
- **THEN** `TMPDIR/.autopilot/plan.yaml` が生成され、exit code が 0 であること

#### Scenario: plan.yaml 生成スキップ（gh 未認証）
- **WHEN** `gh` コマンドが認証されていない、または利用不可の場合
- **THEN** テストを SKIP し、exit code が非ゼロにならないこと

#### Scenario: state write/read の基本動作確認
- **WHEN** `python3 -m twl.autopilot.state write --type issue --issue 999 --role worker --set "status=running"` を一時ディレクトリで実行する
- **THEN** exit code が 0 であり、`python3 -m twl.autopilot.state read --field status` が `running` を返すこと

#### Scenario: state モジュール不在時のスキップ
- **WHEN** `python3 -m twl.autopilot.state` が import エラーを起こす場合（PYTHONPATH 未設定等）
- **THEN** テストを SKIP し、exit code が非ゼロにならないこと

### Requirement: テスト形式の一貫性

smoke test は既存の `skillmd-pilot-fixes.test.sh` と同一形式（PASS/FAIL/SKIP カウンタ、`run_test` / `run_test_skip` ヘルパー）を使用しなければならない（SHALL）。

#### Scenario: テスト結果サマリー出力
- **WHEN** smoke test を実行する
- **THEN** `Results: X passed, Y failed, Z skipped` の形式でサマリーが表示され、FAIL 数が exit code になること
