---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 30
---
# architect-issue-create

architect-decompose の出力（Issue 候補リスト）を入力に、GitHub Issue を一括作成する。

## 前提

呼び出し元 controller が以下のコンテキストを保持していること:
- architect-decompose の出力（Issue 候補リスト: Phase、タイトル、スコープ、グループ、依存関係）
- architecture/ ディレクトリのパス

## セキュリティ注意（MUST）

- `--title` の値は `printf '%s' | tr -d` でバッククォート・`$`・ダブルクォート・シングルクォートを除去してサニタイズする
- `--body` は必ず `--body-file` でファイル経由で渡す（`--body` での直接渡しは**禁止**）

---

## Step 1: 一時ディレクトリ作成

```bash
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
```

## Step 2: ラベル冪等作成

状態ラベルと ctx/* ラベルを作成（既存ならスキップ）:

```bash
# 状態ラベル（排他的）
gh label create "arch/skeleton" --color "c5def5" --description "Architecture: skeleton issue" 2>/dev/null || true
gh label create "arch/refined" --color "0e8a16" --description "Architecture: refined issue" 2>/dev/null || true

# ctx/* ラベル（Issue 候補リストの scope フィールドから動的生成）
# 導出ルール: domain/contexts/<name>.md → ctx/<name>, contracts/<name>.md → ctx/<name> (Cross-cutting)
for SCOPE in <unique-scopes-from-candidates>; do
  # サニタイズ: メタ文字除去 + 空文字列ガード + 英数字・ハイフン・アンダースコアのみ許可
  SAFE_SCOPE=$(printf '%s' "${SCOPE}" | tr -d '`$"'\''' | tr -cd 'a-zA-Z0-9_-')
  [ -z "${SAFE_SCOPE}" ] && { echo "WARN: 空のスコープ名をスキップ" >&2; continue; }
  # description 判定: contracts/ 由来は Cross-cutting、contexts/ は type メタデータから取得（不明時は省略）
  CTX_DESC="Context: ${SAFE_SCOPE}"
  # type が判定できる場合: CTX_DESC="Context: ${SAFE_SCOPE} (Core|Supporting|Generic|Cross-cutting)"
  gh label create "ctx/${SAFE_SCOPE}" --color "1d76db" --description "${CTX_DESC}" 2>/dev/null || true
done
```

## Step 3: Milestone 冪等作成

各 Phase に対応する Milestone を作成:

```bash
# Phase ごとに Milestone を作成（既存ならスキップ）
for PHASE in <unique-phases>; do
  MILESTONE_TITLE="Phase ${PHASE_NUM}: ${PHASE_TITLE}"
  # 既存チェック（jq --arg で安全に変数を渡す）
  EXISTING=$(gh api repos/{owner}/{repo}/milestones 2>/dev/null | jq --arg title "${MILESTONE_TITLE}" '.[] | select(.title==$title) | .number')
  if [ -z "${EXISTING}" ]; then
    gh api repos/{owner}/{repo}/milestones -f title="${MILESTONE_TITLE}" -f state="open"
  fi
done
```

## Step 4: 親 Issue 作成

プロジェクト名をサニタイズし、body を `--body-file` 経由で渡す:

```bash
SAFE_PROJECT=$(printf '%s' "<project-name>" | tr -d '`$"'\''')
# WORK_DIR/parent-issue.md にテンプレートを書き出し、python3 で __PROJECT_NAME__ を置換
PARENT_URL=$(gh issue create --title "[Architecture] ${SAFE_PROJECT}: 実装計画" --label "enhancement" --body-file "${WORK_DIR}/parent-issue.md")
PARENT_NUM=$(echo "${PARENT_URL}" | grep -oP '\d+$')
[[ "${PARENT_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 親Issue番号の取得に失敗" >&2; exit 1; }
```

テンプレート内容: 概要 + Phase構成テーブル + Sub-Issues セクション。

## Step 5: 子 Issue の依存順ソート・作成

候補リストをトポロジカルソートし、`declare -A ISSUE_MAP` で仮番号→実番号を管理。

各候補について:
1. タイトルサニタイズ（`tr -d` + `head -c 200`）
2. 依存関係の仮番号→実番号置換（未解決は WARN + スキップ）
3. body を `WORK_DIR/child-issue.md` に書き出し（heredoc + python3 プレースホルダ置換）
   - セクション: 概要、Architecture Reference（`<!-- arch-ref-start/end -->`）、Dependencies（`<!-- deps-start/end -->`）、受け入れ基準、Related（Parent: #N）
4. Milestone 番号を `gh api repos/{owner}/{repo}/milestones` + jq で取得
5. ctx/* ラベルを scope から動的構築（`CTX_LABEL_ARGS` 配列）
6. `gh issue create --title --label enhancement --label arch/skeleton --body-file` で作成
7. `[[ "${CHILD_NUM}" =~ ^[0-9]+$ ]] || continue` でバリデーション
8. `ISSUE_MAP[${CANDIDATE_ID}]="${CHILD_NUM}"` に記録

## Step 6: GraphQL Sub-Issues 親子紐付け

```bash
PARENT_NODE_ID=$(gh issue view "${PARENT_NUM}" --json id -q '.id')
for CANDIDATE_ID in "${!ISSUE_MAP[@]}"; do
  REAL_NUM="${ISSUE_MAP[${CANDIDATE_ID}]}"
  [ -z "${REAL_NUM}" ] && continue
  CHILD_NODE_ID=$(gh issue view "${REAL_NUM}" --json id -q '.id')
  gh api graphql -f query='
    mutation($parentId: ID!, $childId: ID!) {
      addSubIssue(input: { issueId: $parentId, subIssueId: $childId }) {
        issue { subIssuesSummary { completed total percentCompleted } }
      }
    }
  ' -f parentId="${PARENT_NODE_ID}" -f childId="${CHILD_NODE_ID}"
done
```

## Step 7: 完了サマリー表示

SubIssuesSummary を GraphQL で取得し、親 Issue 番号・子 Issue 数・マッピング・ラベル・Milestone を出力。

