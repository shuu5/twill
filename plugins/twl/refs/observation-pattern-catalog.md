---
type: reference
spawnable_by: [controller, atomic, workflow]
disable-model-invocation: true
---

# Observation Pattern Catalog

子 4 problem-detect atomic が使用する rule-based パターン定義。

## パターン形式

```yaml
<pattern-id>:
  regex: <正規表現>
  severity: critical | high | medium | low | info
  category: <カテゴリ名>
  description: <説明>
  related_issue: <関連 Issue 番号、optional>
```

## error patterns

```yaml
error-general:
  regex: '^Error:'
  severity: error
  category: general-error
  description: "汎用エラー出力"

error-api:
  regex: '^APIError:|API Error'
  severity: error
  category: claude-api-error
  description: "Claude API エラー"

error-mergegate:
  regex: 'MergeGateError'
  severity: error
  category: merge-gate-failure
  description: "merge-gate 失敗"
  related_issue: "166"
```

## warning patterns

```yaml
warn-failed-to:
  regex: 'failed to'
  severity: warning
  category: general-failure
  description: "汎用失敗メッセージ"

warn-critical-tag:
  regex: '\[CRITICAL\]'
  severity: warning
  category: critical-tag
  description: "CRITICAL タグ付きメッセージ"
```

## info patterns

```yaml
info-nudge:
  regex: 'nudge sent'
  severity: info
  category: worker-stall
  description: "Worker stall で nudge 送信"

info-rebase:
  regex: 'force.with.lease'
  severity: info
  category: pilot-rebase-intervention
  description: "Pilot による rebase 介入痕跡"
```

## historical patterns (過去のインシデント由来)

```yaml
hist-silent-deletion:
  regex: 'silent.*deletion'
  severity: error
  category: silent-deletion
  description: "silent file deletion 検出 (#166 関連)"
  related_issue: "166"

hist-ac-shrinking:
  regex: 'AC.*shrink|shrink.*AC'
  severity: error
  category: ac-shrinking
  description: "AC 矮小化検出 (#167 関連)"
  related_issue: "167"
```

## 拡張ガイド

新しいパターンを追加する場合:

1. **頻度確認**: 過去の observation で 2 回以上検出されたパターンか確認する
2. **カテゴリ整合**: category は既存のいずれかに合致するか検討し、新規の場合は命名規則 (`kebab-case`) に従う
3. **severity 判定**: 影響範囲で決定する
   - `error`: production 影響あり、即時対処が必要
   - `warning`: 潜在的問題、監視対象
   - `info`: 検出のみ、統計目的
4. **regex 検証**: 追加前に `echo "test string" | grep -E "$REGEX"` で valid であることを確認する
5. **テスト追加**: 追加後は `tests/bats/refs/observation-references.bats` に検証ケースを追加する
