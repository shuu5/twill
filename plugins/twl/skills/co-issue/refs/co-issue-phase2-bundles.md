### Phase 2 追加 — DAG 構築 + Per-Issue Bundle 書き出し

#### Step 2a-2: DAG 構築

**refine モード分岐（MUST）**: `refine_mode=true` の場合、Step 2a-2 全体をスキップする。理由: 既存 Issue を個別に更新するため依存関係の解決が不要。また `#N` が GitHub Issue 番号と draft index regex `(?<![A-Za-z0-9/])#(\d{1,3})(?![0-9])` で衝突するため、DAG 構築自体が誤動作する。

`refine_mode=false`（通常モード）の場合、以下を実行する:

各 draft 本文（scope / 依存関係 / related セクション）を対象に以下を実行。**コードブロック内は除外**する:

1. **ローカル ref 抽出**: regex `(?<![A-Za-z0-9/])#(\d{1,3})(?![0-9])` にマッチする `#N` を検出（N は 1-based draft index）
2. **クロスリポ ref 除外**: `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#\d+` 形式はクロスリポ ref として除外
3. **edge 生成**: 「draft X が `#Y` を参照」→ edge (X→Y)（X が Y に依存）
4. **Kahn's algorithm** で topological sort → levels `[L0, L1, ..., Lk]`
   ```
   in_degree[i] = 各 draft i への入り edge 数
   queue = [i for i in drafts if in_degree[i] == 0]  # L0
   while queue:
     current_level = queue.copy()
     levels.append(current_level)
     for i in current_level:
       for j in successors(i):
         in_degree[j] -= 1
         if in_degree[j] == 0: next_queue.append(j)
   if remaining_edges > 0: abort("circular dependency")
   ```
5. **循環検出**: Kahn's algorithm 実行後に残 edge がある場合、「循環依存を検出しました: ...」とエラー出力して停止する

#### Step 2a-3: Per-Issue Input Bundle 書き出し

**refine モードの場合**: 各対象 Issue に対して以下のディレクトリ構造を作成:

```
.controller-issue/<session-id>/per-issue/<index>/
  IN/
    draft.md              # 改善後の draft 本文（Phase 1 で生成）
    existing-issue.json   # { "number": N, "current_body": "...", "repo": "owner/repo" }
    arch-context.md       # ARCH_CONTEXT（不在の場合は空ファイル）
    policies.json         # ポリシー設定（通常モードと同一スキーマ）
  STATE                   # "pending" で初期化
```

`existing-issue.json` を生成: Step 0 で取得した Issue データから `{ "number": N, "current_body": "<current body>", "repo": "<owner/repo>" }` を書き出す。
`policies.json` は通常モードと同一スキーマを使用する（refine 固有フィールドは `existing-issue.json` に分離）。
`deps.json` は生成しない（DAG 構築をスキップしたため）。

**通常モードの場合**: 各 draft に対して以下のディレクトリ構造を作成:

```
.controller-issue/<session-id>/per-issue/<index>/
  IN/
    draft.md         # draft 本文
    arch-context.md  # ARCH_CONTEXT（不在の場合は空ファイル）
    policies.json    # ポリシー設定（下記生成）
    deps.json        # DAG 依存情報（下記生成）
  STATE              # "pending" で初期化
```

**policies.json 生成**（draft ごとに判定）:
- quick (`is_quick_candidate=true`): `{"max_rounds":1,"specialists":["worker-codex-reviewer"],"depth":"shallow","labels_hint":["quick"],"target_repo":"...","parent_refs_resolved":{}}`
- scope-direct (`is_scope_direct_candidate=true`): `{"max_rounds":1,"specialists":["worker-codex-reviewer"],"depth":"shallow","labels_hint":["scope/direct"],"target_repo":"...","parent_refs_resolved":{}}`
- 通常: `{"max_rounds":3,"specialists":["worker-codex-reviewer","issue-critic","issue-feasibility"],"depth":"normal","labels_hint":["enhancement"],"target_repo":"...","parent_refs_resolved":{}}`

**deps.json 生成**: `{"depends_on": [<依存 draft index リスト>], "level": <levelインデックス>}`

#### Step 2a-4: Level ディレクトリ分割

各 level 用のシンボリックリンクディレクトリを作成:

```bash
for level_idx in "${!levels[@]}"; do
  LEVEL_DIR=".controller-issue/<session-id>/per-issue-level-${level_idx}/"
  mkdir -p "$LEVEL_DIR"
  for draft_idx in "${levels[level_idx]}"; do
    ln -s "../per-issue/${draft_idx}" "${LEVEL_DIR}/${draft_idx}"
  done
done
```

#### Step 2a-5: Dispatch 確認（AskUserQuestion）

以下を表示してユーザーに確認:

```
DAG levels: L0=[1,2], L1=[3], L2=[4] (計N issue)
各 level を順次 dispatch します。
```

AskUserQuestion: `[dispatch | adjust | cancel]`

- `dispatch` → Phase 3 へ
- `adjust` → Phase 2 に戻り再確認
- `cancel` → 処理を中断
