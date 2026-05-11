## Phase 4: 一括作成（Aggregate & Present）

#### Step 4a: 全 report.json 集約

`.controller-issue/<session-id>/per-issue/` 以下の全 `*/OUT/report.json` を Read し、以下に分類:

| 分類 | 判定条件 |
|------|---------|
| `fallback_inject_exhausted` | `status: "done"` かつ `fallback: true` かつ `reason` が `inject_exhausted_*` にマッチ（`done` より先に評価すること） |
| `done` | `status: "done"` |
| `warned` | `status: "done"` かつ `warnings_acknowledged` が非空 |
| `failed` | `status: "failed"` または `status: "codex_unreliable"` |
| `circuit_broken` | `status: "circuit_broken"` |

#### Step 4b: summary table 提示

以下のフォーマットで表示:

```
| # | Title (from draft.md) | Status | URL |
|---|----------------------|--------|-----|
| 1 | ...                  | done   | ... |
...
合計: done=N / warned=W / failed=F / circuit_broken=C / fallback_inject_exhausted=I
```

#### Step 4c: failure 対話

`failure`・`circuit_broken`・`fallback_inject_exhausted` が 1 件以上の場合、以下のフローで対応する:

**fallback_inject_exhausted の場合（[D] 自動適用）:**

Step 4a で `fallback_inject_exhausted` に分類された issue が存在する場合、[D] を自動実行する（ユーザー確認不要）。

**[D] direct specialist spawn — アーキテクチャ注記:**

[D] は inject_exhausted により Worker セッションが起動不能な場合の回復機構として、co-issue コントローラーが直接 Agent tool で specialist を spawn する。これは ADR-017 の通常 Pilot/Worker 隔離モデルの例外であり、inject_exhausted フォールバック時に限り許可される設計意図の下で実行する。spec-review-session-init.sh / PreToolUse gate（IM-7 層(b)）は適用されないが、以下の completeness guard が代替保証として機能する。

**[D] 実行手順（MUST）:**

1. **policies.json バリデーション**: 各 fallback_inject_exhausted issue の `per-issue/<index>/IN/policies.json` について以下を検証する。バリデーション失敗時は `[B] manual fix` に切り替える:
   - `specialists` キーが存在すること（必須）
   - 値が文字列配列（`string[]`）であること
   - 重複がないこと
   - 各要素が既知の specialist 名（`"worker-codex-reviewer"`, `"issue-critic"`, `"issue-feasibility"`）に含まれること

2. **全 specialist を並列 spawn**: `policies.json` の `specialists` 配列を読み込み、全 specialist を Agent tool で単一メッセージで並列 spawn する（省略・スキップ禁止）。`per-issue/<index>/IN/draft.md` を入力として各 specialist に渡す

3. **完了待ちとタイムアウト**: 全 specialist の完了を待つ（タイムアウト: specialist あたり 300 秒）。タイムアウトした specialist は `timed_out` として記録する

4. **completeness guard（MUST）**: 完了した specialist 名の集合（actual）と `policies.json["specialists"]` の集合（expected）を名前ベースで比較する:
   - `missing = expected - actual` が空でない場合: 不足 specialist を 1 回リトライ spawn する
   - リトライ後も不足の場合: `per-issue/<index>/OUT/report.json` に `{"status":"failed","reason":"specialist_missing","missing":[...]}` を書き込み `[B] manual fix` に移行する
   - **禁止**: `len(findings) >= len(specialists)` 等の findings 数による代替判定（findings=0 は正常実行と実行漏れを区別できないため）

5. **aggregate 実行**: 収集した specialist outputs を入力として `/twl:issue-review-aggregate` を Skill tool で呼び出す。結果を `per-issue/<index>/OUT/report.json` に書き込み（`status: "done"` または `circuit_broken`）、Step 4a の `done` / `failed` と同様に処理する

6. **Phase4-complete.json 生成** (ADR-024 Phase D): Step 5 で `done` に分類された issue について以下を実行する（生成失敗時は WARN のみで継続、hook/tool の evidence check に備えた意図的副作用）:

   ```bash
   # Phase4-complete.json 生成 (ADR-024 Phase D — refine 完了 evidence, phase4_path="[D]")
   PHASE4_DIR="${CONTROLLER_ISSUE_DIR:-.controller-issue}/${SESSION_ID:-${CO_ISSUE_SESSION_ID:-unknown}}"
   mkdir -p "$PHASE4_DIR"
   jq -n \
     --arg schema_version "1.0.0" \
     --arg sid "${SESSION_ID:-${CO_ISSUE_SESSION_ID:-unknown}}" \
     --argjson n "${ISSUE_NUMBER:-0}" \
     --arg repo "${TARGET_REPO:-unknown/repo}" \
     --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --argjson specialists "$(jq '.specialists // []' "${PER_ISSUE_DIR:-/dev/null}/IN/policies.json" 2>/dev/null || echo '[]')" \
     --arg report_path "${PER_ISSUE_DIR:-}/OUT/report.json" \
     --arg phase4_path "[D]" \
     '{schema_version: $schema_version, session_id: $sid, issue_number: $n, repo: $repo, completed_at: $completed_at, specialists: $specialists, report_path: $report_path, phase4_path: $phase4_path}' \
     > "${PHASE4_DIR}/Phase4-complete.json" \
     || printf '[%s] WARN phase4_marker_failed issue=#%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${ISSUE_NUMBER:-?}" >> /tmp/refined-status-update.log
   ```

   **設計注記**: [D] path は `spec-review-session-init.sh` の適用外であり `.spec-review-session-*.json` が存在しない。`Phase4-complete.json` を生成することで次の `board-status-update Refined` hook が allow される（意図した副作用、ADR-024 Phase D 参照）。

**failure / circuit_broken の場合（AskUserQuestion）:**

- `[A] retry subset` → 以下で非 done のみ再実行（env marker 必須 — ADR-037, 不変条件 P）:
  ```bash
  # Issue 作成は env marker 必須 (ADR-037)
  TWL_CALLER_AUTHZ=co-issue-phase4-create bash "${CLAUDE_PLUGIN_ROOT}/scripts/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir ".controller-issue/<session-id>/per-issue/" --resume --model sonnet
  ```
- `[B] manual fix` → Issue body 更新後、以下の決定論的 step を実行する（ADR-024 Phase B: Status=Refined SSoT）:

  ```bash
  # Phase4-complete.json 生成 (ADR-024 Phase D — refine 完了 evidence)
  PHASE4_DIR="${CONTROLLER_ISSUE_DIR:-.controller-issue}/${SESSION_ID:-${CO_ISSUE_SESSION_ID:-unknown}}"
  mkdir -p "$PHASE4_DIR"
  jq -n \
    --arg schema_version "1.0.0" \
    --arg sid "${SESSION_ID:-${CO_ISSUE_SESSION_ID:-unknown}}" \
    --argjson n "${ISSUE_NUMBER:-0}" \
    --arg repo "${TARGET_REPO:-unknown/repo}" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson specialists "$(jq '.specialists // []' "${PER_ISSUE_DIR:-/dev/null}/IN/policies.json" 2>/dev/null || echo '[]')" \
    --arg report_path "${PER_ISSUE_DIR:-}/OUT/report.json" \
    --arg phase4_path "[B]" \
    '{schema_version: $schema_version, session_id: $sid, issue_number: $n, repo: $repo, completed_at: $completed_at, specialists: $specialists, report_path: $report_path, phase4_path: $phase4_path}' \
    > "${PHASE4_DIR}/Phase4-complete.json" \
    || printf '[%s] WARN phase4_marker_failed issue=#%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${ISSUE_NUMBER:-?}" >> /tmp/refined-status-update.log

  # Status=Refined を設定（Phase B 移行後: Status only SSoT）
  bash "${SCRIPTS_ROOT:-plugins/twl/scripts}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined
  _status_exit=$?
  # observability: status update 失敗時のみ WARN
  if [[ "$_status_exit" -ne 0 ]]; then
    printf '[%s] WARN status_update_failed issue=#%s exit_code=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ISSUE_NUMBER" "$_status_exit" \
      >> /tmp/refined-status-update.log 2>/dev/null || true
  fi
  ```

  Status 更新完了後、ユーザーに修正箇所と完了を案内する。
- `[C] accept partial` → このまま完了（**ユーザーの明示的承認を確認してから実行すること**。デフォルト選択禁止）
