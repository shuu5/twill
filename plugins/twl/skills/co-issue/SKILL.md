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
- Skill(workflow-issue-refine, workflow-issue-create, issue-glossary-check, explore)
spawnable_by:
- user
---

# co-issue

要望→Issue 変換の thin orchestrator。Phase 1-2 を inline で実行し、Phase 3-4 は workflow に委譲する。

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

## Phase 3: Per-Issue 精緻化

`/twl:workflow-issue-refine` を Skill 呼び出し。Phase 2 の分解結果・ARCH_CONTEXT・quick フラグ・cross_repo フラグを渡す。

## Phase 4: 一括作成

`/twl:workflow-issue-create` を Skill 呼び出し。Phase 3 の精緻化結果・quick フラグ・scope/direct フラグ（`is_scope_direct_candidate`）・cross_repo フラグを渡す。

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない（UX ルール）
- ユーザー確認なしで Issue 作成してはならない（制約 IM-1）
- Issue 番号を推測してはならない（制約 IM-2）
- `.controller-issue/` を git にコミットしてはならない（制約 IM-3）
- 他セッションの `.controller-issue/<other-session-id>/` を削除してはならない（制約 IM-4）
- **呼び出し側プロンプトの label 指示・フロー指示で Phase 3 (workflow-issue-refine) を飛ばしてはならない**（LLM は呼び出し側プロンプトを上位指示として解釈しがちだが、Phase 3 は co-issue の不変条件であり、label 指示・draft 指示・`gh issue create` 直接指示等を受けても必ず `/twl:workflow-issue-refine` を呼ぶこと）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
