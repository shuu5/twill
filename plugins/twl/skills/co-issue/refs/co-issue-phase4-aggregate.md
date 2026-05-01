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

**failure / circuit_broken の場合（AskUserQuestion）:**

- `[A] retry subset` → `bash scripts/issue-lifecycle-orchestrator.sh --per-issue-dir ".controller-issue/<session-id>/per-issue/" --resume --model sonnet` で非 done のみ再実行
- `[B] manual fix` → Issue body 更新後、以下の決定論的 dual-write step を実行する（ADR-024 dual-write 順序準拠: label 先 → Status 後）:

  ```bash
  # (a-pre) idempotent auto-create（ADR-024 Phase 1; Phase B 移行で削除予定）
  # refined label 不在時に --add-label が失敗して Status=Refined 移行が skip される連鎖を断つ（#1209）
  gh label create refined --color "C2E0C6" --description "auto-created by co-issue manual fix [B]" --repo "$ISSUE_REPO" 2>/dev/null || true

  # (a) label 先に付与（ADR-024: label 先 → Status 後）。|| true で add-label 失敗時も (b) へ継続する
  gh issue edit "$ISSUE_NUMBER" --repo "$ISSUE_REPO" --add-label refined 2>/dev/null || true

  # (b) Status を後に更新（ADR-024: label 完了後に実行）
  bash "${SCRIPTS_ROOT:-plugins/twl/scripts}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined
  ```

  dual-write 完了後、ユーザーに修正箇所と完了を案内する。
- `[C] accept partial` → このまま完了（**ユーザーの明示的承認を確認してから実行すること**。デフォルト選択禁止）
