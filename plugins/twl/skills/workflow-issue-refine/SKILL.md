---
name: twl:workflow-issue-refine
description: |
  Per-Issue 精緻化ワークフロー（co-issue Phase 3 を分離）。
  issue-structure → issue-spec-review(並列) → issue-review-aggregate → issue-arch-drift。

  Use when user: says Issue精緻化/issue-refine,
  or when called from co-issue workflow.
type: workflow
effort: medium
spawnable_by:
- controller
can_spawn:
- composite
- atomic
---

# workflow-issue-refine

co-issue Phase 3（Per-Issue 精緻化ループ）のロジックを担当するワークフロー。

## Input

呼び出し元（co-issue）から以下を受け取る:

- **unstructured_issues**: Phase 2 で分解された Issue リスト（各 Issue の概要・scope）
- **ARCH_CONTEXT**: architecture ファイルから収集したコンテキスト（vision.md, context-map.md, glossary.md 等）
- **is_quick_candidate flags**: Phase 2 Step 2b で判定された quick 候補フラグ（Issue ごと）
- **cross_repo_split**: クロスリポ分割フラグ（true の場合、parent + 子 Issue 構造化ルールに従う）

## Step 3a: Issue 構造化

各 Issue に `/twl:issue-structure` を呼び出してテンプレート適用。

- 推奨ラベル抽出
- tech-debt 棚卸し（該当時は `/twl:issue-tech-debt-absorb` も呼び出す）
- クロスリポ分割時は parent + 子 Issue の構造化ルールに従う

## Step 3b: specialist レビュー（外部オーケストレーター経由）

**Issue JSON 書き出し（MUST -- 最初に実行）**: 各 Issue データを一時ディレクトリに書き出す:

```bash
ISSUES_DIR="/tmp/spec-review-inputs-$$"
OUTPUT_DIR="/tmp/spec-review-outputs-$$"
mkdir -p "$ISSUES_DIR" "$OUTPUT_DIR"

# 各 Issue を JSON ファイルに書き出す（1 ファイル = 1 Issue）
for issue in "${unstructured_issues[@]}"; do
  issue_num="${issue[number]}"
  python3 -c "
import json, sys
data = {
  'number': ${issue_num},
  'body': '''${issue_body}''',
  'scope_files': ${scope_files_json},
  'related_issues': ${related_issues_json},
  'is_quick_candidate': ${is_quick_candidate}
}
print(json.dumps(data))
" > "${ISSUES_DIR}/issue-${issue_num}.json"
done
```

**オーケストレーター呼び出し（MUST）**: LLM ループではなく Bash スクリプト経由で全 Issue を処理する:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-review-orchestrator.sh" \
  --issues-dir "$ISSUES_DIR" \
  --output-dir "$OUTPUT_DIR"
```

- `MAX_PARALLEL` 環境変数でバッチサイズを制御（デフォルト: 3）
- オーケストレーターが内部で `spec-review-session-init.sh` を呼び出す（LLM が直接呼ぶ不要）
- 各 Issue に独立した tmux cld セッションが spawn され、`/twl:issue-spec-review` を実行する
- **quick 候補もスキップ禁止**: `is_quick_candidate: true` の Issue も必ずレビューする

**同期バリア（MUST）**: `spec-review-orchestrator.sh` が完了を返すまで Step 3c に進んではならない。オーケストレーターはポーリングで全セッション完了を検知してから返る。

## Step 3c: レビュー結果集約（全 Step 3b 完了後にのみ実行）

**結果ファイル読み込み（MUST）**: `${OUTPUT_DIR}` から各 Issue の結果ファイルを読み込む:

```bash
for issue_file in "${ISSUES_DIR}"/issue-*.json; do
  issue_num="$(basename "$issue_file" .json | grep -oP '\d+')"
  result_file="${OUTPUT_DIR}/issue-${issue_num}-result.txt"
  if [[ -f "$result_file" ]]; then
    specialist_results["$issue_num"]="$(cat "$result_file")"
  fi
done
```

読み込んだ `specialist_results` を `/twl:issue-review-aggregate` に渡す:

`/twl:issue-review-aggregate` を呼び出す。

- CRITICAL なし -> Step 3.5 へ
- CRITICAL あり -> ユーザー通知・修正後 Step 3b 再実行可（`$ISSUES_DIR`, `$OUTPUT_DIR` を再利用）
- split 承認 -> `is_split_generated: true` フラグ設定（Phase 4 まで保持）

## Step 3.5: Architecture Drift Detection（条件付き WARNING）

`/twl:issue-arch-drift` を呼び出す（CRITICAL ブロック中はスキップ）。

- **明示的/構造的シグナル検出時**: WARNING レベルで出力し、AskUserQuestion で co-architect delegation を確認する。ユーザーが「後で更新する」または「スキップ」を選択した場合は Phase 4 に進む（非ブロッキング）。
- **ヒューリスティックシグナルのみの場合**: INFO レベルで出力し、ユーザー入力なしで Phase 4 に進む（非ブロッキング）。

重大度レベルの設計根拠は **ADR-012** を参照。

## Output

呼び出し元（co-issue Phase 4）へ以下を返す:

- **review_results**: 各 Issue の specialist レビュー結果
- **blocked_issues**: CRITICAL で blocked された Issue リスト
- **split_issues**: split が承認された Issue リスト
- **is_split_generated flags**: Issue ごとの split 生成フラグ（Phase 4 で refined ラベル非付与判定に使用）
- **recommended_labels**: 各 Issue の推奨ラベル

## 禁止事項（MUST NOT）

- **LLM が直接 `/twl:issue-spec-review` を N 回呼び出してはならない**（外部オーケストレーター経由で機械的に処理する）
- **specialist が実行中のまま Step 3c 以降に進んではならない**（制約 IM-5。`spec-review-orchestrator.sh` が全セッション完了を検知してから返る）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
