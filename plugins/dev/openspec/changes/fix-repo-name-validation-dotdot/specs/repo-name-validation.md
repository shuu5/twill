## MODIFIED Requirements

### Requirement: リポジトリ名バリデーションで `..` および `.` を拒否する

`autopilot-plan-board.sh` の `_build_cross_repo_json` 関数は、クロスリポジトリ名を検証する際に `..` および `.` を拒否しなければならない（SHALL）。

正規表現パターンは `^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$` を使用し、先頭文字に `.` を禁止すること（MUST）。さらに `..` および `.` を明示的に拒否する条件を追加しなければならない（MUST）。

#### Scenario: `..` がバリデーションで拒否される

- **WHEN** `cross_name` に `..` が渡された場合
- **THEN** バリデーションで失敗し、そのエントリをスキップする

#### Scenario: `.` がバリデーションで拒否される

- **WHEN** `cross_name` に `.` が渡された場合
- **THEN** バリデーションで失敗し、そのエントリをスキップする

#### Scenario: 有効なリポジトリ名が通過する

- **WHEN** `cross_name` に `my-repo`、`repo.js`、`repo_v2` などの有効な名前が渡された場合
- **THEN** バリデーションを通過し、処理が継続される

#### Scenario: 変更範囲が `autopilot-plan-board.sh` のみに限定される

- **WHEN** バリデーション修正を実施した場合
- **THEN** 変更されたファイルは `scripts/autopilot-plan-board.sh` のみである
