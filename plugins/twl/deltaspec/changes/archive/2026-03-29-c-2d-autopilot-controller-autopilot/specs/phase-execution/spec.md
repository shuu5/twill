## ADDED Requirements

### Requirement: autopilot-phase-execute コマンド

1 Phase 分の Issue ループ処理を実行する。state-read.sh / state-write.sh で状態判定を行い、マーカーファイルを参照してはならない（MUST）。

COMMAND.md を `commands/autopilot-phase-execute.md` に配置する（MUST）。

入力: P（Phase 番号）, SESSION_STATE_FILE, MODE（sequential/parallel）, PLAN_FILE, SESSION_ID, PROJECT_DIR, REPO_MODE, CROSS_ISSUE_WARNINGS, PHASE_INSIGHTS。
処理:
1. Phase 内 Issue リストを plan.yaml から取得
2. 各 Issue について state-read で状態確認（done → スキップ、skip 判定）
3. autopilot-launch → autopilot-poll → merge-gate のチェーンを実行
4. 結果を state-write で記録

parallel モードでは MAX_PARALLEL（デフォルト 4）個ずつバッチ分割しなければならない（SHALL）。
merge-gate リジェクト → 再実行は 1 Issue 最大 1 回としなければならない（MUST）（不変条件 E）。
merge-gate 失敗時に rebase を試みてはならない（MUST）（不変条件 F）。

#### Scenario: sequential モードでの正常実行
- **WHEN** MODE=sequential で 2 Issue がある Phase を実行
- **THEN** Issue を順次 launch → poll → merge-gate し、各 Issue の完了後に次の Issue を開始する

#### Scenario: parallel モードでのバッチ実行
- **WHEN** MODE=parallel, MAX_PARALLEL=2 で 5 Issue がある Phase
- **THEN** 2, 2, 1 のバッチに分割し、各バッチ内は並列 launch → phase ポーリング → merge-gate を実行する

#### Scenario: 依存先 fail 時の skip 伝播
- **WHEN** Phase 内の Issue A が fail し、Issue B が A に依存
- **THEN** Issue B は state-write で status=failed, message="dependency failed" として記録される（不変条件 D）

#### Scenario: done 状態の Issue スキップ（再開時）
- **WHEN** state-read で Issue の status が done
- **THEN** その Issue をスキップし、次の Issue に進む

### Requirement: autopilot-phase-postprocess コマンド

Phase 後処理チェーン（collect → retrospective → patterns → cross-issue）を統合実行しなければならない（MUST）。後処理の実行順序を変更してはならない（MUST）。

COMMAND.md を `commands/autopilot-phase-postprocess.md` に配置する（MUST）。

入力: P（Phase 番号）, SESSION_STATE_FILE, PLAN_FILE, SESSION_ID, PHASE_COUNT。
出力: PHASE_INSIGHTS, CROSS_ISSUE_WARNINGS。
処理:
1. Phase 内 Issue リストを plan.yaml から取得
2. autopilot-collect を実行（done Issue の変更ファイル収集）
3. autopilot-retrospective を実行（PHASE_INSIGHTS 生成）
4. autopilot-patterns を実行（パターン検出 + self-improve Issue 起票）
5. P < PHASE_COUNT の場合のみ autopilot-cross-issue を実行

最終 Phase では cross-issue を実行してはならない（MUST）。

#### Scenario: 中間 Phase の後処理
- **WHEN** P=1, PHASE_COUNT=3
- **THEN** collect → retrospective → patterns → cross-issue の順に全 4 ステップを実行する

#### Scenario: 最終 Phase の後処理
- **WHEN** P=3, PHASE_COUNT=3
- **THEN** collect → retrospective → patterns の 3 ステップのみ実行し、cross-issue はスキップする
