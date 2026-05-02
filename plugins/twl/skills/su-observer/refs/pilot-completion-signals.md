# Pilot Completion Signals

su-observer が Pilot 内部 chain 完遂を検知するための signal 一覧。
Monitor filter / cld-observe-any pattern 設定時に本ファイルを参照すること（MUST）。

> **背景（Issue #948）**: Pilot 内部 chain（別 tmux window `ap-*` を作らない co-autopilot flow variant）完遂時、
> `>>> 実装完了:` シグナルが Worker 側からしか emit されないため、Worker を spawn しない Pilot 内部 chain 完遂は
> 従来の filter では検知できなかった。本ファイルはその構造的欠陥への対処として新設。

---

## Controller 別 Pilot 完了 signal 一覧

| Controller | 完了種別 | Signal テキスト（verified from grep） | ソースファイル |
|---|---|---|---|
| co-autopilot | Phase 完了 | `[orchestrator] Phase <N> 完了` | `autopilot-orchestrator.sh:1286` |
| co-autopilot | Phase 完了 JSON | `{"signal": "PHASE_COMPLETE", "phase": N, ...}` | orchestrator JSON emit |
| co-autopilot | Issue merge 成功 | `[auto-merge] Issue #<N>: merge 成功` | `auto-merge.sh:190` |
| co-autopilot | Issue merge+close | `[merge-gate] Issue #<N>: マージ完了 + Issue CLOSED 確認済み` | merge-gate |
| co-autopilot | Worker 起動 | `Worker 起動完了: Issue #<N>` | `autopilot-launch.sh` |
| co-autopilot | クリーンアップ | `[orchestrator] cleanup: Issue #<N> — window/branch クリーンアップ` | orchestrator |
| co-autopilot | Wave 収集 | `[wave-collect] Wave <N> サマリを生成しました: <path>` | `wave-collect.md` |
| co-issue | Issue 作成完了 | `>>> Issue #<N> 作成完了` | co-issue SKILL.md |
| co-issue (refine) | refine 完遂 | `[IDLE-COMPLETED]` channel (`Status=Refined` + label `refined` 付与で検知) | issue-lifecycle-orchestrator.sh 出口 |
| co-architect | arch review PASS | `>>> arch-phase-review PASS` | co-architect SKILL.md |
| co-architect | arch merge | `[arch-merge] ...` | co-architect SKILL.md |
| 共通（Pilot カスタム） | Phase/Wave/Step 完遂 | `>>> Phase <X> Wave <N> step <M> 完遂` | Pilot 直接出力 |

---

## Monitor filter regex snippet

```bash
# Pilot 内部 chain 完遂 signal を検知する Monitor filter
# (Worker spawn しない Pilot-internal flow 対応)
PILOT_COMPLETE_PATTERN='(\[orchestrator\] Phase [0-9]+ 完了|\{"signal": "PHASE_COMPLETE"|\[auto-merge\] Issue #[0-9]+: merge 成功|\[merge-gate\] Issue #[0-9]+: マージ完了|\[wave-collect\] Wave [0-9]+ サマリ|>>> Phase [A-Z]+ Wave [0-9]+ step [0-9]+ 完遂|>>> Issue #[0-9]+ 作成完了|>>> arch-phase-review PASS)'

# 使用例（Monitor tool の pattern 引数として）
# pattern="${PILOT_COMPLETE_PATTERN}"
# description='[PILOT-COMPLETE] Pilot 内部 chain 完遂を検知しました'
```

---

## チャネル別推奨 regex（monitor-channel-catalog.md と対応）

### PILOT-PHASE-COMPLETE

Pilot が Phase/Issue を完了したことを示す signal:

```bash
PILOT_PHASE_COMPLETE_REGEX='(\[orchestrator\] Phase [0-9]+ 完了|\{"signal": "PHASE_COMPLETE"|\[merge-gate\] Issue #[0-9]+: マージ完了|\[orchestrator\] cleanup: Issue #[0-9]+)'
```

### PILOT-ISSUE-MERGED

Issue の PR がマージされ Issue がクローズされた signal:

```bash
PILOT_ISSUE_MERGED_REGEX='\[auto-merge\] Issue #[0-9]+: merge 成功'
```

### PILOT-WAVE-COLLECTED

Wave 完了後の収集処理が完了した signal:

```bash
PILOT_WAVE_COLLECTED_REGEX='\[wave-collect\] Wave [0-9]+ サマリを生成しました'
```

---

## CO-EXPLORE-COMPLETE — co-explore 完遂検知（.explore/<N>/summary.md 生成）

> **追加背景（Issue #1085）**: co-explore Worker は completion signal を tmux pane に emit しない構造のため、
> `.explore/<N>/summary.md` のファイル生成を filesystem で直接検知する必要がある。

**検知対象**: `.explore/<N>/summary.md` の新規作成（co-explore 完遂の physical artifact）

**検知方法**: filesystem polling または inotifywait による生成検知

```bash
# CO-EXPLORE-COMPLETE: .explore/<N>/summary.md 生成を検知
CO_EXPLORE_COMPLETE_REGEX='\.explore/[^/]+/summary\.md'

# inotifywait 検知例（co-explore 完遂用）
# inotifywait -e create -r .explore/ --format '%w%f' | grep -E 'summary\.md$'

# filesystem polling 検知例
check_co_explore_complete() {
  local explore_dir="${1:-.explore}"
  local phase="${2:-}"
  if [[ -n "$phase" ]]; then
    [[ -f "${explore_dir}/${phase}/summary.md" ]] && echo "CO-EXPLORE-COMPLETE: ${phase}"
  else
    find "${explore_dir}" -name "summary.md" -newer "${explore_dir}/.last-check" 2>/dev/null \
      | while read -r f; do echo "CO-EXPLORE-COMPLETE: ${f}"; done
  fi
}
```

**co-explore 完遂後のアクション（MUST）**:

- `summary.md` 生成を検知したら **5 分以内に next-step 自律 spawn** する
- spawn 先: `co-issue`（子 Issue 起票）または次 Wave の Wave 計画更新
- postpone 判断は **user 明示指示時のみ**（詳細: `su-observer-wave-management.md`）

---

## PR merge 確認クエリ（正しい構文）

> **重要（Issue #948, R5）**: `gh pr list --search "linked-issue:N"` は GitHub CLI の正式構文ではない。
> 以下の正しい構文を使用すること。

```bash
# 推奨: body 中の Issue 番号を検索
ISSUE_NUM=948
gh pr list --search "in:body #${ISSUE_NUM}" --state merged

# より確実: jq で body フィルタリング
gh pr list --state merged --json number,body,mergedAt \
  -q ".[] | select(.body | test(\"#${ISSUE_NUM}(\\b|$)\"))"

# 特定 PR の merged 確認
gh pr view <PR_NUM> --json state,mergedAt -q '.state'
```

**誤った構文（使用禁止）:**
```bash
# NG: linked-issue は gh CLI の正式 syntax ではない
gh pr list --search "linked-issue:${ISSUE_NUM}"
# NG: body: は 'in:body' の代替ではない
gh pr list --search "body:#${ISSUE_NUM}"
```
