## 1. コンポーネントマッピング表

- [x] 1.1 `architecture/migration/` ディレクトリを作成する
- [x] 1.2 `architecture/migration/component-mapping.md` を作成し、旧 dev plugin の全コンポーネント（controller 9, workflow 7, atomic 30, specialist 27, script 15, reference 5）の旧→新マッピングを記載する
- [x] 1.3 各コンポーネントにカテゴリ（吸収/削除/移植/新規）と根拠を記載する

## 2. B-3/C-4 スコープ境界定義

- [x] 2.1 `architecture/migration/scope-boundary.md` を作成し、B-3（セッション構造変更）/ B-5（merge-gate 判定ロジック変更）/ C-4（インターフェース適応）の分類基準を定義する
- [x] 2.2 全 script をスコープ境界テーブルに分類する

## 3. Specialist 共通出力スキーマ仕様

- [x] 3.1 `architecture/contracts/specialist-output-schema.md` を作成し、JSON スキーマ（status, severity, confidence, findings）の詳細仕様を定義する
- [x] 3.2 PASS ケースと FAIL ケースの few-shot 例を各 1 つ追加する
- [x] 3.3 消費側パースルール（正規表現、ブロック判定基準、フォールバック）を記載する
- [x] 3.4 Model 割り当て表（haiku/sonnet/opus の判定基準と対象一覧）を同ファイルの model セクションに追加する

## 4. Bare repo 検証ルール・Worktree ライフサイクル

- [x] 4.1 `architecture/domain/contexts/project-mgmt.md` を作成し、bare repo 正規構造と 3 検証条件を記載する
- [x] 4.2 `architecture/domain/contexts/autopilot.md` に worktree ライフサイクルセクション（作成→使用→削除の Pilot/Worker 役割）を追記する

## 5. OpenSpec シナリオ

- [x] 5.1 `openspec/specs/autopilot-lifecycle.md` を作成し、autopilot セッションフロー（起動→plan 生成→Phase ループ→完了サマリー）のシナリオを定義する
- [x] 5.2 `openspec/specs/merge-gate.md` を作成し、merge-gate ワークフロー（動的レビュアー→並列 specialist→判定）のシナリオを定義する
- [x] 5.3 `openspec/specs/project-create.md` を作成し、project create ワークフロー（bare repo→worktree→テンプレート→Board）のシナリオを定義する

## 6. 検証

- [x] 6.1 Issue #3 の全 AC（12 項目）をチェックし、全て満たされていることを確認する
- [x] 6.2 既存の architecture/ 文書（ADR-001〜005, domain/, contracts/）との整合性を確認する
