## ADDED Requirements

### Requirement: session.json によるセッション排他制御

autopilot セッション開始時に session.json の存在を確認し、既存セッションとの並行実行を防止しなければならない（SHALL）。

#### Scenario: 新規セッション開始
- **WHEN** `.autopilot/session.json` が存在しない状態で autopilot セッションが開始される
- **THEN** session.json が作成され、session_id, plan_path, current_phase=1, phase_count が設定される

#### Scenario: 既存セッション検出による拒否
- **WHEN** `.autopilot/session.json` が既に存在し、started_at が 24 時間以内である
- **THEN** 「既存セッションが実行中です」のエラーメッセージとともに exit 1 で終了する

#### Scenario: stale セッションの検出
- **WHEN** `.autopilot/session.json` が存在し、started_at が 24 時間以上経過している
- **THEN** 「stale セッションが検出されました。削除しますか？」の警告を表示し、ユーザー確認を求める

### Requirement: cross-issue 警告の session.json 格納

同一 Phase 内で変更ファイルが重複する Issue 間の警告を session.json に構造化保存しなければならない（MUST）。

#### Scenario: ファイル重複の検出と記録
- **WHEN** Phase 内の Issue #42 と Issue #43 が同一ファイル `deps.yaml` を変更している
- **THEN** session.json の `cross_issue_warnings` に `{ issue: 42, target_issue: 43, file: "deps.yaml", reason: "同一ファイル変更" }` が追加される

#### Scenario: 重複なしの場合
- **WHEN** Phase 内の全 Issue の変更ファイルに重複がない
- **THEN** session.json の `cross_issue_warnings` は空配列のまま変更されない

## MODIFIED Requirements

### Requirement: ポーリング機構の簡素化

旧プラグインのマーカーファイル監視を廃止し、`state-read.sh` による status フィールドの定期的読み取りに変更しなければならない（SHALL）。

#### Scenario: 通常のポーリングサイクル
- **WHEN** ポーリングが開始され、issue-{N}.json の status が `running` である
- **THEN** 10 秒間隔で `state-read.sh --type issue --issue N --field status` を繰り返し実行する

#### Scenario: status 変化の検知
- **WHEN** ポーリング中に issue-{N}.json の status が `running` から `merge-ready` に変化する
- **THEN** ポーリングを停止し、merge-gate フェーズに遷移する

#### Scenario: crash 検知との統合
- **WHEN** ポーリング中に tmux ペインが消失し、status が `running` のままである
- **THEN** crash として検知し、status を `failed` に遷移する（不変条件 G）

### Requirement: .autopilot ディレクトリの初期化と後始末

autopilot セッションのライフサイクルに合わせて `.autopilot/` ディレクトリを管理しなければならない（MUST）。

#### Scenario: セッション開始時の初期化
- **WHEN** autopilot セッションが開始される
- **THEN** `.autopilot/` ディレクトリと `.autopilot/issues/` サブディレクトリが作成される（既存の場合はスキップ）

#### Scenario: セッション完了後のアーカイブ
- **WHEN** autopilot セッションが全 Phase 完了で正常終了する
- **THEN** session.json と全 issue-{N}.json は `.autopilot/archive/<session_id>/` に移動される

#### Scenario: .gitignore への追加
- **WHEN** `.autopilot/` ディレクトリが初めて作成される
- **THEN** `.gitignore` に `.autopilot/` エントリが追加される（既にある場合はスキップ）
