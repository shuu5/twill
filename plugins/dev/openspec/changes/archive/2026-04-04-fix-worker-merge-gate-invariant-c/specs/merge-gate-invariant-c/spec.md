## MODIFIED Requirements

### Requirement: merge-gate.md PASS セクションから raw コマンドを除去

`commands/merge-gate.md` の PASS 時の状態遷移セクションは、raw `gh pr merge` コマンドおよび `state-write --role pilot` コマンドを含んではならない（SHALL NOT）。代わりに、Worker は `state-write --role worker --set status=merge-ready` で merge-ready 宣言して停止しなければならない（SHALL）。非 autopilot 時の Pilot フローは `merge-gate-execute.sh` 呼び出し案内として記載しなければならない（SHALL）。

#### Scenario: Worker が merge-gate PASS 時に merge-ready を宣言して停止する
- **WHEN** autopilot セッション中に merge-gate が PASS と判定した場合
- **THEN** Worker は `state-write --role worker --set status=merge-ready` を実行し、Pilot による merge を待機する旨のメッセージを出力して停止する

#### Scenario: merge-gate.md に raw merge コマンドが存在しない
- **WHEN** `commands/merge-gate.md` を grep で `gh pr merge` 検索した場合
- **THEN** 一致結果が 0 件である

#### Scenario: merge-gate.md に raw --role pilot state-write が存在しない（merge-ready 遷移を除く）
- **WHEN** `commands/merge-gate.md` を grep で `--role pilot` 検索した場合
- **THEN** PASS セクションに `--role pilot` の記載が存在しない

---

### Requirement: state-write.sh が Worker からの --role pilot 呼び出しを拒否する

`scripts/state-write.sh` は `--role pilot` かつ status フィールド更新が指定された場合、呼び出し元が autopilot Worker（tmux window 名 `ap-#N` パターン、または CWD が `worktrees/` 配下）であることを検出した際に、エラーを返して終了しなければならない（SHALL）。

#### Scenario: tmux window が Worker パターンの場合に --role pilot を拒否する
- **WHEN** tmux window 名が `ap-#<数値>` パターンで `state-write --role pilot --set status=done` を呼び出した場合
- **THEN** スクリプトは非ゼロ終了コードで終了し、エラーメッセージを stderr に出力する

#### Scenario: CWD が worktrees 配下の場合に --role pilot を拒否する
- **WHEN** CWD が `*/worktrees/*` パターンで `state-write --role pilot --set status=done` を呼び出した場合
- **THEN** スクリプトは非ゼロ終了コードで終了し、エラーメッセージを stderr に出力する

#### Scenario: Pilot セッションからの --role pilot は許可する
- **WHEN** CWD が `*/main/*` かつ tmux window 名が非 Worker パターンで `state-write --role pilot --set status=done` を呼び出した場合
- **THEN** スクリプトは正常に状態を書き込んでゼロ終了する

---

### Requirement: auto-merge.sh Layer 1 が merge-ready 状態を autopilot と判定する

`scripts/auto-merge.sh` の Layer 1 は、`state-read` で取得した status が `running` または `merge-ready` の場合に `IS_AUTOPILOT=true` と判定しなければならない（SHALL）。

#### Scenario: merge-ready 状態で auto-merge.sh を呼び出した場合に merge を拒否する
- **WHEN** issue-{N}.json の status が `merge-ready` の状態で `auto-merge.sh` が実行された場合
- **THEN** `IS_AUTOPILOT=true` と判定され、merge を実行せず merge-ready 宣言メッセージを出力してゼロ終了する

#### Scenario: running 状態では従来どおり autopilot を検出する
- **WHEN** issue-{N}.json の status が `running` の状態で `auto-merge.sh` が実行された場合
- **THEN** `IS_AUTOPILOT=true` と判定され、merge を実行せず merge-ready 宣言を行う

---

### Requirement: merge-gate-execute.sh が autopilot 判定を実施する

`scripts/merge-gate-execute.sh` は CWD/tmux ガード通過後に、state-read ベースの autopilot 判定を実施しなければならない（SHALL）。ただし merge-gate-execute.sh は Pilot セッションから呼ばれる想定のため、autopilot 下でも merge 実行を許可する（merge 禁止は auto-merge.sh / state-write の責務）。

#### Scenario: merge-gate-execute.sh が worktrees 配下から実行された場合に拒否する
- **WHEN** CWD が `*/worktrees/*` の状態で `merge-gate-execute.sh` を実行した場合
- **THEN** スクリプトは非ゼロ終了コードで終了し、エラーメッセージを出力する（既存動作の維持）

#### Scenario: Worker tmux window から merge-gate-execute.sh を実行した場合に拒否する
- **WHEN** tmux window 名が `ap-#<数値>` パターンで `merge-gate-execute.sh` を実行した場合
- **THEN** スクリプトは非ゼロ終了コードで終了し、エラーメッセージを出力する（既存動作の維持）
