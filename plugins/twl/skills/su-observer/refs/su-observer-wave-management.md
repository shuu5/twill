# Wave 管理・問題検出・介入記録確認

## 既存セッションの状態確認が必要な場合

1. `session-state.sh` で状態確認、`cld-observe` で snapshot 取得
2. `commands/problem-detect.md` を Read → 実行（rule-based 問題検出）
3. 状態サマリをユーザーに報告

## 問題を検出した場合

1. チャネル名を `refs/monitor-channel-catalog.md` の定義と突き合わせてパターン特定
2. `plugins/twl/refs/intervention-catalog.md` を Read → 3 層分類（Auto/Confirm/Escalate）を照合
   - **permission deny 検出時**: 同一カテゴリで 2 回以上発生した場合はパターン 13（Layer 2 Escalate）として即時 STOP + AskUserQuestion（閾値 2 回。1 回目は自動リトライ可）
   - **chain 停止 / 手動 PR 作成停止**: `plugins/twl/refs/ref-chain-resume.md` を Read → 診断手順（Case A/B/C）に従い復旧
3. 層に応じた介入を実行:
   - Layer 0 Auto → `commands/intervene-auto.md` を Read → 実行（SU-7）
   - Layer 1 Confirm → `commands/intervene-confirm.md` を Read → ユーザー確認後実行
   - Layer 2 Escalate → `commands/intervene-escalate.md` を Read → SU-2 ユーザー確認必須

## Wave 管理手順

Issue 群の一括実装（Wave）を要求された場合:

### 0. CRG ヘルスチェック（MUST — Wave 開始前に毎回実行）

```bash
_crg_path="${TWILL_REPO_ROOT}/main/.code-review-graph"
[[ -L "$_crg_path" ]] && echo "⚠️ [CRG health] symlink 検出。rm -f '$_crg_path' で修復してください。" >&2
```

### 1-6. Wave ライフサイクル

1. Wave 分割を計画（または `.autopilot/plan.yaml` から継続）
2. Wave N の Issue リストを確定・ユーザー承認を得る
3. `spawn-controller.sh co-autopilot <prompt>` で起動（詳細: `refs/su-observer-controller-spawn-playbook.md`）
3.5. `refs/monitor-channel-catalog.md` を参照しチャネル選択・Monitor tool 起動（詳細: `refs/su-observer-supervise-channels.md`）
4. `cld-observe-loop` で能動 observe ループ開始
5. Wave 完了を検知したら:
   - `commands/wave-collect.md` を Read → 実行（`WAVE_NUM=<N>`、specialist completeness 監査を含む）
   - `commands/externalize-state.md` を Read → 実行（`--trigger wave_complete`）
   - audit snapshot: `twl audit snapshot --source-dir "${AUTOPILOT_DIR:-.autopilot}" --label "wave/${WAVE_NUM}"`
   - イベントクリーンアップ: `rm -f .supervisor/events/* 2>/dev/null || true`
   - **SU-6a（MUST）**: doobidoo に `observer-wave` / `observer-pitfall` / `observer-lesson` / `observer-intervention` タグで保存（詳細: `refs/pitfalls-catalog.md` §8）。`commands/externalize-state.md` Step 4 Exit Gate で `pitfall_declaration` を宣言し、`${CLAUDE_PLUGIN_ROOT}/skills/su-observer/scripts/externalize-state-exit-gate.sh` で exit 0 を確認すること（未宣言は WARN）
   - **SU-6b（SHOULD）**: context 消費量 80% 以上で `/compact` をユーザーへ提案
   - **Phase B 起票トリガー判定（AC13）**: 以下のいずれかを満たした場合、Phase B Issue を自動起票する（ユーザー確認を得てから）:
     - (a) `gh project item-list 6 --owner shuu5 --format json | jq '[.items[] | select(.status=="Done" and .content.type=="Issue")]'` で Status=Refined 経由 Done が累計 5 件以上
     - (b) #943 merge から 2 Wave 経過（Wave 単位 = su-observer の Wave カウント）
     - (c) observer が明示的に approval を判断した場合（観察期間中の不具合発見等）
6. 次 Wave があれば 1 に戻る。全 Wave 完了時はサマリを報告

## Pilot/co-explore 完遂後の next-step 自律 spawn 規約（MUST）

### 即時 next-step spawn ルール

**MUST**: Pilot または co-explore が完遂した後、observer は **5 分以内に next-step を自律 spawn** しなければならない。

- co-explore 完遂（`.explore/<N>/summary.md` 生成）を検知したら即時 next-step へ遷移する（spawn next-step within 5 min of phase completion）
- PILOT-WAVE-COLLECTED または PILOT-PHASE-COMPLETE を受信したら、次 Wave / 子 Issue 起票を自律的に開始する
- postpone は **user 明示指示時のみ** 許容される。observer 自身が勝手に `完了条件を再定義` して postpone することは **MUST NOT**

### postpone 禁止パターン（MUST NOT）

以下のような observer 独自 postpone 判断は禁止:

| # | 禁止パターン | 正しい対応 |
|---|------------|-----------|
| P1 | 「Phase 1 完遂後まで Phase 2 の next-step を postpone」（実在しない順序依存） | Phase 2 完遂を検知したら即時 spawn。Phase 1 の状態とは独立 |
| P2 | 「ユーザー入力があるまで次の Issue 起票を postpone」（passive 化） | SU-4 制約（5 Issue 以内）を確認し、範囲内であれば直接 `gh issue create` で起票 |
| P3 | 「co-explore が完遂したが worker-spawn チャネルが未確認のため postpone」 | `.explore/<N>/summary.md` 生成検知で即時 spawn 判定。worker-spawn 待ちは不要 |

### 完遂検知チャネル（組み合わせ使用 MUST）

1. `PILOT-WAVE-COLLECTED`（`refs/pilot-completion-signals.md` の `PILOT_WAVE_COLLECTED_REGEX`）
2. `PILOT-PHASE-COMPLETE`（`refs/pilot-completion-signals.md` の `PILOT_PHASE_COMPLETE_REGEX`）
3. `.explore/<N>/summary.md` 生成検知（co-explore 完遂用、filesystem polling または inotifywait）
4. Pilot idle 状態（tmux capture-pane の `Saturated for`/`Worked for` + IDLE prompt 検出）

**参照**: `refs/pitfalls-catalog.md §15`（Wave U incident 詳細）、Issue #1085

---

## 過去の介入記録確認が必要な場合

1. `mcp__doobidoo__memory_search`（キーワード: observation, intervention, detect）
2. `plugins/twl/refs/observation-pattern-catalog.md` を Read → パターンと照合
3. 集約結果をユーザーに提示
4. 新たな Issue 化が必要か確認し、承認時のみ Issue draft 生成

---

## Wave 自動連鎖（auto-next-spawn、#1155）

`IDLE_COMPLETED_AUTO_NEXT_SPAWN=1`（`AUTO_KILL=1` 必須）で Wave N → Wave N+1 の連鎖実行を自動化する。

### 設定方法

```bash
export IDLE_COMPLETED_AUTO_KILL=1
export IDLE_COMPLETED_AUTO_NEXT_SPAWN=1  # or "dry-run" for testing
```

### wave-queue.json 管理

- パス: `.supervisor/wave-queue.json`
- スキーマ: `skills/su-observer/schemas/wave-queue.schema.json`（JSON Schema v7）
- enqueue: `spawn-controller.sh` 起動時に `CHAIN_WAVE_QUEUE_ENTRY` 環境変数（JSON）で渡す

```json
{
  "version": 1,
  "current_wave": 6,
  "queue": [{
    "wave": 7,
    "issues": [1155],
    "spawn_cmd_argv": ["bash", "<TWILL_ROOT>/plugins/twl/skills/su-observer/scripts/spawn-controller.sh", "..."],
    "depends_on_waves": [6],
    "spawn_when": "all_current_wave_idle_completed"
  }]
}
```

### auto-next-spawn.sh フロー

```
kill 成功 → IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 チェック
  → observer-wave-check.sh::_all_current_wave_idle_completed()
    → 全 window IDLE-COMPLETED? Yes → auto-next-spawn.sh 呼び出し
      → JSON Schema validation → allowlist チェック → exec argv 直接渡し
      → wave-queue.json dequeue + current_wave 更新
      → intervention-log.md に記録
```

**参照スクリプト**:
- `skills/su-observer/scripts/auto-next-spawn.sh`（メイン spawn スクリプト、#1155）
- `skills/su-observer/scripts/lib/observer-wave-check.sh`（Wave 判定ライブラリ、#1155）
