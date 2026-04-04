## ADDED Requirements

### Requirement: merge-gate-init スクリプト移植

merge-gate-init.sh を新リポジトリに移植し、MARKER_DIR / マーカーファイル参照を state-read.sh 経由に置換しなければならない（SHALL）。PR番号・ブランチ名は issue-{N}.json から取得し、GATE_TYPE 判定ロジックは維持する。

#### Scenario: 正常な merge-gate 初期化
- **WHEN** Issue N の status が `merge-ready` で、issue-{N}.json に pr と branch が記録されている
- **THEN** eval 可能な変数定義（PR_NUMBER, BRANCH, RETRY_COUNT, PR_DIFF_FILE, PR_FILES, GATE_TYPE, PLUGIN_NAMES）を stdout に出力する

#### Scenario: merge-ready 状態でない Issue
- **WHEN** Issue N の status が `merge-ready` でない
- **THEN** エラーメッセージを stderr に出力し exit 1 で終了する

#### Scenario: GATE_TYPE の自動判定
- **WHEN** PR差分のファイルパスに `plugins/` 配下の変更が含まれ、対応する deps.yaml が存在する
- **THEN** GATE_TYPE=plugin を出力する

### Requirement: merge-gate-execute スクリプト移植

merge-gate-execute.sh を新リポジトリに移植し、マーカーファイル操作を state-write.sh による状態遷移に置換しなければならない（MUST）。3つのモード（merge, --reject, --reject-final）を維持する。

#### Scenario: マージ成功時の状態遷移
- **WHEN** `gh pr merge` が成功する
- **THEN** state-write.sh で status=done, merged_at, branch を記録し、worktree/ブランチのクリーンアップを実行する

#### Scenario: リジェクト時の状態遷移
- **WHEN** --reject モードで実行される
- **THEN** state-write.sh で status=failed, reason=merge_gate_rejected, retry_count=1 を記録する

#### Scenario: 確定失敗時の状態遷移
- **WHEN** --reject-final モードで実行される
- **THEN** state-write.sh で status=failed, reason=merge_gate_rejected_final, retry_count=2 を記録する

### Requirement: merge-gate-issues スクリプト移植

merge-gate-issues.sh を新リポジトリに移植しなければならない（SHALL）。tech-debt Issue 自動起票のロジックは変更最小限とする。

#### Scenario: tech-debt Issue の自動起票
- **WHEN** merge-gate レビューで tech-debt finding が検出される
- **THEN** GitHub Issue が自動作成され、tech-debt ラベルが付与される
