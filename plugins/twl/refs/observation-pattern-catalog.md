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

## bug-reproduction patterns

```yaml
bug-deltaspec-archive:
  regex: 'archive.*fail|fail.*archive|Error.*archive|deltaspec.*archive.*error'
  severity: error
  category: deltaspec-archive-failure
  description: "deltaspec archive 失敗検出 (#436 関連)"
  related_issue: "436"

bug-chain-stall:
  regex: 'chain.*stall|polling.*timeout|transition.*stop|chain.*stop'
  severity: error
  category: chain-transition-stall
  description: "chain 遷移停止 / polling timeout 検出 (#438 関連)"
  related_issue: "438"

bug-phase-review-skip:
  regex: 'phase.review.*skip|phase.review\.json.*not found|skip.*phase.review'
  severity: warning
  category: phase-review-skip
  description: "phase-review スキップ / phase-review.json 不在検出 (#439 関連)"
  related_issue: "439"

bug-469-chain-end:
  regex: 'non_terminal_chain_end|chain.*end.*non.terminal|WorkflowTransitionError'
  severity: error
  category: non-terminal-chain-end
  description: "Worker 完了後の non_terminal_chain_end による workflow-pr-verify 遷移停止検出 (#469 関連)"
  related_issue: "469"

bug-470-state-path:
  regex: 'state.*path.*not found|state file.*missing|autopilot.*state.*resolve.*fail'
  severity: error
  category: state-path-resolution
  description: "Pilot state file パス誤認による state 参照失敗検出 (#470 関連)"
  related_issue: "470"

bug-471-refspec:
  regex: 'refspec.*missing|remote\.origin\.fetch.*not set|fetch.*origin.*main.*fail'
  severity: error
  category: refspec-missing
  description: "remote.origin.fetch refspec 欠落による git fetch 失敗検出 (#471 関連)"
  related_issue: "471"

bug-472-monitor-stall:
  regex: 'PHASE_COMPLETE.*wait.*timeout|Monitor.*stall|Monitor.*hang|phase.*complete.*never'
  severity: error
  category: monitor-stall
  description: "Pilot Monitor の PHASE_COMPLETE wait 無限 stall 検出 (#472 関連)"
  related_issue: "472"
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
