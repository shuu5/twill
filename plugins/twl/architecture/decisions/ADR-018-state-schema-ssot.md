# ADR-018: autopilot state schema SSOT — status フィールドを外部観察の唯一の正典に指定

**Status**: Accepted  
**Date**: 2026-04-12  
**Issue**: #507  
**Supersedes**: —  
**Related**: ADR-003 (unified state file)、ADR-021 (pilot-driven workflow loop)

---

## Context

`.autopilot/issues/issue-{N}.json` には進捗を表す3フィールドが存在していた:

| フィールド | 役割 |
|---|---|
| `status` | Issue ライフサイクル全体の状態（running/merge-ready/done/failed/conflict） |
| `current_step` | chain-runner が記録する実行中のステップ名 |
| `workflow_done` | chain terminal で書かれ、orchestrator の inject トリガーとして機能した後に null クリアされる |

Wave 7 で Monitor が `workflow_done` の null 逆戻りを異常と誤検知し、STAGNATE 警告を繰り返し発した。根本原因は「外部観察者が正しい状態を判断するための SSOT フィールドが不明」なこと。

## Decision

**`status` を SSOT（Single Source of Truth）に指定する（Option 1）。**

1. **`status` = 外部観察の唯一のフィールド**: Monitor/su-observer は `jq -r '.status'` 単一クエリで進捗を判定する
2. **`workflow_done` を廃止**: inject トリガーを `current_step` の terminal 値検知に変更する
3. **`current_step` = orchestrator 内部フィールド**: inject トリガー判定のみに使用。外部観察には使用しない

### Option 1 を選んだ理由

- Monitor/su-observer の主用途は「マージ可能か」「正常か」の判定であり、`status` の意味的粒度がそれに合致する
- `current_step` は chain 内部の実装詳細であり、外部観察に露出すると Observer と chain 実装が密結合になる
- `workflow_done` は「null クリア後は null」という性質が外部観察を困難にする根本原因

### Option 2（current_step SSOT）を選ばなかった理由

- chain-runner の都合に合わせた設計になりすぎる
- chain の internal state が外部インターフェースになり、chain 変更ごとに Observer を修正する必要が生じる

## Consequences

### 廃止フィールド

`workflow_done` を廃止する。以下の全箇所を更新する:

**Writer（書込側）— 削除:**
- `plugins/twl/skills/workflow-setup/SKILL.md`
- `plugins/twl/skills/workflow-test-ready/SKILL.md`
- `plugins/twl/skills/workflow-pr-verify/SKILL.md`
- `plugins/twl/skills/workflow-pr-fix/SKILL.md`
- `plugins/twl/skills/workflow-pr-merge/SKILL.md`
- `plugins/twl/scripts/autopilot-orchestrator.sh`（AC-2 fallback）
- `plugins/twl/scripts/chain-runner.sh`

**Reader（読込側）— 代替に変更:**
- `plugins/twl/scripts/autopilot-orchestrator.sh`（inject 検知ロジック）
- `cli/twl/src/twl/autopilot/resolve_next_workflow.py`
- `cli/twl/src/twl/autopilot/state.py`（`_PILOT_ISSUE_ALLOWED_KEYS` から除外）

### 新しい inject トリガー機構

`current_step` の terminal 値検知:

| terminal current_step | 次 workflow |
|---|---|
| `ac-extract` | workflow-test-ready |
| `post-change-apply` | workflow-pr-verify |
| `ac-verify` | workflow-pr-fix |
| `warning-fix` | workflow-pr-merge |

重複 inject 防止: orchestrator が `LAST_INJECTED_STEP[issue]` でローカルトラッキング。`current_step` が変化した時のみ inject。

### 正常な状態遷移（5値）

```
running → merge-ready | failed
merge-ready → done | failed | conflict
failed → running (retry_count < 1) | done (force-done のみ)
conflict → merge-ready (conflict_retry_count < 1) | failed
done → [終端]
```

### STAGNATE 判定の単純化

```bash
status=$(jq -r '.status' issue-N.json)
[[ "$status" == "merge-ready" || "$status" == "done" || "$status" == "conflict" ]] && skip_stagnate=1
```

## Migration

既存の running session は `workflow_done` が null になるが、`current_step` の terminal 値検知で inject が継続して機能する。既存 session への影響は最小限。

---

## Amendment (2026-04-22、Issue #890): `last_heartbeat_at` field 追加

### 背景

Phase D #888 で step-aware stagnation threshold (300s) を導入した後、`_check_stagnation` は `updated_at` を heartbeat 代替として使用していた。しかし:

- `updated_at` は `state.py::StateManager.write` が任意 write 時に自動更新する。軽微な副作用 write (例: `input_waiting_detected` 更新) でも fresh になる
- LLM 判断 step 内で chain 境界を通過していないのに、別経路で state write が発生すると、実質 stall でも `updated_at` が fresh で誤 no-stagnate
- 逆に worker が生存していても `updated_at` が長時間 stale なら誤 stagnate

### 新 field: `last_heartbeat_at`

| フィールド | 役割 | Writer |
|---|---|---|
| `last_heartbeat_at` | chain step 境界を通過した pure heartbeat (ISO8601 UTC) | `chain-runner.sh::record_current_step` のみ |

- `StateManager._init_issue` で `last_heartbeat_at: now` 初期化
- `chain-runner.sh::record_current_step` が `current_step` と同時に `last_heartbeat_at` を更新
- `orchestrator.py::_check_stagnation` が `last_heartbeat_at` 優先参照、欠損時のみ `updated_at` に fallback (backward compat)

### ADR-018 との位置づけ

本 Amendment は ADR-018 Decision の原則（`status` = 外部観察 SSoT）を変更しない。`last_heartbeat_at` は orchestrator 内部判定の補助 field であり、Monitor/su-observer の外部観察には公開しない。既存廃止フィールド方針 (`workflow_done`) は維持する。
