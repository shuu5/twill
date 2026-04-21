## ADDED Requirements

### Requirement: ref-invariants.md 新規作成

`plugins/twl/refs/ref-invariants.md` を新規作成し、不変条件 A-M（13 件）の定義を単一ドキュメントに一本化しなければならない（SHALL）。

各不変条件は以下の形式で記述しなければならない（SHALL）:

```
## 不変条件 X: <title>

- **定義**: <1 文の要件>
- **根拠**: <ADR リンク or DeltaSpec spec リンク or "ADR なし — 慣習的制約">
- **検証方法**: `<bats テスト関数名>` または `grep -r '<pattern>' <path>`
- **影響範囲**: <code path 箇条書き>
```

#### Scenario: 全 13 件の section が存在する
- **WHEN** `plugins/twl/refs/ref-invariants.md` を読み込む
- **THEN** `## 不変条件 [A-M]` 形式の section が A から M まで 13 件すべて存在する

#### Scenario: 半角コロンと半角大文字を使用する
- **WHEN** `ref-invariants.md` の section ヘッダーを検査する
- **THEN** `## 不変条件 A:` 〜 `## 不変条件 M:` に全角文字・全角コロンが含まれない

#### Scenario: ADR なし条件（H/A/C/L）の根拠フィールド
- **WHEN** 不変条件 H、A、C、L の根拠フィールドを確認する
- **THEN** "ADR なし — 慣習的制約" と記載されている

#### Scenario: DeltaSpec spec リンク条件（D/E/F/G/I/J/K）の根拠フィールド
- **WHEN** 不変条件 D、E、F、G、I、J、K の根拠フィールドを確認する
- **THEN** `autopilot-lifecycle.md` または `merge-gate.md` の該当 anchor へのリンクが記載されている

#### Scenario: L/M の検証方法フィールド
- **WHEN** 不変条件 L、M の検証方法フィールドを確認する
- **THEN** "#789 で bats テスト生成予定" と注記されている

### Requirement: deps.yaml への ref-invariants エントリ追加

`plugins/twl/deps.yaml` に `ref-invariants` エントリを `type: reference` として追加しなければならない（SHALL）。

#### Scenario: deps.yaml に ref-invariants エントリが存在する
- **WHEN** `plugins/twl/deps.yaml` を確認する
- **THEN** `ref-invariants` という名前のエントリが `type: reference` で存在する

### Requirement: README.md の Refs 一覧更新

`plugins/twl/README.md` の Refs セクションを更新し、`ref-invariants` を追加して合計カウントを 19 にしなければならない（SHALL）。

#### Scenario: README Refs に ref-invariants が追加される
- **WHEN** `plugins/twl/README.md` の Refs セクションを確認する
- **THEN** `ref-invariants` エントリが存在し、Refs の合計カウントが 19 である
