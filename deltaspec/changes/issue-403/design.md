## Context

pr-verify chain は以下の順序で実行される設計:
prompt-compliance → ts-preflight → **phase-review** → **scope-judge** → pr-test → ac-verify

しかし chain 実行フレームワーク（chain-steps.sh、chain.py、chain-runner.sh）に phase-review と scope-judge が未登録のため、この 2 ステップは chain の next-step 判定で選ばれず完全にスキップされる。

**既存ファイルの状態:**
- `chain-steps.sh`: CHAIN_STEPS 配列の pr-verify セクションに `prompt-compliance`, `ts-preflight`, `pr-test`, `ac-verify` のみ（phase-review/scope-judge なし）
- `chain.py`: STEP_TO_WORKFLOW に phase-review/scope-judge の登録なし
- `chain-runner.sh`: case 文に phase-review/scope-judge のハンドラなし

**deps.yaml の定義（正しい）:**
- `phase-review`: `dispatch_mode: llm`, `type: composite`
- `scope-judge`: `dispatch_mode: llm`, `type: atomic`

**既存の llm dispatch パターン（change-propose 等）:**
```bash
change-propose) record_current_step "change-propose"; ok "change-propose" "LLM スキル実行（chain-runner はステップ記録のみ）" ;;
```
chain-runner.sh は record_current_step のみ実行し、実際の LLM 判断は SKILL.md 側（workflow-pr-verify）が commands/*.md を Read → 実行する。

## Goals / Non-Goals

**Goals:**

- chain-steps.sh の CHAIN_STEPS 配列（pr-verify セクション）に phase-review と scope-judge を正しい順序で追加
- chain.py の STEP_TO_WORKFLOW に phase-review → "pr-verify"、scope-judge → "pr-verify" を追加
- chain-runner.sh の case 文に phase-review と scope-judge のハンドラを追加（既存 llm dispatch パターンに準拠）
- chain trace に phase-review の start/end イベントが記録されることを確認する自動テストを追加または拡張

**Non-Goals:**

- commands/phase-review.md や commands/scope-judge.md の内容変更
- workflow-pr-verify.md の内容変更
- specialist の実行ロジック変更

## Decisions

**D-1: chain-steps.sh への挿入位置**

CHAIN_STEPS 配列の pr-verify セクションで `ts-preflight` の後、`pr-test` の前に phase-review と scope-judge を挿入する。これが Issue の「期待される動作」で指定された順序と一致する。

**D-2: chain-runner.sh のハンドラ実装**

既存の `change-propose` と同じパターン:
```bash
phase-review) record_current_step "phase-review"; ok "phase-review" "LLM スキル実行（chain-runner はステップ記録のみ）" ;;
scope-judge)  record_current_step "scope-judge";  ok "scope-judge"  "LLM スキル実行（chain-runner はステップ記録のみ）" ;;
```
workflow-pr-verify SKILL.md の LLM 実行側が commands/phase-review.md と commands/scope-judge.md を Read して実行するため、chain-runner.sh は step 記録のみ担う。

**D-3: DISPATCH_MODE マップへの追加**

chain-steps.sh の `declare -A STEP_DISPATCH_MODE` に phase-review=llm、scope-judge=llm を追加する。

**D-4: STEP_CMD マップへの追加**

chain-steps.sh の `declare -A STEP_CMD` に phase-review の commands/phase-review.md、scope-judge の commands/scope-judge.md を追加する（既存の ac-verify=commands/ac-verify.md パターンに準拠）。

## Risks / Trade-offs

**R-1: テスト追加の影響範囲**

既存の chain trace テストを拡張するか新規テストを追加するかは、テストファイルの構造を確認してから決定する。既存テストのステップリストに phase-review/scope-judge を追加するだけで済む可能性が高い。

**R-2: chain-steps.sh の STEP_TO_WORKFLOW ミラー**

chain-steps.sh の `CHAIN_STEP_TO_WORKFLOW` は chain.py の STEP_TO_WORKFLOW のミラーと明記されている。両ファイルを同時に更新し整合性を保つ必要がある。
