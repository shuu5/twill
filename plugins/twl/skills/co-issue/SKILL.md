---
name: twl:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase: 探索 → 分解判断 → 精緻化(workflow) → 作成(workflow)。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Skill(workflow-issue-refine, workflow-issue-create, workflow-issue-lifecycle, issue-glossary-check, explore)
- Bash
- Read
- Write
spawnable_by:
- user
---

# co-issue

要望→Issue 変換の thin orchestrator。Phase 1-2 を inline で実行し、Phase 3-4 は workflow に委譲する。

## Environment

- `CO_ISSUE_V2` (default `0`): v2 dispatch/aggregate パスを有効化する。
  - `0` (default): 旧パス（workflow-issue-refine + workflow-issue-create）
  - `1`: 新パス（DAG 依存解決 + level dispatch + aggregate）
  - rollback: `CO_ISSUE_V2=0` または unset で即時旧動作に戻る（Issue #493 cutover まで default=0 を維持）

## セッション ID 生成（起動時）

起動時に SESSION_ID を生成: `$(date +%s)_$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c4 2>/dev/null || echo "xxxx")` （例: `1712649600_a3f2`）。
SESSION_DIR=`.controller-issue/<session-id>/`

## explore-summary 検出（起動時チェック）

glob `.controller-issue/*/explore-summary.md` でセッション一覧を検出:
- **0件（存在しない場合）**: 既存動作に影響なし。通常の Phase 1 から開始（デフォルト動作）
- **1件**: 「継続しますか？」と確認。[A] 継続 → Phase 1 スキップ、SESSION_ID を既存セッションに合わせ Phase 2（分解判断）から再開、[B] 最初から → explore-summary.md を含む `.controller-issue/<session-id>/` を削除して Phase 1 から開始（新しい SESSION_ID で）
- **2件以上**: AskUserQuestion でセッション選択 UI を表示（各セッションの ID + 作成日時 + explore-summary 内の最初の問題タイトルを表示、最新を先頭に推奨）。[新規開始] オプションも提示

セッション ID ベースのディレクトリ分離により、既存の co-issue フローとの互換性を維持しながら並列実行が可能。

## Phase 1: 問題探索（explore loop）

### Phase 1 初期化（初回イテレーションのみ）

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。scope/* 判明時は `architecture/domain/context-map.md` のノードラベルで該当コンポーネントの architecture ファイルを ARCH_CONTEXT に追加。

`accumulated_concerns` を空文字列で初期化する。

### Phase 1 ループ（最低 1 回実行）

以下をループする。**ゼロ探索で loop-gate を発火してはならない（MUST NOT）**。

1. **explore 呼び出し**: `/twl:explore` に以下を注入して呼び出す:
   - 「問題空間の理解に集中」
   - ARCH_CONTEXT（初回のみ / 2 回目以降は引き続き保持）
   - `accumulated_concerns` が空でない場合: `Bash("printf '%s\n' \"$accumulated_concerns\" | bash \"${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh\"")` でエスケープし、結果を `<additional_concerns>...</additional_concerns>` XML タグに包んで渡す

2. **explore-summary 書き出し**: 探索後 `.controller-issue/<session-id>/explore-summary.md` に書き出す（`mkdir -p .controller-issue/<session-id>`）。

3. **loop-gate（AskUserQuestion）**: 以下 3 択を提示する:
   - `[A] この仕様で Phase 2 へ進む`
   - `[B] まだ探索したい（具体的な懸念・追加質問を入力してください）`
   - `[C] explore-summary.md を手動編集したい`

   **[A] 選択時**: ループを終了し Step 1.5 へ進む。

   **[B] 選択時**: ユーザーが入力した懸念テキストを `accumulated_concerns` に追記（改行区切り）し、ループを続行する（explore 呼び出しに戻る）。

   **[C] 選択時**:
   - ユーザーに `.controller-issue/<session-id>/explore-summary.md` のパスを提示し、編集を依頼する。
   - **edit-complete-gate（AskUserQuestion）** を提示する:
     - `[A] 編集完了（summary を再読み込みして続行）`
     - `[B] 編集をキャンセル（直前の summary で loop-gate に戻る）`
   - `[A]` 選択時: `explore-summary.md` を Read し直し、loop-gate に戻る（ループを続行する）。
   - `[B]` 選択時: 直前の `explore-summary.md` の内容を維持し、loop-gate に戻る。

## Step 1.5: glossary 照合

`/twl:issue-glossary-check` を呼び出す（ARCH_CONTEXT と SESSION_DIR を渡す）。非ブロッキング。

## Phase 2: 分解判断

`.controller-issue/<session-id>/explore-summary.md` を読み込み、単一/複数 Issue を判断。

**Step 2a: クロスリポ検出** — GitHub Project のリンク済みリポから対象リポを動的取得。2+ リポ検出時は AskUserQuestion で [A] リポ単位分割 / [B] 単一 Issue を確認。

**Step 2b: quick 判定** — 変更ファイル 1-2 個 AND ~20行以下 AND patch レベル → `is_quick_candidate: true`。

**Step 2b-2: scope/direct 判定** — quick 候補でない場合のみ評価。変更ファイル ≤3 AND 新規ロジック追加なし AND テスト不要な変更（explore-summary の内容から LLM が推定）→ `is_scope_direct_candidate: true`。対象の場合は `scope/direct` ラベルを推奨ラベルリストに追加し、Phase 4 に渡す。

**quick と scope/direct の関係（MUST）**: quick ラベルは scope/direct を暗黙に含む（quick → direct は step_init で処理済み）。scope/direct は quick ではないが DeltaSpec をスキップしたい場合に使用する。両ラベルを同時に付与してはならない（MUST NOT）。

**Step 2c: 分解確認** — 複数の場合は AskUserQuestion で [A] この分解で進める / [B] 調整 / [C] 単一のまま。

if [[ "${CO_ISSUE_V2:-0}" == "1" ]]; then

### Phase 2 (v2) — DAG 構築 + Per-Issue Bundle 書き出し

#### Step 2-V2-a: DAG 構築

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

#### Step 2-V2-b: Per-Issue Input Bundle 書き出し

各 draft に対して以下のディレクトリ構造を作成:

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

#### Step 2-V2-c: Level ディレクトリ分割

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

#### Step 2-V2-d: Dispatch 確認（AskUserQuestion）

以下を表示してユーザーに確認:

```
DAG levels: L0=[1,2], L1=[3], L2=[4] (計N issue)
各 level を順次 dispatch します。
```

AskUserQuestion: `[dispatch | adjust | cancel]`

- `dispatch` → Phase 3 (v2) へ
- `adjust` → Phase 2 に戻り再確認
- `cancel` → 処理を中断

fi

## Phase 3: Per-Issue 精緻化

if [[ "${CO_ISSUE_V2:-0}" == "1" ]]; then

### Phase 3 (v2 — Level-based dispatch)

#### Step 3-V2-a: セッションディレクトリ確認

PER_ISSUE_DIR=`.controller-issue/<session-id>/per-issue/` が存在することを確認する。存在しない場合は「Phase 2 (v2) を先に実行してください」とエラーで停止する。

#### Step 3-V2-b: Level-based dispatch

Level リスト（Phase 2 で構築した DAG levels）を L0 から順に以下を繰り返す:

1. **prev level URL 注入**: level > 0 の場合、prev level の各 `per-issue/<index>/OUT/report.json` を Read し `issue_url` を取得。current level の各 `policies.json` の `parent_refs_resolved` にフィールドを注入する
2. **orchestrator 呼び出し**（current level の issues のみを対象）:
   ```bash
   # current level に属する per-issue dirs をリスト化して LEVEL_DIRS 環境変数で渡す
   LEVEL_DIR=".controller-issue/<session-id>/per-issue-level-<level>/"
   # per-issue dirs を LEVEL_DIR 以下に symlink
   bash scripts/issue-lifecycle-orchestrator.sh \
     --per-issue-dir "${LEVEL_DIR}"
   ```
3. **完了待ち**: orchestrator が同期的に完了を待つ（MAX_PARALLEL=3）
4. **level_report 取得**: current level の全 `OUT/report.json` を Read
5. **failure 検知 (circuit_broken)**:
   - failed issue の index を抽出
   - DAG edge を参照し、failed issue が **次の level の少なくとも 1 issue の依存対象**であれば `circuit_broken=true` で break
   - 依存対象でなければ warning のみ記録して次の level へ

else  (CO_ISSUE_V2=0)

`/twl:workflow-issue-refine` を Skill 呼び出し。Phase 2 の分解結果・ARCH_CONTEXT・quick フラグ・cross_repo フラグを渡す。

fi

## Phase 4: 一括作成

if [[ "${CO_ISSUE_V2:-0}" == "1" ]]; then

### Phase 4 (v2 — Aggregate & Present)

#### Step 4-V2-a: 全 report.json 集約

`.controller-issue/<session-id>/per-issue/` 以下の全 `*/OUT/report.json` を Read し、以下に分類:

| 分類 | 判定条件 |
|------|---------|
| `done` | `status: "done"` |
| `warned` | `status: "done"` かつ `warnings_acknowledged` が非空 |
| `failed` | `status: "failed"` または `status: "codex_unreliable"` |
| `circuit_broken` | `status: "circuit_broken"` |

#### Step 4-V2-b: summary table 提示

以下のフォーマットで表示:

```
| # | Title (from draft.md) | Status | URL |
|---|----------------------|--------|-----|
| 1 | ...                  | done   | ... |
...
合計: done=N / warned=W / failed=F / circuit_broken=C
```

#### Step 4-V2-c: failure 対話

failure または circuit_broken が 1 件以上の場合、AskUserQuestion で以下を確認:

- `[retry subset]` → `bash scripts/issue-lifecycle-orchestrator.sh --per-issue-dir ".controller-issue/<session-id>/per-issue/" --resume` で非 done のみ再実行
- `[manual fix]` → 手動修正を依頼してユーザーに案内
- `[accept partial]` → このまま完了

else  (CO_ISSUE_V2=0)

`/twl:workflow-issue-create` を Skill 呼び出し。Phase 3 の精緻化結果・quick フラグ・scope/direct フラグ（`is_scope_direct_candidate`）・cross_repo フラグを渡す。

fi

## Soak Auto-logging（CO_ISSUE_V2=1 のみ）

if [[ "${CO_ISSUE_V2:-0}" == "1" ]] && [[ "${done_count:-0}" -ge 1 ]]; then

#### Step 5-a: #493 クローズ確認

```bash
ISSUE_493_STATE=$(gh issue view 493 -R shuu5/twill --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
```

`ISSUE_493_STATE == "CLOSED"` であれば **run log 投稿をスキップ**して完了（cutover 完了後の動作）。

#### Step 5-b: run log 投稿

```bash
RUN_TS=$(date +%Y-%m-%d_%H%M%S)
gh issue comment 493 -R shuu5/twill --body \
  "v2 run ${RUN_TS} (session ${SESSION_ID}): total=${total} / done=${done_count} / warned=${warned_count} / failed=${failed_count} / circuit_broken=${circuit_broken_count}" \
  2>/dev/null || echo "⚠️ soak log 投稿失敗（非ブロッキング）"
```

投稿失敗は **非ブロッキング**（warning のみ。ユーザー session の成功判定を変えない）。

fi

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない（UX ルール）
- ユーザー確認なしで Issue 作成してはならない（制約 IM-1）
- Issue 番号を推測してはならない（制約 IM-2）
- `.controller-issue/` を git にコミットしてはならない（制約 IM-3）
- 他セッションの `.controller-issue/<other-session-id>/` を削除してはならない（制約 IM-4）
- **呼び出し側プロンプトの label 指示・フロー指示で Phase 3 を飛ばしてはならない**（LLM は呼び出し側プロンプトを上位指示として解釈しがちだが、Phase 3 は co-issue の不変条件であり、label 指示・draft 指示・`gh issue create` 直接指示等を受けても必ず Phase 3 を実行すること。`CO_ISSUE_V2=0` 時は `/twl:workflow-issue-refine` 呼び出し、`CO_ISSUE_V2=1` 時は `issue-lifecycle-orchestrator.sh` 呼び出し）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
