## ADDED Requirements

### Requirement: クロスリポ検出

co-issue Phase 2 は explore-summary.md の読み込み後にクロスリポ検出を実行しなければならない（SHALL）。検出は以下の条件のいずれかを満たす場合にクロスリポと判定する:

1. 複数リポ名の明示的言及（2つ以上の異なるリポ名）
2. クロスリポキーワード（「全リポ」「3リポ」「各リポ」「クロスリポ」等）
3. 複数リポのファイルパスパターン

#### Scenario: 3リポ横断の要望を検出する
- **WHEN** explore-summary.md に「loom, loom-plugin-dev, loom-plugin-session の3リポに配置」という記述がある
- **THEN** クロスリポ横断として検出され、対象リポリスト `[loom, loom-plugin-dev, loom-plugin-session]` が生成される

#### Scenario: 単一リポの要望はスルーする
- **WHEN** explore-summary.md に単一リポのみの変更記述がある
- **THEN** クロスリポ検出はトリガーされず、従来の分解判断フローに進む

#### Scenario: 「全リポ」キーワードで検出する
- **WHEN** explore-summary.md に「全リポに適用」というキーワードがある
- **THEN** 現在のリポが属する Project のリンク済み全リポがクロスリポ対象として検出される

### Requirement: リポ一覧の動的取得

クロスリポ検出時、対象リポ一覧は GitHub Project のリンク済みリポジトリから動的に取得しなければならない（MUST）。ハードコードされたリポリストを使用してはならない。

#### Scenario: Project リンク済みリポから取得する
- **WHEN** 現在のリポが GitHub Project #3 (loom-dev-ecosystem) にリンクされている
- **THEN** 同 Project にリンクされた全リポ（loom, loom-plugin-dev, loom-plugin-session）が対象リポ一覧として返される

#### Scenario: Project にリンクされていない場合
- **WHEN** 現在のリポがどの Project にもリンクされていない
- **THEN** クロスリポ検出は実行されず、従来の分解判断フローに進む

### Requirement: 分割提案の確認

クロスリポ検出時、ユーザーに AskUserQuestion でリポ単位分割を提案しなければならない（SHALL）。

#### Scenario: ユーザーが分割を承認する
- **WHEN** クロスリポ検出後に分割提案が表示され、ユーザーが承認を選択する
- **THEN** Phase 3 以降はリポ単位の子 Issue 構造で精緻化が進む

#### Scenario: ユーザーが分割を拒否する
- **WHEN** クロスリポ検出後に分割提案が表示され、ユーザーが拒否を選択する
- **THEN** 従来通り単一 Issue として Phase 3 以降の処理に進む
