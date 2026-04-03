## MODIFIED Requirements

### Requirement: PROJECT_NUMBERS の mapfile パターン統一

プロジェクト番号を取得してイテレーションする全箇所は、`mapfile -t` + `"${ARRAY[@]}"` パターンを使用しなければならない（SHALL）。unquoted word-split に依存してはならない（MUST NOT）。

#### Scenario: project-board-archive.sh のイテレーション
- **WHEN** `project-board-archive.sh` がプロジェクト番号リストを取得してループする
- **THEN** `mapfile -t PROJECT_NUMS < <(...)` で配列に格納し `"${PROJECT_NUMS[@]}"` でイテレーションすること

#### Scenario: project-board-backfill.sh のイテレーション
- **WHEN** `project-board-backfill.sh` がプロジェクト番号リストを取得してループする
- **THEN** `mapfile -t PROJECT_NUMS < <(...)` で配列に格納し `"${PROJECT_NUMS[@]}"` でイテレーションすること

#### Scenario: chain-runner.sh の2箇所のイテレーション
- **WHEN** `chain-runner.sh` 内の board-status-update および関連処理でプロジェクト番号リストをループする
- **THEN** 各箇所で `mapfile -t project_nums < <(...)` で配列に格納し `"${project_nums[@]}"` でイテレーションすること

#### Scenario: autopilot-plan-board.sh のイテレーション（バリデーション維持）
- **WHEN** `autopilot-plan-board.sh` がプロジェクト番号リストを取得してループする
- **THEN** `mapfile -t project_nums < <(...)` で配列に格納し `"${project_nums[@]}"` でイテレーションすること、かつ数値バリデーションガード `[[ ! "$pnum" =~ ^[0-9]+$ ]] && continue` を維持すること

### Requirement: shellcheck 準拠

修正後のスクリプトは `shellcheck` で word-split 関連 WARNING が出力されてはならない（MUST NOT）。

#### Scenario: shellcheck 検証
- **WHEN** 修正後の4スクリプトに対して `shellcheck` を実行する
- **THEN** SC2206 / SC2207 / SC2086 等の word-split 関連 WARNING がゼロであること
