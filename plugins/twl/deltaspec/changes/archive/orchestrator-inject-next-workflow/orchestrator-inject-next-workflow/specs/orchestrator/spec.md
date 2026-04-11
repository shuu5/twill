## ADDED Requirements

### Requirement: workflow_done フィールドの読み取り

polling ループの `status=running` ブランチ内で、`workflow_done` フィールドを追加読み取りしなければならない（SHALL）。読み取りはクラッシュ検知の後、`check_and_nudge()` の前に配置する。

#### Scenario: workflow_done が設定されている場合
- **WHEN** `status=running` のポーリング中に `workflow_done` フィールドが非空の値を持つ
- **THEN** `inject_next_workflow()` を呼び出し、成功時は `check_and_nudge()` をスキップする

#### Scenario: workflow_done が未設定の場合
- **WHEN** `status=running` のポーリング中に `workflow_done` フィールドが空または未設定
- **THEN** 既存の `check_and_nudge()` フローを継続する（動作変更なし）

---

### Requirement: inject_next_workflow() 関数の実装

`inject_next_workflow()` 関数を実装しなければならない（MUST）。引数として `issue`（Issue 番号）と `window_name`（tmux ウィンドウ名）を受け取る。

#### Scenario: 正常な inject フロー
- **WHEN** `inject_next_workflow()` が呼ばれ、`resolve_next_workflow` が非 `pr-merge` の workflow skill を返す
- **THEN** tmux pane の入力待ち確認 → `tmux send-keys` で workflow skill を inject → `workflow_done` をクリア → inject 履歴を state に記録する

#### Scenario: resolve_next_workflow が pr-merge を返した場合
- **WHEN** `inject_next_workflow()` 内で `resolve_next_workflow` が `pr-merge` を返す
- **THEN** inject は行わず `workflow_done` をクリアするのみ（Worker が `status=merge-ready` を書き込む自然な遷移に委譲）

#### Scenario: resolve_next_workflow が失敗した場合
- **WHEN** `inject_next_workflow()` 内で `resolve_next_workflow` がエラーを返す
- **THEN** WARNING ログを出力し、10秒後に再チェックする（inject 失敗として扱う）

---

### Requirement: tmux pane 入力待ち確認

inject 前に `tmux capture-pane` で入力待ち状態を確認しなければならない（SHALL）。最大3回、2秒間隔でリトライする。

#### Scenario: プロンプト検出成功
- **WHEN** `tmux capture-pane -p -t "$window_name"` の出力末尾に `> ` または `$ ` が存在する
- **THEN** `tmux send-keys` で inject を実行する

#### Scenario: 3回リトライ後もプロンプト未検出
- **WHEN** 3回のリトライ（合計6秒待機）後もプロンプトが検出されない
- **THEN** `[orchestrator] WARNING: inject タイムアウト — 10秒後に再チェック` ログを出力し、戻り値 1 で終了する

---

### Requirement: inject 履歴の state 記録

inject 成功後に `workflow_injected` と `injected_at` を state に書き込まなければならない（MUST）。

#### Scenario: inject 成功後の履歴記録
- **WHEN** `tmux send-keys` による inject が成功する
- **THEN** `state write --role pilot --set "workflow_injected=<skill_name>" --set "injected_at=<timestamp>"` を実行する

---

### Requirement: inject 成功後の NUDGE_COUNTS リセット

inject 成功後に該当 Issue の `NUDGE_COUNTS` をゼロにリセットしなければならない（SHALL）。

#### Scenario: inject 後の stall カウンターリセット
- **WHEN** `inject_next_workflow()` が成功する
- **THEN** `NUDGE_COUNTS[$issue]=0` を設定する

---

### Requirement: inject イベントのログ出力

inject 関連イベントは `[orchestrator]` プレフィックス形式でログを出力しなければならない（MUST）。

#### Scenario: inject 実行ログ
- **WHEN** inject が実行される（成功・失敗問わず）
- **THEN** `[orchestrator] Issue #${issue}: inject_next_workflow — <skill_name>` 形式でログを出力する

## MODIFIED Requirements

### Requirement: check_and_nudge() の条件付きスキップ

`status=running` ブランチで `inject_next_workflow()` が成功した場合、`check_and_nudge()` をスキップしなければならない（SHALL）。

#### Scenario: inject 成功後の nudge スキップ
- **WHEN** polling ループ内で `inject_next_workflow()` が戻り値 0 で完了する
- **THEN** `check_and_nudge()` を呼ばずに次のポーリングサイクルに進む
