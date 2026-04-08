---
name: twl:workflow-self-improve
description: |
  Self-Improve 改善適用ワークフロー（collect → propose → close + ecc-monitor）。

  co-autopilot の後処理として呼び出される。直接ユーザートリガーは co-autopilot 経由。
type: workflow
effort: medium
spawnable_by:
- controller
---

# workflow-self-improve

Self-Improve Bounded Context の「改善適用フロー」を workflow として実装する。
`contexts/self-improve.md` で定義された collect → propose → close フローを担当する。

## フロー制御（MUST）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。

### Step 1: self-improve-collect（Issue 収集）

`commands/self-improve-collect.md` を Read → 実行。

- self-improve ラベル付き Issue を収集・分類・優先度ソート
- 0 件の場合は「改善候補 Issue なし」と報告して終了

### Step 2: self-improve-propose（提案生成）

Step 1 で Issue が 1 件以上あった場合のみ実行。

`commands/self-improve-propose.md` を Read → 実行。

- cooldown 判定 → ECC 照合 → 改善提案生成 → ユーザー確認（IS_AUTOPILOT=true 時は自動承認）
- 全件 cooldown or 棄却の場合はその旨を報告して終了

### Step 3: self-improve-close（適用 + クローズ）

Step 2 で承認済み Issue が 1 件以上あった場合のみ実行。

`commands/self-improve-close.md` を Read → 実行（承認済み各 Issue について）。

### Step 4: ecc-monitor（ECC 変更検知、任意）

IS_AUTOPILOT 判定:

```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
IS_AUTOPILOT=false
if [ -n "$ISSUE_NUM" ]; then
  AUTOPILOT_STATUS=$(python3 -m twl.autopilot.state read --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
fi
```

- IS_AUTOPILOT=true → `commands/ecc-monitor.md` を Read → `evaluate` サブコマンドで実行
- IS_AUTOPILOT=false → スキップ（ユーザーが手動で `/twl:ecc-monitor` を実行可能）

## 禁止事項（MUST NOT）

- ユーザー確認なしでファイルを変更してはならない（IS_AUTOPILOT=true 時を除く）
- cooldown 判定をスキップしてはならない
- Step 1 で 0 件の場合に後続ステップを実行してはならない

## co-self-improve との関係

本 workflow は**受動的** self-improvement（autopilot 後処理）を担当する。
co-autopilot 完了時に自動呼び出しされ、蓄積された self-improve Issue を collect → propose → close する。
**能動的**なライブセッション観察（out-of-process observation）は `co-self-improve` controller（ADR-011 で定義）が担当する。
両者は責務が重ならず、独立して動作する。
