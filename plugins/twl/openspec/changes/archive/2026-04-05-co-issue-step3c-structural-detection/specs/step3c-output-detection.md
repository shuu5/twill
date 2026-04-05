## MODIFIED Requirements

### Requirement: Step 3c 出力なし完了検知の構造的判定

`skills/co-issue/SKILL.md` の Step 3c「[前処理] 出力なし完了の検知（上位ガード）」を、行頭縛り正規表現による構造的判定に変更しなければならない（SHALL）。`status:` および `findings:` の単純キーワード検索から以下のパターンに置き換える:

- status 検出: `^status:\s*(PASS|WARN|FAIL)` （行頭、コロン後スペース任意、有効値のみ）
- findings 検出: `^findings:` （行頭）

いずれのパターンにもマッチしない場合を「出力なし」として WARNING エントリを追加する。

#### Scenario: 正常な specialist 出力（行頭 status）

- **WHEN** specialist の返却値が行頭に `status: PASS` を含む
- **THEN** status 検出に成功し、WARNING エントリを追加しない

#### Scenario: 文中の偶然の status キーワード（誤検知ケース）

- **WHEN** specialist の返却値が `message: "status: PASS"` や `"status: ok"` のような文中キーワードのみを含み、行頭に `^status:\s*(PASS|WARN|FAIL)` のマッチがない
- **THEN** 「出力なし」と判定し、WARNING エントリを追加する

#### Scenario: 行頭 findings のみ存在する場合

- **WHEN** specialist の返却値が行頭に `findings:` を含み、`^status:\s*(PASS|WARN|FAIL)` は含まない
- **THEN** findings 検出に成功し、WARNING エントリを追加しない（findings が存在するため出力ありと判定）

#### Scenario: 完全に空または非構造化の出力

- **WHEN** specialist の返却値にいずれのパターンもマッチしない
- **THEN** findings テーブルに `WARNING: <specialist名>: 構造化出力なしで完了（調査が maxTurns に到達した可能性）` を追加する。Phase 4 はブロックしない

### Requirement: ref-specialist-output-schema との関係注記

`skills/co-issue/SKILL.md` Step 3c の出力なし検知セクションに、`ref-specialist-output-schema.md` との関係を注記しなければならない（SHALL）。

#### Scenario: SKILL.md に注記が存在する

- **WHEN** Step 3c の出力なし検知セクションを参照する
- **THEN** 「本ガードは `refs/ref-specialist-output-schema.md` の消費側パースルールの上位ガードとして、行頭縛りを追加適用する（ref 自体は変更しない）」旨の注記が存在する
