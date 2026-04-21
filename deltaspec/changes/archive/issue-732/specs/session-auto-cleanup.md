## ADDED Requirements

### Requirement: autopilot-init.sh 完了済みセッション自動削除

`autopilot-init.sh` は既存セッション検出時、`is_session_completed()=true` であれば `--force` なしで session.json と issues/issue-*.json を自動削除しなければならない（SHALL）。

#### Scenario: 完了済み session.json が存在する場合の自動削除

- **WHEN** `autopilot-init.sh` を `--force` なしで実行し、既存 session.json に全 issue の `status=done` が記録されている
- **THEN** session.json と issues/issue-*.json が削除され exit 0 で続行する

#### Scenario: issues フィールドが空の session.json は完了済みとみなさない

- **WHEN** `autopilot-init.sh` を実行し、既存 session.json の `issues` フィールドが空配列（`[]`）である
- **THEN** `is_session_completed()` は false を返し、実行中エラー exit 1 で停止する（新 Wave 直後の誤発火防止）

#### Scenario: running issue が存在する場合は停止

- **WHEN** `autopilot-init.sh` を実行し、既存 session.json に `status=running` の issue が 1 つ以上存在する
- **THEN** 自動削除は発火せず exit 1 で停止する

#### Scenario: 24h 経過 + --force なし の未完了セッションは既存挙動維持

- **WHEN** `autopilot-init.sh` を `--force` なしで実行し、session.json が 24h 以上経過かつ未完了（running issue あり）
- **THEN** exit 2 で stale 警告を出力する（既存挙動と同一）

### Requirement: orchestrator ログ per-session 分離

orchestrator のログファイル名は `session_id` を含まなければならず（SHALL）、Wave をまたいで同一ファイルへの追記が発生してはならない（MUST NOT）。

#### Scenario: session_id 付きログが生成される

- **WHEN** 2 連続 Wave を起動する
- **THEN** `${AUTOPILOT_DIR}/trace/` に `orchestrator-phase-${N}-${SESSION_ID}.log` が各 Wave につき 1 ファイル生成され、各ファイルの session_id 部分が異なる

#### Scenario: session.json 不在時に WARN を出力

- **WHEN** `autopilot-pilot-wakeup-loop.md` の _ORCH_LOG 生成処理実行時に session.json が存在しない
- **THEN** stderr に `WARN: session.json が不在またはパース失敗。Wave ログ分離が無効になります` を出力し、`orchestrator-phase-${N}-unknown.log` を使用して続行する

#### Scenario: orchestrator.sh 書き込み先が wakeup-loop.md と同一

- **WHEN** orchestrator が実行ログを書き込む
- **THEN** ログが `orchestrator-phase-${PHASE_NUM}-${SESSION_ID}.log` に書き込まれ、wakeup-loop.md の _ORCH_LOG と同一パスを参照する

### Requirement: AC 2 再修正防止マーカー

`autopilot-pilot-wakeup-loop.md` の Step A に AC 2 hotfix（L26 絶対パス）の再修正防止コメントが存在しなければならない（SHALL）。

#### Scenario: HOTFIX コメントが 2 箇所に存在する

- **WHEN** `grep -c "HOTFIX #732" plugins/twl/commands/autopilot-pilot-wakeup-loop.md` を実行する
- **THEN** 出力が `2`（HTML コメントと blockquote の 2 箇所）である
