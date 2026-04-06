## ADDED Requirements

### Requirement: クロスリポジトリ変数の入力バリデーション

autopilot-launch.md は Step 5 で tmux コマンドに展開する前に、クロスリポジトリ変数をバリデーションしなければならない（SHALL）。バリデーションは Step 4 と Step 5 の間（Step 4.5）で実行する。

#### Scenario: ISSUE_REPO_OWNER が不正なパターンの場合
- **WHEN** ISSUE_REPO_OWNER が設定されており、`^[a-zA-Z0-9_-]+$` に一致しない
- **THEN** state-write.sh で status=failed、failure に `{"message": "invalid_repo_owner", "step": "launch_worker"}` を書き込み、return 1 する

#### Scenario: ISSUE_REPO_NAME が不正なパターンの場合
- **WHEN** ISSUE_REPO_NAME が設定されており、`^[a-zA-Z0-9_.-]+$` に一致しない
- **THEN** state-write.sh で status=failed、failure に `{"message": "invalid_repo_name", "step": "launch_worker"}` を書き込み、return 1 する

#### Scenario: ISSUE_REPO_OWNER/NAME が未設定の場合
- **WHEN** ISSUE_REPO_OWNER または ISSUE_REPO_NAME が空またはunset
- **THEN** バリデーションをスキップし、正常に次のステップへ進む

### Requirement: PILOT_AUTOPILOT_DIR のパスバリデーション

PILOT_AUTOPILOT_DIR が設定されている場合、パストラバーサル防止のバリデーションを実行しなければならない（MUST）。

#### Scenario: PILOT_AUTOPILOT_DIR が相対パスの場合
- **WHEN** PILOT_AUTOPILOT_DIR が設定されており、`/` で始まらない
- **THEN** state-write.sh で status=failed、failure に `{"message": "invalid_autopilot_dir", "step": "launch_worker"}` を書き込み、return 1 する

#### Scenario: PILOT_AUTOPILOT_DIR にパストラバーサルが含まれる場合
- **WHEN** PILOT_AUTOPILOT_DIR に `..` コンポーネントが含まれる（`/\.\./` または末尾 `/..`）
- **THEN** state-write.sh で status=failed、failure に `{"message": "invalid_autopilot_dir", "step": "launch_worker"}` を書き込み、return 1 する

#### Scenario: PILOT_AUTOPILOT_DIR が未設定の場合
- **WHEN** PILOT_AUTOPILOT_DIR が空またはunset
- **THEN** バリデーションをスキップし、正常に次のステップへ進む

## MODIFIED Requirements

### Requirement: AUTOPILOT_ENV / REPO_ENV のクォート展開

Step 5 の tmux new-window コマンドで、AUTOPILOT_ENV と REPO_ENV の値部分を printf '%q' でクォートしなければならない（MUST）。

#### Scenario: PILOT_AUTOPILOT_DIR にスペースを含むパスが設定されている場合
- **WHEN** PILOT_AUTOPILOT_DIR が "/path/with spaces/autopilot" のような値
- **THEN** AUTOPILOT_ENV が `AUTOPILOT_DIR=/path/with\ spaces/autopilot` のようにクォートされ、tmux コマンドが正しく展開される

#### Scenario: クロスリポジトリ変数が正常値の場合
- **WHEN** ISSUE_REPO_OWNER="shuu5"、ISSUE_REPO_NAME="loom-plugin-dev" が設定されている
- **THEN** REPO_ENV が `REPO_OWNER=shuu5 REPO_NAME=loom-plugin-dev` として安全にクォートされ、従来と同じ動作結果になる
