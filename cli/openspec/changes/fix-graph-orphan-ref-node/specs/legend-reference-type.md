## MODIFIED Requirements

### Requirement: Legend に reference 型が正しく表示される

`generate_graphviz()` の Legend セクションは、deps.yaml に reference 型 skill が存在する場合、reference エントリを表示しなければならない（SHALL）。

#### Scenario: reference 型 skill が存在する
- **WHEN** deps.yaml に type=reference の skill が 1 つ以上存在する
- **THEN** Legend に "Reference (skill)" エントリが shape=note, fillcolor="#e1f5fe" で表示される

#### Scenario: reference 型 skill が存在しない
- **WHEN** deps.yaml に type=reference の skill が存在しない
- **THEN** Legend に "Reference (skill)" エントリは表示されない
