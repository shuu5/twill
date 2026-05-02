## Phase 3: Per-Issue 精緻化（Level-based dispatch）

#### Step 3a-pre: Phase 3 gate state 書き込み（Layer C-2）

Phase 3 開始直前に gate state を書き込む:

```bash
SESSION_ID_CKSUM=$(printf '%s' "${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}" | cksum | awk '{print $1}')
GATE_FILE="/tmp/.co-issue-phase3-gate-${SESSION_ID_CKSUM}.json"
printf '{"phase3_completed":false,"session_id_cksum":"%s"}\n' "$SESSION_ID_CKSUM" > "$GATE_FILE"
```

#### Step 3a: セッションディレクトリ確認

PER_ISSUE_DIR=`.controller-issue/<session-id>/per-issue/` が存在することを確認する。存在しない場合は「Phase 2 (v2) を先に実行してください」とエラーで停止する。

#### Step 3b: Level-based dispatch

Level リスト（Phase 2 で構築した DAG levels）を L0 から順に以下を繰り返す:

1. **prev level URL 注入**: level > 0 の場合、prev level の各 `per-issue/<index>/OUT/report.json` を Read し `issue_url` を取得。current level の各 `policies.json` の `parent_refs_resolved` にフィールドを注入する
2. **orchestrator 呼び出し**（current level の issues のみを対象）:
   ```bash
   # current level に属する per-issue dirs をリスト化して LEVEL_DIRS 環境変数で渡す
   LEVEL_DIR=".controller-issue/<session-id>/per-issue-level-<level>/"
   # per-issue dirs を LEVEL_DIR 以下に symlink
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/issue-lifecycle-orchestrator.sh" \
     --per-issue-dir "${LEVEL_DIR}" \
     --model sonnet
   ```
3. **完了待ち**: orchestrator が同期的に完了を待つ（MAX_PARALLEL=3）
4. **level_report 取得**: current level の全 `OUT/report.json` を Read
5. **failure 検知 (circuit_broken)**:
   - failed issue の index を抽出
   - DAG edge を参照し、failed issue が **次の level の少なくとも 1 issue の依存対象**であれば `circuit_broken=true` で break
   - 依存対象でなければ warning のみ記録して次の level へ

#### Step 3d: Phase 3 gate state 解除（Layer C-2）

全 level の orchestrator 完了後、gate state を解除する:

```bash
SESSION_ID_CKSUM=$(printf '%s' "${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}" | cksum | awk '{print $1}')
GATE_FILE="/tmp/.co-issue-phase3-gate-${SESSION_ID_CKSUM}.json"
if [[ -f "$GATE_FILE" && ! -L "$GATE_FILE" ]]; then
  printf '{"phase3_completed":true,"session_id_cksum":"%s"}\n' "$SESSION_ID_CKSUM" > "$GATE_FILE"
fi
```
