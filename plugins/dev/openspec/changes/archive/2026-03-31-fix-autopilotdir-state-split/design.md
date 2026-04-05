## Context

bare repo 構成（`.bare/` + worktree）で co-autopilot を実行すると、PROJECT_DIR の導出方法が Pilot（SKILL.md）とスクリプト群（`SCRIPT_DIR/..`）で異なる。結果として `.autopilot/` が2箇所に分散し、Pilot と Worker が互いの状態ファイルを参照できない。

全スクリプトは既に `${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}` パターンで env override に対応済み。不足しているのは co-autopilot SKILL.md からの `AUTOPILOT_DIR` の export と、コマンド層（autopilot-init.md, autopilot-phase-execute.md）での環境変数伝搬のみ。

## Goals / Non-Goals

**Goals:**

- co-autopilot SKILL.md Step 0 で `AUTOPILOT_DIR` を export し、全ステップで一貫したパスを使用
- autopilot-init.md の全スクリプト呼び出しで `AUTOPILOT_DIR` を明示的に渡す
- autopilot-phase-execute.md の全スクリプト呼び出しで `AUTOPILOT_DIR` を伝搬

**Non-Goals:**

- scripts/*.sh の変更（既に env override 対応済み）
- autopilot-plan.sh の変更（PROJECT_DIR 引数経由で正しく動作）
- PROJECT_DIR 導出ロジック自体の統一（別 Issue #70 のスコープ）

## Decisions

1. **AUTOPILOT_DIR の定義位置**: co-autopilot SKILL.md Step 0 で `PROJECT_DIR` 取得直後に `AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` を export する。これにより Pilot セッション内の全ステップで統一パスが使用される。

2. **コマンド層での伝搬方法**: autopilot-init.md と autopilot-phase-execute.md の各スクリプト呼び出しで `AUTOPILOT_DIR=$AUTOPILOT_DIR` を環境変数として前置する。スクリプト引数ではなく env 経由で渡す（スクリプト側が既に `${AUTOPILOT_DIR:-default}` で受け取る設計のため）。

3. **SESSION_STATE_FILE の定義**: autopilot-init.md の出力変数 `SESSION_STATE_FILE` を `$AUTOPILOT_DIR/session.json` に統一（現在は `$PROJECT_ROOT/.autopilot/session.json` とハードコードされている可能性）。

## Risks / Trade-offs

- **リスク**: `PROJECT_DIR` の `git rev-parse --git-common-dir | dirname` が bare repo ルートを返す。main worktree の `.autopilot/` ではなく bare root の `.autopilot/` が使用されるが、Pilot/Worker 間で一貫していればどちらでも正常動作する。
- **トレードオフ**: `.autopilot/` の配置先が bare root に統一されるため、`main/.autopilot/` に手動で作成した状態ファイルがある場合は認識されなくなる。ただし現時点で手動作成のユースケースはない。
