## ADDED Requirements

### Requirement: switchover.sh check サブコマンド

`scripts/switchover.sh check` は切替前の事前チェックを実行しなければならない（SHALL）。チェック項目: loom validate の pass、loom check の pass、tmux 内 autopilot セッション未稼働、現在の symlink パス確認。全チェック pass 時に exit 0、いずれか fail 時に exit 1 と詳細メッセージを返す。

#### Scenario: 全チェック pass
- **WHEN** loom validate/check が pass かつ autopilot セッションが未稼働
- **THEN** exit 0 を返し「切替可能」メッセージを表示する

#### Scenario: autopilot セッション稼働中
- **WHEN** tmux 内に DEV_AUTOPILOT_SESSION=1 のセッションが存在する
- **THEN** exit 1 を返し「in-flight セッション検出、切替を中止」と表示する

#### Scenario: loom validate 失敗
- **WHEN** loom validate が fail を返す
- **THEN** exit 1 を返し検証失敗の詳細を表示する

### Requirement: switchover.sh switch サブコマンド

`scripts/switchover.sh switch` は check 実行後に symlink 切替を実行しなければならない（MUST）。手順: check 実行 → 旧 symlink バックアップ（`~/.claude/plugins/dev.bak`）→ 旧状態ファイル cleanup → 新 symlink 作成。check が fail した場合は切替を中止する。

#### Scenario: 正常切替
- **WHEN** check が pass かつバックアップ先に既存ファイルがない
- **THEN** 旧 symlink を `dev.bak` にリネームし、新 symlink を作成する

#### Scenario: 既存バックアップあり
- **WHEN** `~/.claude/plugins/dev.bak` が既に存在する
- **THEN** 上書き確認プロンプトを表示し、承認なしでは切替を中止する

#### Scenario: check 失敗時の中止
- **WHEN** check が exit 1 を返す
- **THEN** symlink 変更を行わずに exit 1 で終了する

### Requirement: switchover.sh rollback サブコマンド

`scripts/switchover.sh rollback` はバックアップから旧 symlink を復元しなければならない（SHALL）。新プラグインの状態ファイルを cleanup し、旧 symlink を復元する。

#### Scenario: 正常ロールバック
- **WHEN** `~/.claude/plugins/dev.bak` が存在する
- **THEN** 現在の symlink を削除し、バックアップから旧 symlink を復元する

#### Scenario: バックアップ不在
- **WHEN** `~/.claude/plugins/dev.bak` が存在しない
- **THEN** エラーメッセージ「バックアップが見つかりません」を表示し exit 1

### Requirement: switchover.sh retire サブコマンド

`scripts/switchover.sh retire` は試運転完了後の退役処理を実行しなければならない（MUST）。バックアップ symlink の削除と、claude-plugin-dev リポジトリのアーカイブ案内を表示する。

#### Scenario: 正常退役
- **WHEN** バックアップが存在し、ユーザーが確認を承認する
- **THEN** バックアップを削除し、`gh repo archive` コマンドの案内を表示する

#### Scenario: 退役キャンセル
- **WHEN** ユーザーが確認を拒否する
- **THEN** 何も変更せず exit 0 で終了する
