## ADDED Requirements

### Requirement: --real-issues フラグ対応

`test-project-scenario-load` は `--real-issues` フラグを受け付け、シナリオカタログの `issue_templates` を `gh issue create` を使って専用テストリポに実 Issue として起票しなければならない（SHALL）。

#### Scenario: smoke-001 シナリオで実 Issue が起票される
- **WHEN** `test-project-scenario-load --scenario smoke-001 --real-issues` を実行する
- **THEN** `.test-target/config.json` の `repo` フィールドが示す専用テストリポに `smoke-001` の `issue_templates` 全件が `gh issue create` で起票される

#### Scenario: --mode local で init した後に --real-issues を指定した場合にエラーになる
- **WHEN** `.test-target/config.json` の `mode` が `local` の状態で `--real-issues` を実行する
- **THEN** `{"error": "--real-issues を使うには test-project-init --mode real-issues で初期化してください"}` を出力してエラー終了する

### Requirement: loaded-issues.json への記録

起票された Issue の番号と scenario ID のマッピングを `.test-target/loaded-issues.json` に記録しなければならない（SHALL）。

#### Scenario: 起票後に loaded-issues.json が生成される
- **WHEN** `--real-issues` モードで Issue 起票に成功する
- **THEN** `.test-target/loaded-issues.json` に `{"scenario": "<name>", "repo": "<repo>", "loaded_at": "<ISO8601>", "issues": [{"id": "<id>", "number": <N>, "url": "<url>"}]}` 形式で記録される

#### Scenario: loaded-issues.json が git commit に含まれる
- **WHEN** `--real-issues` モードで Issue 起票に成功する
- **THEN** `loaded-issues.json` が `git commit -m "chore(test): load real-issues <scenario>"` に含まれる

### Requirement: 二重起票ガード

`loaded-issues.json` が既に存在し、同一シナリオの記録がある場合、再起票しないようにしなければならない（SHALL）。`--force` フラグで強制再起票できる（SHALL）。

#### Scenario: 既存の loaded-issues.json がある場合は skip する
- **WHEN** `.test-target/loaded-issues.json` が存在し、`scenario` フィールドが一致する状態で `--real-issues` を実行する
- **THEN** 起票をスキップし `{"status": "skipped", "reason": "already loaded", ...}` を出力する

#### Scenario: --force フラグで強制再起票できる
- **WHEN** `loaded-issues.json` が存在する状態で `--real-issues --force` を実行する
- **THEN** 既存 Issue を `gh issue close` してから新たに `gh issue create` し、`loaded-issues.json` を上書きする

## MODIFIED Requirements

### Requirement: --local-only（未指定）の後退互換保証

`--real-issues` フラグが指定されていない場合、`test-project-scenario-load` の動作は変更してはならない（SHALL NOT）。

#### Scenario: フラグ未指定時は既存のローカルファイル生成動作を維持する
- **WHEN** `test-project-scenario-load --scenario smoke-001`（`--real-issues` フラグなし）を実行する
- **THEN** 従来通り `.test-target/issues/<id>.md` にローカルファイルが生成され、`loaded-issues.json` は作成されない
