## ADDED Requirements

### Requirement: autopilot-summary コマンド

全 Phase 完了後に結果集計、レポート出力、doobidoo 保存、session-archive.sh でアーカイブを行わなければならない（MUST）。マーカーファイルを参照せず state-read.sh で全 Issue 状態を取得しなければならない（MUST）。

COMMAND.md を `commands/autopilot-summary.md` に配置する（MUST）。

入力: PLAN_FILE, SESSION_ID, SESSION_STATE_FILE, PHASE_COUNT。
処理:
1. plan.yaml から ALL_ISSUES を構築（全 Phase の Issue 番号を抽出）
2. 各 Issue について state-read で status/pr_number/failure を集計
3. session-audit を --since $ELAPSED_HOURS で自動実行（失敗時は警告のみ）
4. サマリーレポートを出力（done/fail/skip 件数、パターン、retrospective、self-improve、監査結果）
5. doobidoo memory_store で保存（type: session-completion-report）
6. session-archive.sh でセッションをアーカイブ
7. notify-send + pw-play で通知

ALL_ISSUES は plan.yaml から正しく構築しなければならない（MUST）。未定義変数を使用してはならない（MUST）。

#### Scenario: 全 Issue 成功時のサマリー
- **WHEN** 全 Issue が done
- **THEN** 成功件数と各 PR 番号を含むサマリーを出力し、notify-send で完了通知する

#### Scenario: 失敗含むサマリー
- **WHEN** 一部 Issue が failed
- **THEN** 失敗件数と reason を含むサマリーを出力し、notify-send で失敗通知する

#### Scenario: session-audit 失敗時
- **WHEN** session-audit の実行が失敗する
- **THEN** 「session-audit: 実行失敗（スキップ）」をサマリーに含め、ワークフローは停止しない

#### Scenario: セッションアーカイブ
- **WHEN** サマリー出力完了後
- **THEN** session-archive.sh が実行され .autopilot/archive/ にセッションデータが移動される

### Requirement: session-audit コマンド

セッション JSONL の事後分析で 5 カテゴリのワークフロー信頼性問題を検出し self-improve Issue を起票しなければならない（SHALL）。

COMMAND.md を `commands/session-audit.md` に配置する（MUST）。

入力: COUNT（デフォルト 5）または --since PERIOD。
処理:
1. プロジェクトの JSONL ディレクトリを特定（worktree 対応、bare repo main フォールバック）
2. 対象セッション JSONL を取得
3. session-audit.sh で監査サマリー抽出
4. Haiku Agent で 5 カテゴリ分析（script-fragility, silent-failure, ai-compensation, retry-loop, loom-inline-logic）
5. confidence >= 70 のもののみ self-improve Issue 起票（重複排除チェック付き）

Haiku 以外のモデルで分析してはならない（MUST）。confidence < 70 の検出で Issue 起票してはならない（MUST）。

#### Scenario: 直近 5 セッション分析
- **WHEN** 引数なしで実行
- **THEN** 最新 5 セッションの JSONL を分析し、検出結果テーブルを出力する

#### Scenario: 期間指定分析
- **WHEN** --since 3d で実行
- **THEN** 直近 3 日間のセッション JSONL を分析する

#### Scenario: confidence 閾値フィルタリング
- **WHEN** 分析で confidence 65 の検出がある
- **THEN** 低 confidence としてログ出力のみ。Issue 起票はしない

#### Scenario: 重複排除
- **WHEN** 同一パターンの self-improve Issue が既に open
- **THEN** 重複としてスキップする

## MODIFIED Requirements

### Requirement: co-autopilot SKILL.md の calls 更新

co-autopilot の calls セクションに 11 コマンドを追加しなければならない（MUST）。マーカーファイルおよび DEV_AUTOPILOT_SESSION への参照を全削除しなければならない（MUST）。

#### Scenario: calls に全 11 コマンドが記載
- **WHEN** co-autopilot SKILL.md を確認
- **THEN** autopilot-init, autopilot-launch, autopilot-poll, autopilot-phase-execute, autopilot-phase-postprocess, autopilot-collect, autopilot-retrospective, autopilot-patterns, autopilot-cross-issue, autopilot-summary, session-audit の全 11 コマンドが calls に含まれる

#### Scenario: マーカーファイル参照の完全除去
- **WHEN** co-autopilot SKILL.md 内で grep "marker\|MARKER_DIR\|\.done\|\.fail\|\.merge-ready"
- **THEN** 0 件ヒットする

### Requirement: deps.yaml への 11 コマンド追加

deps.yaml の commands セクションに 11 コマンドを追加し、co-autopilot の calls を更新しなければならない（MUST）。loom validate が pass しなければならない（MUST）。

#### Scenario: deps.yaml に全 11 コマンドが定義
- **WHEN** deps.yaml の commands セクションを確認
- **THEN** 11 コマンドが type: atomic で定義されている

#### Scenario: co-autopilot の calls 更新
- **WHEN** deps.yaml の co-autopilot スキル定義を確認
- **THEN** calls に 11 コマンドが全て含まれている（既存の self-improve 系 4 コマンドに加えて）

#### Scenario: loom validate pass
- **WHEN** `loom validate` を実行
- **THEN** エラーなしで pass する
