## ADDED Requirements

### Requirement: ref-invariants-structure.bats 新規作成

`plugins/twl/tests/bats/invariants/ref-invariants-structure.bats` を新規作成し、`ref-invariants.md` の構造を 13 件の section 存在・書式・半角文字強制で自動検証しなければならない（SHALL）。

#### Scenario: 13 件の section 存在を検証する
- **WHEN** `ref-invariants-structure.bats` を実行する
- **THEN** 不変条件 A から M まで各 1 件ずつ、`## 不変条件 X:` ヘッダーの存在が検証される

#### Scenario: 全角コロン混入を検出する
- **WHEN** `ref-invariants.md` に `## 不変条件 A：` のような全角コロンが含まれる
- **THEN** bats テストが FAIL してエラーを報告する

#### Scenario: 全角アルファベット混入を検出する
- **WHEN** `ref-invariants.md` に `## 不変条件 Ａ:` のような全角大文字が含まれる
- **THEN** bats テストが FAIL してエラーを報告する

## MODIFIED Requirements

### Requirement: autopilot-invariants.bats の invariant-J/K grep 対象を切替

`plugins/twl/tests/bats/invariants/autopilot-invariants.bats` の `invariant-J` および `invariant-K` テストの grep 対象を `autopilot.md` から `refs/ref-invariants.md` に変更し、grep パターンを新構造（`## 不変条件 J:` / `## 不変条件 K:`）に合わせて更新しなければならない（SHALL）。

この変更は `autopilot.md` の定義削除（existing-docs-update.md の要件）と同一 PR でアトミックに実装すること（SHALL）。

#### Scenario: invariant-J テストが ref-invariants.md を参照する
- **WHEN** `autopilot-invariants.bats` の invariant-J テストを確認する
- **THEN** grep 対象が `refs/ref-invariants.md` であり、パターンが `## 不変条件 J:` にマッチする

#### Scenario: invariant-K テストが ref-invariants.md を参照する
- **WHEN** `autopilot-invariants.bats` の invariant-K テストを確認する
- **THEN** grep 対象が `refs/ref-invariants.md` であり、パターンが `## 不変条件 K:` にマッチする

#### Scenario: autopilot.md 定義削除後も bats が PASS する
- **WHEN** `autopilot.md` から不変条件 J/K の定義が削除された後に `autopilot-invariants.bats` を実行する
- **THEN** invariant-J および invariant-K の "defines invariant" テストが PASS する
