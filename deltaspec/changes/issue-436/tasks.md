## 1. cli/twl: spec/new.py の issue フィールド自動付与

- [ ] 1.1 `_ISSUE_RE = re.compile(r"^issue-(\d+)$")` を定義する
- [ ] 1.2 `cmd_new()` で name が `_ISSUE_RE` にマッチした場合に `issue_line` を生成する
- [ ] 1.3 `.deltaspec.yaml` の write_text に `name:`, `status:`, `issue:` フィールドを追加する
- [ ] 1.4 unit test: `test_spec_new.py` に issue フィールド付与・非付与のテストを追加する

## 2. plugins/twl: autopilot-orchestrator.sh のフォールバック検索追加

- [ ] 2.1 `_archive_deltaspec_changes_for_issue()` のプライマリ grep ループを抽出して共通化する
- [ ] 2.2 `found == "false"` のフォールバック処理として `grep -rl "^name: issue-${issue}$"` ループを追加する
- [ ] 2.3 integration test: `issue:` フィールドなしの `.deltaspec.yaml` でフォールバック検出を確認する

## 3. cli/twl: orchestrator.py のフォールバック検索追加

- [ ] 3.1 `_archive_deltaspec_changes()` のループ内に `name: issue-<N>` フォールバック条件を追加する（`elif` で `found` を true にする）
- [ ] 3.2 二重 archive を防ぐためにループ内の早期 `continue` を確認する
- [ ] 3.3 unit test: `test_orchestrator.py` にフォールバック検索のテストを追加する

## 4. 動作確認

- [ ] 4.1 `twl spec new "issue-999"` を実行し `.deltaspec.yaml` に `issue: 999` が付与されることを確認する
- [ ] 4.2 `issue:` フィールドなしの既存 change に対して orchestrator の archive が成功することを確認する
