## Context

autopilot-orchestrator.sh の polling loop は Pilot の Bash context 内で同期実行される。Pilot が新しいメッセージを受信すると実行中の Bash タスクは cancel され、orchestrator プロセスも停止する。`inject_next_workflow()` の実装自体は正しい（L746-812）が「呼ばれない」のが根本問題。

Wave 18-25 で 28 PRs（#407-#434）が specialist review なしでマージされたのは、chain 停止後に Pilot が独自判断で Worker に直接 nudge → PR 作成 → merge を実行したため。co-autopilot SKILL.md に chain bypass 禁止ルールが明記されておらず、不変条件 M も存在しなかった。

**orchestrator 停止の3パターン:**
1. Pilot が `Bash(timeout=10m)` で orchestrator を実行 → timeout で kill
2. Pilot context window 内の Bash タスクとして管理 → 新メッセージで cancel
3. バックグラウンド実行でも Pilot の context switch で orphan 化

**inject_next_workflow の追加リスク（現状）:**
- Worker プロンプト検出（正規表現 `[>$][[:space:]]*$`）が3回リトライ後タイムアウト → silent return 1
- tmux send-keys のエラーが `/dev/null` にリダイレクトされ silent fail
- 実行結果がログに残らないためデバッグ不能

## Goals / Non-Goals

**Goals:**
- orchestrator polling loop が Pilot の Bash timeout/cancel に影響されず持続する
- `inject_next_workflow()` の実行結果（成功/失敗/理由）が `.autopilot/trace/` に記録される
- co-autopilot SKILL.md に chain bypass 禁止と chain 停止時の正規復旧手順が明記される
- autopilot.md に不変条件 M が追加される
- setup → test-ready → pr-verify の chain 遷移が自動的に完了する

**Non-Goals:**
- orchestrator の全面的なアーキテクチャ刷新（systemd 化、daemon 化等）
- inject_next_workflow の retry ロジック追加（別 Issue 相当）
- resolve_next_workflow の内部ロジック変更

## Decisions

### 1. orchestrator 持続実行: nohup + disown パターン

co-autopilot SKILL.md の Step 4 orchestrator 起動コードを `nohup ... &` + `disown` に変更する。これにより Pilot の Bash プロセスが終了しても orchestrator は独立プロセスとして継続する。

```bash
# 変更前
bash autopilot-orchestrator.sh \
  --plan "$PLAN_FILE" --phase "$PHASE" ...

# 変更後
nohup bash autopilot-orchestrator.sh \
  --plan "$PLAN_FILE" --phase "$PHASE" \
  >> "${AUTOPILOT_DIR}/trace/orchestrator-phase-${PHASE}.log" 2>&1 &
disown
ORCH_PID=$!
echo "[orchestrator] PID=${ORCH_PID} 起動 (nohup)" >&2
```

ただし Pilot は orchestrator が完了したことを知る必要がある。PHASE_COMPLETE イベントの検知に `tail -f` + grep を使う（orchestrator が trace ログに PHASE_COMPLETE を出力する）。

**代替案との比較:**
- systemd unit: セットアップコストが高い、ポータビリティ低下
- tmux new-window: Pilot の tmux セッション依存、複雑化
- nohup/disown: 最小変更、既存の co-autopilot SKILL.md との整合性が高い

### 2. trace ログ記録

`inject_next_workflow()` の実行結果を `.autopilot/trace/inject-{YYYYMMDD}.log` に追記する。

フォーマット:
```
[2026-04-10T14:30:00Z] issue=438 skill=/twl:workflow-test-ready result=success
[2026-04-10T14:35:00Z] issue=438 skill=RESOLVE_FAILED result=skip reason="resolve_next_workflow exit=1"
```

orchestrator 起動時に trace ディレクトリを作成（`mkdir -p "${AUTOPILOT_DIR}/trace"`）。

### 3. chain bypass 禁止ルール（co-autopilot SKILL.md）

co-autopilot SKILL.md の「禁止事項（MUST NOT）」セクションに追加:
- Worker chain 停止時に Pilot が直接 nudge して PR 作成 → マージを実行してはならない
- chain 停止時の正規手順: orchestrator 再起動 or 手動 `twl:workflow-<name>` inject

「chain 停止検知」セクションを新設し、復旧手順を明記する。

### 4. 不変条件 M 追加（autopilot.md）

```
| **M** | chain 遷移は orchestrator/手動 inject のみ | chain 遷移（workflow_done 検知後の次 workflow 起動）は orchestrator の inject_next_workflow または手動 skill inject（`/twl:workflow-<name>`）のみ許可。Pilot の直接 nudge による chain bypass は禁止 | |
```

不変条件数を 12 → 13 に更新。

## Risks / Trade-offs

- **nohup プロセスの孤立リスク**: Pilot がクラッシュした場合、orchestrator が孤立プロセスとして残る。既存の crash-detect.sh（不変条件 G）が Worker をカバーするが orchestrator 自体のクリーンアップは手動が必要。→ trace ログの PID 記録で特定可能にする
- **SKILL.md 変更の即効性**: ルール追加後も Pilot の既存コンテキストには反映されない。次回セッションから有効。これは許容範囲
- **trace ログ肥大化**: 長時間セッションでログが大きくなる。rotate は未実装だが MVP では許容
