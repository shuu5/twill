## MODIFIED Requirements

### Requirement: merge-gate controller 行数削減

`merge-gate.md` は 120 行以下でなければならない（SHALL）。インライン bash スクリプトをスクリプトファイルへ抽出することで行数を削減する。

#### Scenario: 行数削減後の検証
- **WHEN** `merge-gate.md` の変更後に `wc -l` を実行する
- **THEN** 行数が 120 以下であること

#### Scenario: 動作等価性
- **WHEN** `merge-gate.md` が参照する各スクリプトを実行する
- **THEN** 抽出前と同じロジックが実行され、同じ結果を返すこと

## ADDED Requirements

### Requirement: PR 存在確認スクリプト抽出

`merge-gate-check-pr.sh` を `plugins/twl/scripts/` 配下に作成し、PR 存在確認ロジックを保持しなければならない（SHALL）。

#### Scenario: PR 存在確認スクリプト実行
- **WHEN** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-pr.sh"` が呼び出される
- **THEN** PR が存在しない場合は exit 1 を返し、REJECT checkpoint を書き込むこと

#### Scenario: merge-gate.md からの参照
- **WHEN** `merge-gate.md` の PR 存在確認セクションを参照する
- **THEN** インライン bash の代わりに `bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-pr.sh"` の 1 行参照になっていること

### Requirement: 動的レビュアー構築スクリプト抽出

`merge-gate-build-manifest.sh` を `plugins/twl/scripts/` 配下に作成し、specialist マニフェスト構築ロジックを保持しなければならない（SHALL）。

#### Scenario: マニフェスト構築スクリプト実行
- **WHEN** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-build-manifest.sh"` が呼び出される
- **THEN** `MANIFEST_FILE` と `CONTEXT_ID` と `SPAWNED_FILE` が設定され、specialists が書き込まれること

### Requirement: spawn 完了確認スクリプト抽出

`merge-gate-check-spawn.sh` を `plugins/twl/scripts/` 配下に作成し、全 specialist の spawn 完了チェックロジックを保持しなければならない（SHALL）。

#### Scenario: spawn 確認スクリプト実行
- **WHEN** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-spawn.sh"` が呼び出される（`MANIFEST_FILE` と `SPAWNED_FILE` が環境変数で渡される）
- **THEN** 未 spawn の specialist がある場合は ERROR を出力してスクリプトを終了し、全員完了の場合は成功メッセージを出力すること

### Requirement: Cross-PR AC 検証スクリプト抽出

`merge-gate-cross-pr-ac.sh` を `plugins/twl/scripts/` 配下に作成し、Cross-PR AC 検証ロジックを保持しなければならない（SHALL）。

#### Scenario: Cross-PR AC 検証スクリプト実行
- **WHEN** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-cross-pr-ac.sh"` が呼び出される
- **THEN** `implementation_pr` が設定されている場合にマージコミットを取得し checkpoint へ記録すること

### Requirement: checkpoint 統合スクリプト抽出

`merge-gate-checkpoint-merge.sh` を `plugins/twl/scripts/` 配下に作成し、複数 checkpoint の統合ロジックを保持しなければならない（SHALL）。

#### Scenario: checkpoint 統合スクリプト実行
- **WHEN** `COMBINED_FINDINGS=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-checkpoint-merge.sh" "$FINDINGS")` が呼び出される
- **THEN** ac-verify, phase-review の findings を統合した JSON を stdout に出力すること

### Requirement: phase-review 必須チェックスクリプト抽出

`merge-gate-check-phase-review.sh` を `plugins/twl/scripts/` 配下に作成し、phase-review checkpoint の存在確認ロジックを保持しなければならない（SHALL）。

#### Scenario: phase-review チェックスクリプト実行
- **WHEN** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-phase-review.sh"` が呼び出される（`PHASE_REVIEW_STATUS`, `ISSUE_NUM` が環境変数で渡される）
- **THEN** phase-review が不在かつ `scope/direct` / `quick` ラベルがない場合は REJECT を返し、ラベルがある場合はスキップすること
