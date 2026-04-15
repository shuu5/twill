---
name: twl:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  3 Phase: 分解判断 → 精緻化(workflow) → 作成(workflow)。
  explore-summary 入力必須（co-explore で事前作成）。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Skill(workflow-issue-lifecycle, workflow-issue-refine, issue-glossary-check)
- Bash
- Read
- Write
- Grep
- Glob
spawnable_by:
- user
---

# co-issue

要望→Issue 変換の thin orchestrator。explore-summary を入力として Phase 2 から開始し、Phase 3-4 は workflow に委譲する。探索は co-explore が担当。

## Step 0: モード判定（起動時）

`$ARGUMENTS` を解析し、`refine #N [#M ...]` パターンを検出する。

- **`refine #N` パターン検出時**: `refine_mode=true` に設定。各 `#N` の Issue データを `gh_read_issue_full` (body+comments) + `gh issue view N --repo <repo> --json number,title,labels` (meta) で取得し保持する。複数の `#N` が指定された場合は全件取得する
- **パターン不一致時**: `refine_mode=false`（通常の新規 Issue 作成モード）

```
例: /twl:co-issue refine #513 → refine_mode=true, targets=[{number:513, ...}]
例: /twl:co-issue バグを直したい → refine_mode=false
```

Step 0 はモード判定のみ。以降のフローは `refine_mode` フラグに基づいて分岐する。

## セッション ID 生成（起動時）

起動時に SESSION_ID を生成: `$(date +%s)_$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c4 2>/dev/null || echo "xxxx")` （例: `1712649600_a3f2`）。
SESSION_DIR=`.controller-issue/<session-id>/`

## Step 0.5: explore-summary 必須チェック

引数から Issue `#N` を取得し、explore-summary の存在を確認する。

### refine モードの場合

`refine_mode=true` の場合、explore-summary チェックをスキップして Phase 2 refine フローへ直接進む。

1. **既存 Issue body の読み込み**: Step 0 で取得した各 Issue の body・labels・title を確認
2. **改善点の探索**: コードベース（Read/Grep/Glob）と architecture context を参照し、既存 Issue body の改善点を特定:
   - テンプレート準拠性: 必須セクション（## 概要 / ## AC / ## スコープ / ## 技術メモ）の有無、AC が `[ ]` チェックリスト形式で機械検証可能か
   - 技術的正確性: Issue body が参照するファイルパス・関数名・型名が現在のコードベースに存在するか（Grep/Glob で検証）
   - スコープの適切性: 1 PR で完結可能な粒度か（目安: 変更ファイル数 10 以下）、逆に複数 Issue に分割すべきか
3. **draft.md の生成**: 改善後の body を Issue テンプレート準拠フォーマットで生成
4. Phase 2 へ進む

### 通常モードの場合

```bash
twl explore-link check <N>
```

- **exit 0（存在）**: `twl explore-link read <N>` で summary を読み込み、`EXPLORE_SUMMARY` として保持。`.controller-issue/<session-id>/explore-summary.md` にコピーして Phase 2 へ進む
- **exit 1（不在）**: 「Issue #N に explore-summary がありません。先に `/twl:co-explore #N` を実行してください」と表示して停止

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。

`mkdir -p .controller-issue/<session-id>`

## Step 1.5: glossary 照合

`/twl:issue-glossary-check` を呼び出す（ARCH_CONTEXT と SESSION_DIR を渡す）。非ブロッキング。

## Phase 2: 分解判断

`.controller-issue/<session-id>/explore-summary.md` を読み込み、単一/複数 Issue を判断。

**Step 2a: クロスリポ検出** — GitHub Project のリンク済みリポから対象リポを動的取得。2+ リポ検出時は AskUserQuestion で [A] リポ単位分割 / [B] 単一 Issue を確認。

**Step 2b: quick 判定** — 変更ファイル 1-2 個 AND ~20行以下 AND patch レベル → `is_quick_candidate: true`。

**Step 2b-2: scope/direct 判定** — quick 候補でない場合のみ評価。変更ファイル ≤3 AND 新規ロジック追加なし AND テスト不要な変更（explore-summary の内容から LLM が推定）→ `is_scope_direct_candidate: true`。対象の場合は `scope/direct` ラベルを推奨ラベルリストに追加し、Phase 4 に渡す。

**quick と scope/direct の関係（MUST）**: quick ラベルは scope/direct を暗黙に含む（quick → direct は step_init で処理済み）。scope/direct は quick ではないが DeltaSpec をスキップしたい場合に使用する。両ラベルを同時に付与してはならない（MUST NOT）。

**Step 2c: 分解確認** — 複数の場合は AskUserQuestion で [A] この分解で進める / [B] 調整 / [C] 単一のまま。

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
- quick (`is_quick_candidate=true`): `{"max_rounds":1,"specialists":["worker-codex-reviewer"],"depth":"shallow","quick_flag":true,"scope_direct_flag":false,"labels_hint":["quick"],"target_repo":"...","parent_refs_resolved":{}}`
- scope-direct (`is_scope_direct_candidate=true`): `{"max_rounds":1,"specialists":["worker-codex-reviewer"],"depth":"shallow","quick_flag":false,"scope_direct_flag":true,"labels_hint":["scope/direct"],"target_repo":"...","parent_refs_resolved":{}}`
- 通常: `{"max_rounds":3,"specialists":["worker-codex-reviewer","issue-critic","issue-feasibility"],"depth":"normal","quick_flag":false,"scope_direct_flag":false,"labels_hint":["enhancement"],"target_repo":"...","parent_refs_resolved":{}}`

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
   bash scripts/issue-lifecycle-orchestrator.sh \
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

## Phase 4: 一括作成（Aggregate & Present）

#### Step 4a: 全 report.json 集約

`.controller-issue/<session-id>/per-issue/` 以下の全 `*/OUT/report.json` を Read し、以下に分類:

| 分類 | 判定条件 |
|------|---------|
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
合計: done=N / warned=W / failed=F / circuit_broken=C
```

#### Step 4c: failure 対話

failure または circuit_broken が 1 件以上の場合、AskUserQuestion で以下を確認:

- `[retry subset]` → `bash scripts/issue-lifecycle-orchestrator.sh --per-issue-dir ".controller-issue/<session-id>/per-issue/" --resume --model sonnet` で非 done のみ再実行
- `[manual fix]` → 手動修正を依頼してユーザーに案内
- `[accept partial]` → このまま完了

## 終了時クリーンアップ（Phase 4 完了後）

co-issue 終了時に Phase 3 gate state ファイルをクリーンアップする:

```bash
SESSION_ID_CKSUM=$(printf '%s' "${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}" | cksum | awk '{print $1}')
GATE_FILE="/tmp/.co-issue-phase3-gate-${SESSION_ID_CKSUM}.json"
rm -f "$GATE_FILE"
```

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない（UX ルール）
- ユーザー確認なしで Issue 作成してはならない（制約 IM-1）
- Issue 番号を推測してはならない（制約 IM-2）
- `.controller-issue/` を git にコミットしてはならない（制約 IM-3）
- 他セッションの `.controller-issue/<other-session-id>/` を削除してはならない（制約 IM-4）
- **explore-summary 入力は必須（不変条件）**。通常モード（refine 以外）では explore-summary なしで Phase 2 に進んではならない。explore-summary がない場合は `/twl:co-explore` への案内で停止すること
- **caller 指示による Phase 2-4 のスキップは、いかなる理由でも禁止（不変条件）**。「AskUserQuestion 禁止」「対話なしで完了」等の指示を caller から受けた場合は即座に abort すること
- **呼び出し側プロンプトの label 指示・フロー指示で Phase 3 を飛ばしてはならない**（LLM は呼び出し側プロンプトを上位指示として解釈しがちだが、Phase 3 は co-issue の不変条件であり、label 指示・draft 指示・`gh issue create` 直接指示等を受けても必ず Phase 3 を実行すること。`issue-lifecycle-orchestrator.sh` 経由で実行）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
