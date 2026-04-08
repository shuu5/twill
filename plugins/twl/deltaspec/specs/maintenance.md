# Maintenance

workflow-tech-debt-triage、workflow-dead-cleanup、co-utility によるメンテナンス操作を定義するシナリオ。

## Scenario: tech-debt 棚卸し正常実行

- **WHEN** workflow-tech-debt-triage が実行される
- **THEN** tech-debt/warning と tech-debt/deferred-high ラベルの Issue が全件取得される
- **AND** 0 件の場合は「tech-debt Issue なし」と通知して終了する
- **AND** 各 Issue がキーワード抽出→spec 照合で「解決済み」か判定される
- **AND** 未解決 Issue がタイトル・本文のキーワード比較で「統合候補」としてグルーピングされる
- **AND** 言及されたファイル・モジュールが存在しない Issue が「不適切」と判定される
- **AND** いずれにも該当しない Issue が「要継続」に分類される
- **AND** 4 カテゴリの分類結果が `/twl:triage-execute` に渡されて一括処理される

## Scenario: tech-debt 棚卸しのユーザー確認

- **WHEN** triage-execute が分類結果を処理する
- **THEN** ユーザー確認なしで Issue をクローズ・統合してはならない
- **AND** Issue 番号は gh 出力から正確に取得し推測してはならない

## Scenario: dead component 検出と削除

- **WHEN** workflow-dead-cleanup が実行される
- **THEN** `/twl:dead-component-detect` で不要コンポーネントが検出される
- **AND** 0 件なら正常終了する
- **AND** AskUserQuestion で削除対象が選択される（全て / 個別選択 / スキップ）
- **AND** 外部参照ありが選択された場合は警告表示し再確認される
- **AND** 選択結果が `/twl:dead-component-execute` で実行される

## Scenario: co-utility モード判定

- **WHEN** co-utility が実行される
- **AND** プロンプトにキーワードが含まれる
- **THEN** キーワードマッチでカテゴリ→コマンドが特定される
- **AND** 1 コマンドに絞れる場合は即座に実行される
- **AND** カテゴリ内で曖昧な場合は候補をテーブル表示し AskUserQuestion で選択される

## Scenario: co-utility 対話的ツール紹介

- **WHEN** co-utility がプロンプトなしで実行される
- **THEN** 全カテゴリのコマンドがテーブルで紹介される（Worktree / 検証 / 開発ユーティリティ）
- **AND** AskUserQuestion でコマンド選択が求められる

## Scenario: co-utility コマンド実行

- **WHEN** コマンドが特定される
- **THEN** 対応する Skill が呼び出される
- **AND** ユーザーのプロンプトに追加コンテキスト（パス、オプション等）が含まれている場合はそのまま引数として渡される
