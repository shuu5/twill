## MODIFIED Requirements

### Requirement: project-board-sync の Project 検出改善

project-board-sync は複数の Project がリポジトリにリンクされている場合、リポジトリ名と Project タイトルのマッチングを優先して正しい Project を選択しなければならない（MUST）。

#### Scenario: リポジトリ名と Project タイトルが一致する場合
- **WHEN** リポジトリ `shuu5/loom-plugin-dev` にリンクされた Project が `loom-plugin-dev` (#3) と `ipatho1 研究基盤` (#5) の2つ存在する
- **THEN** Project タイトルがリポジトリ名を含む `loom-plugin-dev` (#3) が選択される

#### Scenario: タイトルマッチなしの場合のフォールバック
- **WHEN** リポジトリにリンクされた複数の Project のいずれもタイトルがリポジトリ名と一致しない
- **THEN** リポジトリがリンクされた最初の Project を使用し、警告メッセージを出力する

#### Scenario: 単一 Project の場合
- **WHEN** リポジトリにリンクされた Project が1つのみ
- **THEN** その Project がそのまま使用され、マッチングロジックはスキップされる
