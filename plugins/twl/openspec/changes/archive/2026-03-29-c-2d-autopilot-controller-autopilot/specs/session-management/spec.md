## ADDED Requirements

### Requirement: autopilot-init コマンド

.autopilot/ ディレクトリ初期化と session.json 作成を行う co-autopilot の最初のステップ。autopilot-init.sh と session-create.sh のラッパーとして機能しなければならない（SHALL）。

COMMAND.md を `commands/autopilot-init.md` に配置する（MUST）。

入力: plan.yaml のパス（PLAN_FILE）。
処理:
1. `autopilot-init.sh` を実行し .autopilot/ を初期化
2. plan.yaml から phase_count を抽出
3. `session-create.sh --plan-path $PLAN_FILE --phase-count $PHASE_COUNT` で session.json 作成
4. SESSION_ID, PHASE_COUNT, SESSION_STATE_FILE を eval 用に出力

旧マーカーファイル（/tmp/dev-autopilot/）の残存を検出した場合は警告を出力しなければならない（MUST）。

#### Scenario: 正常初期化
- **WHEN** .autopilot/ が未存在で plan.yaml が有効
- **THEN** .autopilot/ が作成され session.json が生成される。SESSION_ID が出力される

#### Scenario: 既存セッション検出
- **WHEN** session.json が既に存在（24h 以内）
- **THEN** autopilot-init.sh がエラーを返し、排他制御メッセージが表示される

#### Scenario: 旧マーカー残存警告
- **WHEN** /tmp/dev-autopilot/ にマーカーファイルが存在
- **THEN** 「旧マーカーファイルが残存しています」警告を出力する。初期化自体は続行する

### Requirement: autopilot-launch コマンド

tmux window を作成し Worker を起動する。DEV_AUTOPILOT_SESSION 環境変数を使用せず、state-write.sh で issue-{N}.json を初期化しなければならない（MUST）。

COMMAND.md を `commands/autopilot-launch.md` に配置する（MUST）。

入力: ISSUE（番号）, PROJECT_DIR, SESSION_STATE_FILE, CROSS_ISSUE_WARNINGS, PHASE_INSIGHTS。
処理:
1. cld パス解決
2. `state-write.sh --type issue --issue $ISSUE --role worker --init` で issue-{N}.json を running で初期化
3. cross-issue 警告と retrospective 知見の --append-system-prompt 構築
4. `tmux new-window -n "ap-#${ISSUE}" -c "$PROJECT_DIR"` で Worker 起動（DEV_AUTOPILOT_SESSION なし）
5. pane-died フックで crash-detect.sh を呼び出す設定

Worker 起動プロンプトは `/twl:workflow-setup #${ISSUE}` を使用しなければならない（SHALL）。

#### Scenario: 正常起動
- **WHEN** cld が PATH に存在し Issue 番号が有効
- **THEN** issue-{N}.json が status=running で作成され、tmux window "ap-#N" が起動される

#### Scenario: cross-issue 警告付き起動
- **WHEN** CROSS_ISSUE_WARNINGS に該当 Issue の警告がある（high confidence）
- **THEN** --append-system-prompt にサニタイズ済み警告テキストが注入される

#### Scenario: cld 未検出
- **WHEN** cld が PATH に存在しない
- **THEN** state-write で status=failed に遷移し、failure.message に "cld_not_found" を記録する

### Requirement: autopilot-poll コマンド

state-read.sh を使用して Issue 状態をポーリングし、crash-detect.sh でクラッシュ検知を行わなければならない（MUST）。マーカーファイルを参照してはならない（MUST）。

COMMAND.md を `commands/autopilot-poll.md` に配置する（MUST）。

入力: ISSUE（single モード）/ ISSUES（phase モード）, POLL_MODE, SESSION_STATE_FILE。
処理:
1. 10 秒間隔で state-read.sh --type issue --issue $ISSUE --field status を実行
2. status が done/failed/merge-ready のいずれかなら検知完了
3. status が running の場合、crash-detect.sh --issue $ISSUE --window "ap-#${ISSUE}" でペイン死亡チェック
4. MAX_POLL=360（60 分タイムアウト）で status=failed + reason=poll_timeout に遷移

phase モードでは全 Issue を一括ポーリングし、merge-ready 検知時に controller に制御を返さなければならない（SHALL）。

#### Scenario: 正常完了検知（single）
- **WHEN** Worker が merge-ready に遷移
- **THEN** "Issue #N: merge-ready" を出力し、ポーリングを終了する

#### Scenario: クラッシュ検知
- **WHEN** tmux ペインが消失し status が running のまま
- **THEN** crash-detect.sh が status=failed に遷移させ、failure.message に "Worker crash detected" を記録する

#### Scenario: タイムアウト
- **WHEN** 360 回のポーリング（60 分）で状態が変化しない
- **THEN** state-write で status=failed, reason=poll_timeout に遷移する

#### Scenario: phase モードの一括ポーリング
- **WHEN** POLL_MODE=phase で 3 Issue を監視
- **THEN** 全 Issue が done/failed/merge-ready になるまでポーリングを継続する。個別の merge-ready は即座に報告する
