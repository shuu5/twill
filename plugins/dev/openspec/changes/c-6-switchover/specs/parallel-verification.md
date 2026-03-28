## ADDED Requirements

### Requirement: 並行検証チェックリスト

並行検証フェーズの手順を `docs/switchover-guide.md` に文書化しなければならない（SHALL）。検証項目: `claude --plugin-dir` による新プラグインテスト、旧プラグインとの同一 Issue 動作比較、loom validate/check/audit の全 pass 確認。

#### Scenario: 検証手順の網羅性
- **WHEN** docs/switchover-guide.md を参照する
- **THEN** 並行検証の全ステップ（テスト方法、比較対象、pass 基準）が記載されている

#### Scenario: plugin-dir による非破壊テスト
- **WHEN** `claude --plugin-dir` で新プラグインをテストする
- **THEN** 旧プラグインの symlink を変更せずに新プラグインの動作を確認できる
