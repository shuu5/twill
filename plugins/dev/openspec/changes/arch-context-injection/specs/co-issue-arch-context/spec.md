## ADDED Requirements

### Requirement: co-issue architecture context 注入

co-issue の Phase 1 explore 呼び出し時、プロジェクトに `architecture/` ディレクトリが存在する場合、`vision.md`・`domain/context-map.md`・`domain/glossary.md` を Read し、explore の prompt に `## Architecture Context` セクションとして注入しなければならない（SHALL）。ファイルが存在しない場合はスキップし、エラーを出力してはならない（SHALL NOT）。

#### Scenario: architecture/ あり - context 注入
- **WHEN** co-issue Phase 1 を開始し、プロジェクトルートに `architecture/` が存在する
- **THEN** `vision.md`・`domain/context-map.md`・`domain/glossary.md` が読み込まれ、explore の prompt 冒頭に `## Architecture Context` として追記される

#### Scenario: architecture/ なし - スキップ
- **WHEN** co-issue Phase 1 を開始し、プロジェクトルートに `architecture/` が存在しない
- **THEN** architecture context は注入されず、explore は従来通り実行される（エラーなし）

#### Scenario: 一部ファイルが欠損している場合
- **WHEN** `architecture/` は存在するが `domain/context-map.md` が欠損している
- **THEN** 存在するファイルのみ読み込み、欠損ファイルはスキップする（エラー出力なし）
