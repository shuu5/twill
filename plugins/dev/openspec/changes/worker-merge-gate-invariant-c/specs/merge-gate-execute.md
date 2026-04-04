## MODIFIED Requirements

### Requirement: merge-gate-execute.sh が status=running 時に merge を拒否する

merge-gate-execute.sh の merge 実行パス（デフォルト分岐）は、IssueState.status が "running"（Worker が merge-ready 未宣言）の場合、merge を拒否しなければならない（SHALL）。

#### Scenario: status=running での merge ブロック
- **WHEN** merge-gate-execute.sh がデフォルトモード（merge 実行）で呼ばれ、state-read.sh が status=running を返す
- **THEN** exit 1 を返し、merge を実行しない

#### Scenario: status=merge-ready での merge 許可
- **WHEN** merge-gate-execute.sh がデフォルトモードで呼ばれ、state-read.sh が status=merge-ready を返す
- **THEN** merge を実行する（exit 1 しない）

#### Scenario: --reject モードは status=running の影響を受けない
- **WHEN** merge-gate-execute.sh が --reject モードで呼ばれ、state-read.sh が status=running を返す
- **THEN** --reject のリジェクト処理を正常実行し、exit 1 しない

#### Scenario: status 空（非 autopilot 環境）での merge 許可
- **WHEN** merge-gate-execute.sh がデフォルトモードで呼ばれ、state-read.sh が空文字列を返す
- **THEN** merge を実行する（exit 1 しない）
