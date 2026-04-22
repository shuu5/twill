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
  severity: error | warning | info
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

channel-input-wait:
  regex: 'input-waiting|Enter to select|↑/↓ to navigate|承認しますか|確認しますか|\[y/N\]|\[Y/n\]|Do you want to|Waiting for user input'
  severity: warning
  category: input-waiting
  intervention: Auto
  description: "[INPUT-WAIT] approval UI / AskUserQuestion / y/N プロンプトで window が input-waiting 状態。session-comm.sh inject で即時介入可能 (#486 関連)"
  related_issue: "486"

channel-pilot-idle:
  regex: 'Skedaddling|Frolicking|Background.*poll|idle.*5.*min|5 分.*停滞'
  severity: warning
  category: pilot-idle
  intervention: Confirm
  description: "[PILOT-IDLE] Pilot が Skedaddling/Frolicking/Background poll で 5 分以上停滞。wave 進行の遅延リスクあり (#486 関連)"
  related_issue: "486"

channel-stagnate:
  regex: 'state.*stagnate|stagnate.*detect|mtime.*600|updated_at.*600|state file.*not updated'
  severity: warning
  category: state-stagnate
  intervention: Confirm
  description: "[STAGNATE] .supervisor/working-memory.md / .autopilot/waves/*.summary.md / .autopilot/checkpoints/*.json の mtime が 10 分以上更新されない (#486 関連)"
  related_issue: "486"
```

## 観察パターン (Phase B W1 追記)

Phase A ～ Wave 5 で蓄積された observer-pitfall / observer-lesson を自然言語観察セクションとして記録。
su-observer SKILL.md「過去の介入記録確認」ステップ (L.182) の catalog Read 時に自動参照される。

```yaml
hist-interrupted-detect:
  regex: 'Interrupted by user|Monitor.*interrupt.*soft_deny|interrupt.*classifier.*collide'
  severity: warning
  category: interrupted-detection
  description: "[INTERRUPTED-DETECT] Monitor tool の 'Interrupted by user' が auto mode classifier soft_deny と衝突した際の盲点。pane 状態を session-state.sh で確認し手動介入の要否を判定すること"
  observation_signal: "Monitor tool 出力に 'Interrupted by user' が出現"
  detection_condition: "auto mode 動作中に Monitor が soft_deny と衝突した場合"
  action: "session-state.sh で pane 状態確認 → input-waiting なら inject、それ以外は監視継続"
  memory_hash: "cda6473c"

hist-auto-yes-43-45:
  regex: 'input-waiting.*inject|auto.*inject.*"1"|inject.*1.*success'
  severity: info
  category: auto-yes-success
  description: "[AUTO-YES] input-waiting 検知 → auto inject '1' の実運用パターン。Phase A Wave 2 で 45 回連続成功。channel-input-wait パターンと組み合わせた正常動作確認済みフロー"
  observation_signal: "channel-input-wait 検知 → inject '1' → 承認完了"
  detection_condition: "AskUserQuestion / y/N プロンプトで input-waiting 状態、かつ auto mode が有効"
  action: "session-comm.sh inject-file で '1' を送信。成功率 100% (45/45) の実績あり"
  memory_hash: "Phase A Wave 2"

hist-inject-buffer-collide:
  regex: 'inject-file.*concurrent|paste.*buffer.*corrupt|buffer.*collide|tmux.*buffer.*fail'
  severity: error
  category: inject-buffer-collision
  description: "[BUFFER-COLLIDE] inject-file を 2 セッション同時実行すると tmux paste buffer が破損する。inject 間隔は serial 15s 以上を MUST 化すること"
  observation_signal: "inject 後に対象 pane でコマンドが二重実行 / 文字化け / 無応答が発生"
  detection_condition: "2 以上の セッションが 15s 未満の間隔で inject-file を呼び出した場合"
  action: "inject を直列化し 15s 以上の間隔を確保。並列 inject は禁止"
  memory_hash: "06fd9a74"

hist-inject-wait-timeout:
  regex: 'spawn.*controller.*timeout|inject.*wait.*timeout|processing.*input-waiting.*60s|cld-spawn.*state.*transition.*fail'
  severity: warning
  category: inject-wait-timeout
  description: "[INJECT-TIMEOUT] spawn-controller.sh 経由 cld-spawn 直後に session-state.sh が processing → input-waiting 遷移を 60s 以内に検出できない既知問題。workaround: 待機時間を 120s に延長するか polling 間隔を調整する"
  observation_signal: "inject-file --wait 実行後 60s でタイムアウトエラー / pane が processing のまま停滞"
  detection_condition: "cld-spawn 直後 (~60s 以内) に inject-file --wait を実行した場合"
  action: "待機時間を 120s 以上に設定するか、cld-spawn 後 90s 待ってから inject を試みる"
  memory_hash: "15ab26c5"

hist-classifier-bypass-context:
  regex: 'bypass.*intent|classifier.*bypass|deny.*bypass|Layer D.*deny'
  severity: warning
  category: classifier-bypass-context
  description: "[BYPASS-CONTEXT] Classifier の bypass 意図検出はセッション内 action history で累積判定される。類似操作の deny 後にアプローチを変えた再試行も deny される（実測: 6 連続拒否、2026-04-21）。W5-1 (Security gate MUST NOT), W5-2 (2-deny STOP rule) と三位一体。observer は deny を「意図の二次検証」として受容し即 STOP すること"
  observation_signal: "同一セッション内で類似操作が複数回 deny され、trick を変えても deny が継続する（gh issue edit → deny、spec-review-session-init + gh issue edit → deny、計 6 連続拒否）"
  detection_condition: "bypass 意図を持つ操作（label 追加・settings.json 変更提案等）が deny され、直後に手法を変えた類似操作も deny された場合。deny 回数に関係なく累積検出される"
  action: "deny を受容し即 STOP。W5-2 (2-deny STOP rule) に従い 2 回目 deny の時点で作業停止しユーザーに報告。bypass 試行を重ねるほど検出感度が上がるため早期停止が最善策"
  related_issue: "840"
  memory_hash: "886e374d"
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
