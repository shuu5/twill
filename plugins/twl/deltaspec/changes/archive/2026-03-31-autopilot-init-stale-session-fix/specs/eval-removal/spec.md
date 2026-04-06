## MODIFIED Requirements

### Requirement: autopilot-init.md の eval 除去

autopilot-init.md はスクリプト実行に `eval` を使用してはならない（MUST NOT）。`bash` コマンドで直接実行し、戻り値は `$?` で確認しなければならない（SHALL）。

#### Scenario: autopilot-init.sh の直接実行
- **WHEN** autopilot-init.md の Step 2 で autopilot-init.sh を実行する
- **THEN** `eval` を使用せず `bash $SCRIPTS_ROOT/autopilot-init.sh` で直接実行し、終了コードで成否判定する

#### Scenario: session-create.sh の直接実行
- **WHEN** autopilot-init.md の Step 4 で session-create.sh を実行する
- **THEN** `eval` を使用せず `bash $SCRIPTS_ROOT/session-create.sh` で直接実行し、出力から SESSION_ID を取得する
