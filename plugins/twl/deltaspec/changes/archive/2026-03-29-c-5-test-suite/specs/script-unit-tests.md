## ADDED Requirements

### Requirement: state-write 単体テスト

state-write.sh の全操作パス（init、フィールド更新、遷移バリデーション、ロール制御）をテストしなければならない（SHALL）。

#### Scenario: issue 状態初期化
- **WHEN** `state-write.sh --type issue --issue 1 --role pilot --init` を実行する
- **THEN** `.autopilot/issues/issue-1.json` が作成され `status=running` が設定される

#### Scenario: 不正な状態遷移の拒否
- **WHEN** status=done の issue に対して `--set status=running` を実行する
- **THEN** 終了コード 1 で遷移拒否メッセージが出力される

#### Scenario: retry 制限
- **WHEN** retry_count=1 かつ status=failed の issue に `--set status=running` を実行する
- **THEN** 終了コード 1 でリトライ上限メッセージが出力される

### Requirement: state-read 単体テスト

state-read.sh の全クエリパターン（単一フィールド、全フィールド、存在しないファイル）をテストしなければならない（SHALL）。

#### Scenario: 単一フィールド読み取り
- **WHEN** issue-1.json が存在し `state-read.sh --type issue --issue 1 --get status` を実行する
- **THEN** status の値が stdout に出力される

#### Scenario: 存在しないファイル
- **WHEN** issue-99.json が存在せず `state-read.sh --type issue --issue 99 --get status` を実行する
- **THEN** 終了コード 1 でエラーメッセージが出力される

### Requirement: crash-detect 単体テスト

crash-detect.sh のクラッシュ検知ロジック（ペイン存在/不在、非 running 状態のスキップ）をテストしなければならない（MUST）。

#### Scenario: ペイン不在で crash 検知
- **WHEN** tmux ペインが存在せず status=running の issue に対して実行する
- **THEN** 終了コード 2 で status が failed に遷移する

#### Scenario: 非 running 状態のスキップ
- **WHEN** status=done の issue に対して実行する
- **THEN** 終了コード 0 でチェック不要として正常終了する

### Requirement: autopilot-plan 単体テスト

autopilot-plan.sh の依存グラフ解決・Phase 分割ロジックをテストしなければならない（SHALL）。

#### Scenario: 線形依存の Phase 分割
- **WHEN** A→B→C の依存グラフで実行する
- **THEN** Phase 1=[A], Phase 2=[B], Phase 3=[C] に分割される

#### Scenario: 並列可能な Issue の同一 Phase 配置
- **WHEN** A、B が独立し、C が A,B 両方に依存する場合
- **THEN** Phase 1=[A,B], Phase 2=[C] に分割される

### Requirement: autopilot-should-skip 単体テスト

autopilot-should-skip.sh の skip 判定ロジック（依存先 fail 伝播）をテストしなければならない（SHALL）。

#### Scenario: 依存先 failed で skip
- **WHEN** 依存先 issue の status=failed の場合
- **THEN** 終了コード 0 で skip=true が返される

#### Scenario: 依存先 done で続行
- **WHEN** 依存先 issue の status=done の場合
- **THEN** 終了コード 0 で skip=false が返される

### Requirement: session 管理スクリプト単体テスト

session-create.sh、session-archive.sh、session-add-warning.sh のセッションライフサイクルをテストしなければならない（MUST）。

#### Scenario: session.json 新規作成
- **WHEN** `session-create.sh` を .autopilot/ が存在する環境で実行する
- **THEN** `.autopilot/session.json` が作成され必須フィールドが含まれる

#### Scenario: warning 追加
- **WHEN** session.json が存在する状態で `session-add-warning.sh --message "test"` を実行する
- **THEN** session.json の warnings 配列にメッセージが追加される

### Requirement: worktree-create / worktree-delete 単体テスト

worktree-create.sh のブランチ名生成・バリデーション、worktree-delete.sh のロール制御をテストしなければならない（SHALL）。

#### Scenario: Issue 番号からブランチ名生成
- **WHEN** `worktree-create.sh #99` を実行する（gh を stub）
- **THEN** `feat/99-*` 形式のブランチ名が生成される

#### Scenario: worktree-delete の worker 拒否
- **WHEN** role=worker で `worktree-delete.sh` を実行する
- **THEN** 終了コード 1 で pilot 専任メッセージが出力される

### Requirement: merge-gate スクリプト単体テスト

merge-gate-init.sh、merge-gate-execute.sh、merge-gate-issues.sh の 3 段階フローをテストしなければならない（SHALL）。

#### Scenario: merge-gate-init の PR 情報取得
- **WHEN** gh を stub して PR 情報を返す状態で実行する
- **THEN** .autopilot/ に gate 情報ファイルが作成される

#### Scenario: merge-gate-execute の worker 拒否
- **WHEN** role=worker で merge-gate-execute.sh を実行する
- **THEN** 終了コード 1 でマージ拒否メッセージが出力される

### Requirement: ユーティリティスクリプト単体テスト

classify-failure.sh、parse-issue-ac.sh、specialist-output-parse.sh、tech-stack-detect.sh の入出力をテストしなければならない（MUST）。

#### Scenario: failure 分類
- **WHEN** テストエラーログを stdin で渡す
- **THEN** カテゴリ（test-failure, build-error 等）が stdout に出力される

#### Scenario: AC パース
- **WHEN** Issue body テキストを入力する
- **THEN** `- [ ]` 形式の AC 項目が抽出される
