# ADR-014: Pilot 駆動ワークフローループ

## Status

Accepted

## Date

2026-04-10

## Related

- ADR-018 (state schema SSOT): `workflow_done` フィールドを廃止し、inject トリガーを `current_step` terminal 値検知に変更。本 ADR の Decision 1-2 の `workflow_done` 関連記述は ADR-018 で supersede された

## Context

47件の Issue を autopilot で実行した結果、**全件で non_terminal_chain_end が発生**した。Worker が workflow-setup → workflow-test-ready → workflow-pr-verify の途中（通常 ac-verify 付近）で停止し、pr-fix / pr-merge に遷移しない。

現在のアーキテクチャでは、Worker（1つの Claude Code セッション）が 5 つの workflow skill を連鎖的に自力実行する設計。遷移メカニズムは以下の3層で構成されるが、全て「お願い」ベースであり機械的保証がない:

1. **SKILL.md 末尾のプロンプト指示**: LLM が従う保証なし。context compaction で消失しうる
2. **PostToolUse hook** (`post-skill-chain-nudge.sh`): LLM が既にレスポンス生成完了後に発火。タイミング的に無効
3. **Orchestrator の tmux nudge** (`check_and_nudge`): Worker が input-waiting 時のみ有効。レスポンス生成中は無視される

試みた対策（PR#313, PR#317, PR#314）は全て効果なし。根本原因は「1つの LLM セッション内で 5 workflow の連鎖実行を LLM 自身に委ねている」構造にある。

## Decision

**Worker は 1 つの workflow skill だけ実行して停止する。Pilot（Orchestrator）が Worker の完了を検知し、次の workflow skill を tmux inject する。**

### 1. Worker の動作変更

各 workflow SKILL.md の末尾遷移セクションを変更:
- 旧: `IS_AUTOPILOT=true → 即座に /twl:workflow-pr-fix を Skill tool で実行（停止禁止）`
- 新: `IS_AUTOPILOT=true → workflow_done を state に記録して停止。Pilot が次の workflow を inject する`

Worker の最終ステップ完了後:
```bash
python3 -m twl.autopilot.state write --type issue --issue "$ISSUE_NUM" --role worker \
  --set "current_step=<last-step>" --set "workflow_done=<workflow-id>"
```

### 2. Orchestrator の inject ロジック

polling ループに新たな状態判定を追加:

```
status=running かつ workflow_done=<workflow-id>
→ meta_chains.worker-lifecycle.flow から次の workflow skill を決定
→ pane capture で入力待ち確認（最大3回、2秒間隔）
→ tmux send-keys で inject
→ workflow_done をクリア
```

inject 安全性のハイブリッド方式:
1. `workflow_done` を state で検知
2. `tmux capture-pane` で入力プロンプトが表示されているか確認（最大3回、2秒間隔でリトライ）
3. プロンプト検出 → inject、未検出 → 10秒後に再チェック

### 3. context 膨張対策

Worker セッションは workflow 間で context が累積する。2層で対策:

**主線: workflow 完了時保存**
- 各 workflow の最終ステップで `.autopilot/issues/issue-{N}-context.md` にサマリーを書き出し
- 内容: 完了ステップ、change-id、PR番号、テスト結果、レビュー所見
- 次の workflow SKILL.md 先頭で「context.md があれば Read して復元」

**補助: PreCompact hook 拡張**
- 既存の `pre-compact-checkpoint.sh` を拡張
- `current_step` に加え、直近の重要変数を `issue-{N}-context.md` に追記
- `post-compact-checkpoint.sh` で stdout に「context.md を Read せよ」を注入

### 4. 不要コンポーネントの整理

- `post-skill-chain-nudge.sh`: 削除（Pilot 駆動で不要）
- `check_and_nudge()` のワークフロー境界 nudge: 削除。stall 検知のみ残す
- Template D 生成ロジック: autopilot=true の遷移を「停止」に変更

### 5. IssueState への追加フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| workflow_done | string \| null | Worker が完了した workflow ID。Pilot が inject 後にクリア |

### 6. deps.yaml meta_chains との機械的同期

Orchestrator は `deps.yaml` の `meta_chains.worker-lifecycle.flow` を SSOT として参照し、次の workflow skill を機械的に決定する。`chain.py` に `resolve_next_workflow()` を追加:

```python
def resolve_next_workflow(current_workflow: str, is_autopilot: bool, is_quick: bool) -> str | None:
    """meta_chains.worker-lifecycle.flow から次の workflow skill を解決"""
```

Template D 生成（`meta_generate.py`）も連動して更新し、SKILL.md の遷移セクションが SSOT と自動同期される。

## Consequences

### Positive
- LLM の指示遵守に依存しない機械的ワークフロー遷移
- 各 workflow が独立。compaction リスク低減
- PostToolUse hook (`post-skill-chain-nudge.sh`) 削除により Worker 実行の軽量化
- tmux inject のタイミング問題が解消（Worker は停止状態で待機）

### Negative
- Worker セッションに inject 待ちの idle 時間が発生（最大6〜16秒）
- Orchestrator の改修が必要（inject ロジック + pane capture 確認）
- Worker が context.md を Read する指示が SKILL.md に追加される（プロンプト膨張）

### Risks
- tmux pane capture での入力待ち判定が Claude Code の UI 変更で壊れる可能性
  → 緩和策: 固定待機時間へのフォールバック
- context.md の書き出し内容が不十分で次 workflow が失敗する可能性
  → 緩和策: context.md のスキーマを定義し、必須フィールドをバリデーション
