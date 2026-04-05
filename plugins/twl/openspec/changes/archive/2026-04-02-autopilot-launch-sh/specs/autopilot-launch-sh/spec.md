## ADDED Requirements

### Requirement: autopilot-launch.sh スクリプト新設

`scripts/autopilot-launch.sh` はフラグ形式引数で Worker 起動の全決定的処理を実行しなければならない（SHALL）。

#### Scenario: 必須引数による正常起動
- **WHEN** `--issue 42 --project-dir /path/to/project --autopilot-dir /path/to/.autopilot` で実行
- **THEN** tmux new-window が作成され、cld が AUTOPILOT_DIR 環境変数付きで起動される

#### Scenario: cld パス解決
- **WHEN** スクリプトが実行される
- **THEN** `command -v cld` で cld パスを解決しなければならない（MUST）。見つからない場合は state-write で failed を記録し終了コード 2 で終了

#### Scenario: issue state 初期化
- **WHEN** スクリプトが実行される
- **THEN** `state-write.sh --type issue --issue $ISSUE --role worker --init` で issue-{N}.json を初期化しなければならない（MUST）

#### Scenario: ISSUE 数値バリデーション
- **WHEN** `--issue abc` のように非数値が渡される
- **THEN** エラーメッセージを出力し終了コード 1 で終了しなければならない（SHALL）

#### Scenario: パストラバーサル防止
- **WHEN** `--autopilot-dir /path/../etc/passwd` のように `..` を含むパスが渡される
- **THEN** エラーメッセージを出力し state-write で failed を記録して終了コード 1 で終了しなければならない（MUST）

#### Scenario: bare repo 検出と LAUNCH_DIR 計算
- **WHEN** `--project-dir` のパスに `.bare/` ディレクトリが存在する
- **THEN** `LAUNCH_DIR` を `$PROJECT_DIR/main` に設定しなければならない（SHALL）
- **WHEN** `.bare/` が存在しない
- **THEN** `LAUNCH_DIR` を `$PROJECT_DIR` のまま使用する

#### Scenario: コンテキスト注入
- **WHEN** `--context "テキスト"` が指定される
- **THEN** スクリプト内で `printf '%q'` によるクォーティングを行い `--append-system-prompt` 引数として cld に渡さなければならない（MUST）

#### Scenario: クロスリポジトリ対応
- **WHEN** `--repo-owner OWNER --repo-name NAME` が指定される
- **THEN** `REPO_OWNER` と `REPO_NAME` を環境変数として Worker に渡さなければならない（SHALL）

#### Scenario: クロスリポジトリ repo-path
- **WHEN** `--repo-path /path/to/external` が指定される
- **THEN** そのパスを EFFECTIVE_PROJECT_DIR として使用しなければならない（SHALL）。パスが存在しない場合は failed を記録して終了

#### Scenario: クラッシュ検知フック設定
- **WHEN** tmux window が正常に作成される
- **THEN** `remain-on-exit on` と `pane-died` フックを設定し、crash-detect.sh を呼び出す構成にしなければならない（MUST）

#### Scenario: SCRIPTS_ROOT 自動解決
- **WHEN** スクリプトが任意のディレクトリから呼び出される
- **THEN** `$(cd "$(dirname "$0")" && pwd)` で自身のディレクトリを SCRIPTS_ROOT として解決しなければならない（SHALL）

### Requirement: 終了コード体系

スクリプトは以下の終了コード体系に従わなければならない（MUST）。

#### Scenario: 正常終了
- **WHEN** Worker 起動が成功
- **THEN** 終了コード 0

#### Scenario: バリデーションエラー
- **WHEN** 引数バリデーションに失敗
- **THEN** 終了コード 1、state-write で failed を記録

#### Scenario: 外部コマンド不在
- **WHEN** cld が見つからない
- **THEN** 終了コード 2、state-write で failed を記録

## MODIFIED Requirements

### Requirement: autopilot-launch.md 簡素化

autopilot-launch.md は Step 4（コンテキスト注入テキスト構築）のみを LLM が担当し、残りは `bash $SCRIPTS_ROOT/autopilot-launch.sh` 呼び出しに委譲しなければならない（SHALL）。

#### Scenario: コンテキスト構築と委譲
- **WHEN** autopilot-phase-execute から autopilot-launch が呼び出される
- **THEN** LLM は CROSS_ISSUE_WARNINGS と PHASE_INSIGHTS から CONTEXT_TEXT を構築し、`--context` フラグでスクリプトに渡す

#### Scenario: 前提変数の維持
- **WHEN** 既存の呼び出し元（autopilot-phase-execute）が前提変数を設定
- **THEN** autopilot-launch.md は同じ前提変数インターフェースを維持しなければならない（MUST）

### Requirement: deps.yaml 更新

deps.yaml の autopilot-launch エントリに `script: autopilot-launch` を追加しなければならない（MUST）。

#### Scenario: calls 定義の更新
- **WHEN** deps.yaml が更新される
- **THEN** autopilot-launch の calls に script 参照が含まれる
- **THEN** `loom check` が PASS する
