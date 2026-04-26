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
   - **SU-6a（MUST）**: doobidoo に `observer-wave` / `observer-pitfall` / `observer-lesson` / `observer-intervention` タグで保存（詳細: `refs/pitfalls-catalog.md` §8）。`commands/externalize-state.md` Step 4 Exit Gate で `pitfall_declaration` を宣言し、`scripts/externalize-state-exit-gate.sh` で exit 0 を確認すること（未宣言は WARN）
   - **SU-6b（SHOULD）**: context 消費量 80% 以上で `/compact` をユーザーへ提案
   - **Phase B 起票トリガー判定（AC13）**: 以下のいずれかを満たした場合、Phase B Issue を自動起票する（ユーザー確認を得てから）:
     - (a) `gh project item-list 6 --owner shuu5 --format json | jq '[.items[] | select(.status=="Done" and .content.type=="Issue")]'` で Status=Refined 経由 Done が累計 5 件以上
     - (b) #943 merge から 2 Wave 経過（Wave 単位 = su-observer の Wave カウント）
     - (c) observer が明示的に approval を判断した場合（観察期間中の不具合発見等）
6. 次 Wave があれば 1 に戻る。全 Wave 完了時はサマリを報告

## 過去の介入記録確認が必要な場合

1. `mcp__doobidoo__memory_search`（キーワード: observation, intervention, detect）
2. `plugins/twl/refs/observation-pattern-catalog.md` を Read → パターンと照合
3. 集約結果をユーザーに提示
4. 新たな Issue 化が必要か確認し、承認時のみ Issue draft 生成
