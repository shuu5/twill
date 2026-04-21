## MODIFIED Requirements

### Requirement: ADR-015 ステータス確定

ADR-015 の Status フィールドを `Proposed` から `Accepted` に更新し、Accept 判断基準を ADR 本文に明文化しなければならない（SHALL）。判断基準は互換性・実装コスト・運用影響・テスト容易性の4軸を含まなければならない（SHALL）。

#### Scenario: ADR ステータス更新
- **WHEN** `plugins/twl/architecture/decisions/ADR-015-deltaspec-auto-init.md` の Status フィールドを編集する
- **THEN** `Status: Accepted` に変更され、`## Accept 判断基準` セクションが追加されている

#### Scenario: 判断基準セクション完備
- **WHEN** ADR-015 の Accept 判断基準セクションを確認する
- **THEN** 互換性・実装コスト・運用影響・テスト容易性の4項目それぞれに評価結果と根拠が記載されている

### Requirement: ADR Decision テキストの実装合わせ

ADR-015 の Decision 1（`deltaspec/` 存在チェック削除）テキストを現実装（チェック維持・返却値変更）に合わせて更新しなければならない（SHALL）。機能的同値であることと、実装が段階的状態遷移を明確にする利点を明記しなければならない（SHALL）。

#### Scenario: Decision テキスト更新
- **WHEN** ADR-015 の Decision 1 セクションを確認する
- **THEN** 「`deltaspec_dir.is_dir()` が `False` のとき `recommend_action=propose + auto_init=True` を返す」という現実装の記述を含み、元の「チェック削除」記述から更新されている

## ADDED Requirements

### Requirement: step_init auto_init パスの docstring 補強

`chain.py:step_init()` の `deltaspec/` 不在ブランチに、ADR-015 への参照と auto_init の意図を示すコメントを追加しなければならない（SHALL）。

#### Scenario: docstring 追加後のコード検証
- **WHEN** `cli/twl/src/twl/autopilot/chain.py` の `step_init()` 内の auto_init ブロックを確認する
- **THEN** `# ADR-015:` または `# auto_init:` で始まるコメントが存在し、auto_init の意図が 1 行以内で説明されている

### Requirement: step_init auto_init の pytest テスト補完

`issue_num` が与えられた場合の `step_init()` auto_init パスをテストしなければならない（SHALL）。state への `mode=propose` 書き込みが呼び出されることを検証しなければならない（SHALL）。

#### Scenario: issue_num あり auto_init テスト
- **WHEN** `step_init("784")` を `deltaspec/` 不在の環境で実行する
- **THEN** `recommended_action == "propose"` かつ `auto_init is True` が返り、`_write_state_field` が `mode=propose` で呼び出される

### Requirement: change-propose Step 0 の bats テスト追加

`plugins/twl/tests/bats/` 配下に、`change-propose` Step 0 の auto_init フローを検証する bats テストを追加しなければならない（SHALL）。

#### Scenario: bats テストファイル作成
- **WHEN** `plugins/twl/tests/bats/` に change-propose の bats テストファイルを作成する
- **THEN** ファイルが存在し、`MODE=propose` かつ `DELTASPEC_EXISTS=false` の条件で auto_init チェックが正しく機能することを検証するテストケースを含む

#### Scenario: auto_init 条件検証
- **WHEN** `MODE=propose` かつ `deltaspec/config.yaml` が存在しない状態で auto_init チェックロジックを実行する
- **THEN** `DELTASPEC_EXISTS=false` と判定され、auto_init パス（`twl spec new` 実行）に進むことが確認される
