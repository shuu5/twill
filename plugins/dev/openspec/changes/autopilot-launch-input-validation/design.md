## Context

autopilot-launch.md は autopilot-phase-execute から呼び出され、tmux new-window で Worker（cld）を起動する。クロスリポジトリ対応で追加された ISSUE_REPO_OWNER / ISSUE_REPO_NAME / PILOT_AUTOPILOT_DIR の3変数は、autopilot-plan.sh 側でバリデーション済みだが、autopilot-launch.md 側では未検証のまま tmux コマンドに展開される。defense-in-depth の原則に基づき、launch 側でも独自にバリデーションを行う。

他のスクリプト（state-read.sh, merge-gate-execute.sh, autopilot-plan.sh）では既に `^[a-zA-Z0-9_-]+$` パターンでのバリデーションが実装されており、同一パターンを採用する。

## Goals / Non-Goals

**Goals:**

- ISSUE_REPO_OWNER / ISSUE_REPO_NAME に `^[a-zA-Z0-9_-]+$` バリデーション追加
- PILOT_AUTOPILOT_DIR にパストラバーサル（`..`）防止と絶対パス必須のバリデーション追加
- AUTOPILOT_ENV / REPO_ENV の値を printf '%q' でクォートし、tmux コマンド展開を安全にする
- バリデーション失敗時は state-write.sh で status=failed に遷移

**Non-Goals:**

- autopilot-plan.sh 側のバリデーション変更（既に十分）
- ISSUE 変数のバリデーション（既に数値として扱われている）
- state-write.sh / state-read.sh の変更

## Decisions

1. **バリデーションの挿入位置**: Step 4（コンテキスト注入構築）と Step 5 の間に新しい「Step 4.5: 入力バリデーション」を追加。Step 5 で変数を使用する直前にチェックする
2. **バリデーションパターン**: `^[a-zA-Z0-9_-]+$` を ISSUE_REPO_OWNER / ISSUE_REPO_NAME に適用。既存の autopilot-plan.sh / merge-gate-execute.sh と同一パターン
3. **PILOT_AUTOPILOT_DIR のバリデーション**: 絶対パス必須（`^/` で始まる）、`..` コンポーネント禁止、printf '%q' でクォート
4. **エラー時の動作**: state-write.sh で status=failed + failure JSON を書き込み、return 1。ワークフロー全体の停止と同じパターン（Step 1 の cld 未検出時と同一）
5. **クォート方式**: AUTOPILOT_ENV / REPO_ENV の値部分のみ printf '%q' でクォート。env コマンドの `KEY=VALUE` 形式は維持

## Risks / Trade-offs

- **リスク**: バリデーションが厳しすぎると正当なリポジトリ名（例: ドットを含む名前 `my.repo`）がブロックされる可能性。ただし REPO_NAME は OWNER/NAME 分離済みで、GitHub の命名規則上 `^[a-zA-Z0-9_.-]+$` が正確。OWNER は `^[a-zA-Z0-9_-]+$` で十分
- **トレードオフ**: defense-in-depth としてのバリデーション追加は冗長だが、セキュリティ上の安全マージンを確保する。autopilot-plan.sh のバリデーションが将来変更されても launch 側は独立して安全
