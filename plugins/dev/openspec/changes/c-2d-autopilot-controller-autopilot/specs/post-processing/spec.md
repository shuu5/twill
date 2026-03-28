## ADDED Requirements

### Requirement: autopilot-collect コマンド

Phase 完了後に done 状態の Issue の PR 差分から変更ファイルリストを収集し session.json に保存しなければならない（MUST）。マーカーファイル (.done) を参照せず state-read.sh で状態判定しなければならない（MUST）。

COMMAND.md を `commands/autopilot-collect/COMMAND.md` に配置する（MUST）。

入力: ISSUES（Phase 内 Issue リスト）, SESSION_STATE_FILE。
処理:
1. 各 Issue について state-read --type issue --issue $ISSUE --field status で状態確認
2. status=done の Issue について state-read --field pr_number で PR 番号取得
3. `gh pr diff $PR_NUMBER --name-only` で変更ファイルリスト取得
4. state-write で completed_issues[$ISSUE].files に保存

#### Scenario: done Issue の変更ファイル収集
- **WHEN** Issue #19 が status=done, pr_number=42
- **THEN** PR #42 の差分ファイルリストを取得し session.json の completed_issues に記録する

#### Scenario: PR 差分取得失敗
- **WHEN** gh pr diff がエラーを返す
- **THEN** 警告を出力しスキップする。ワークフロー全体は停止しない

#### Scenario: failed Issue のスキップ
- **WHEN** Issue #20 が status=failed
- **THEN** 変更ファイル収集をスキップする

### Requirement: autopilot-retrospective コマンド

Phase 振り返りを実行し成功/失敗パターンを分析して次 Phase 向け知見を生成しなければならない（SHALL）。状態ファイルから情報を取得し、doobidoo に保存しなければならない（MUST）。

COMMAND.md を `commands/autopilot-retrospective/COMMAND.md` に配置する（MUST）。

入力: P, ISSUES, SESSION_ID, SESSION_STATE_FILE, PHASE_COUNT。
出力: PHASE_INSIGHTS。
処理:
1. state-read で各 Issue の状態と詳細を集約
2. LLM 推論で成功/失敗パターンを分析
3. 最終 Phase でなければ次 Phase 向け知見を PHASE_INSIGHTS として生成
4. doobidoo memory_store で保存（type: phase-retrospective）
5. session.json の retrospectives[] に追記

#### Scenario: 成功 Phase の振り返り
- **WHEN** Phase 内の全 Issue が done
- **THEN** 成功パターンを分析し PHASE_INSIGHTS を生成。doobidoo に保存する

#### Scenario: 失敗含む Phase の振り返り
- **WHEN** Phase 内に failed Issue がある
- **THEN** 失敗原因を分析し回避策を PHASE_INSIGHTS に含める

#### Scenario: 最終 Phase の振り返り
- **WHEN** P == PHASE_COUNT
- **THEN** 振り返りは実行するが PHASE_INSIGHTS は空文字列とする

### Requirement: autopilot-patterns コマンド

セッション状態からの繰り返しパターン検出と self-improve Issue 起票判定を行わなければならない（MUST）。マーカーファイル (.fail) を参照せず state-read.sh で failure 情報を取得しなければならない（MUST）。

COMMAND.md を `commands/autopilot-patterns/COMMAND.md` に配置する（MUST）。

入力: SESSION_ID, SESSION_STATE_FILE。
処理:
1. doobidoo memory_search で merge-gate decision 記録を取得しグルーピング
2. state-read で failed Issue の failure 情報を取得しグルーピング
3. count >= 2 のパターンを抽出
4. confidence >= 80 かつ count >= 2 で self-improve Issue 起票（PATTERN_TITLE サニタイズ必須）
5. session.json の patterns と self_improve_issues に追記

PATTERN_TITLE はシェル特殊文字を除去してサニタイズしなければならない（MUST）。

#### Scenario: 繰り返し失敗パターン検出
- **WHEN** 2 Issue が同一 reason（例: test_failure）で failed
- **THEN** failure パターンとして検出し doobidoo に記録する

#### Scenario: self-improve Issue 起票
- **WHEN** パターンの confidence >= 80 かつ count >= 2
- **THEN** "[Self-Improve] サニタイズ済みタイトル" で Issue を起票し session.json に記録する

#### Scenario: 低 confidence パターン
- **WHEN** パターンの confidence < 80
- **THEN** doobidoo キャッシュにのみ記録し Issue 起票しない

### Requirement: autopilot-cross-issue コマンド

完了 Issue の変更ファイルと後続 Phase の Issue スコープを比較し競合リスクを検出しなければならない（SHALL）。session-add-warning.sh 経由で session.json に追記しなければならない（MUST）。

COMMAND.md を `commands/autopilot-cross-issue/COMMAND.md` に配置する（MUST）。

入力: SESSION_STATE_FILE, NEXT_PHASE_ISSUES。
出力: CROSS_ISSUE_WARNINGS。
処理:
1. state-read で completed_issues の変更ファイルリスト取得
2. 後続 Issue の body を `gh issue view` で取得
3. LLM 推論でファイル競合リスクを検出（high/medium/low confidence）
4. session-add-warning.sh で session.json に警告追記
5. CROSS_ISSUE_WARNINGS 連想配列を構築

high confidence 警告のみ Worker 起動プロンプトに注入しなければならない（SHALL）。

#### Scenario: ファイル名完全一致の競合検出
- **WHEN** Phase 1 で deps.yaml を変更し、Phase 2 の Issue が deps.yaml を参照
- **THEN** confidence: high として検出し session.json に警告を追記する

#### Scenario: 競合なし
- **WHEN** 変更ファイルと後続 Issue のスコープに重複がない
- **THEN** CROSS_ISSUE_WARNINGS は空で、session.json に警告は追記されない
