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

```bash
SAFE_PROJECT=$(printf '%s' "<project-name>" | tr -d '`$"'\''')

cat > "${WORK_DIR}/parent-issue.md" <<'ISSUE_EOF'
## 概要

__PROJECT_NAME__ のアーキテクチャ実装計画。
architecture/ の設計に基づき、Phase 構成で Issue を管理する。

## Phase 構成

(Phase ごとの Issue 一覧テーブル)

## Sub-Issues

(起票後に SubIssuesSummary で進捗追跡)
ISSUE_EOF

# プレースホルダーを安全に展開
python3 -c "
import sys
body = open(sys.argv[1]).read()
body = body.replace('__PROJECT_NAME__', sys.argv[2])
open(sys.argv[1], 'w').write(body)
" "${WORK_DIR}/parent-issue.md" "${SAFE_PROJECT}"

PARENT_URL=$(gh issue create \
  --title "[Architecture] ${SAFE_PROJECT}: 実装計画" \
  --label "enhancement" \
  --body-file "${WORK_DIR}/parent-issue.md")
PARENT_NUM=$(echo "${PARENT_URL}" | grep -oP '\d+$')

[[ "${PARENT_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 親Issue番号の取得に失敗" >&2; exit 1; }
```

## Step 5: 子 Issue の依存順ソート・作成

Issue 候補リストを依存順にトポロジカルソートし、依存先が先に作成されるようにする。
作成済み Issue の仮番号→実番号マッピングテーブルを保持する:

```bash
# マッピングテーブル: 仮番号 → 実 GitHub Issue 番号
declare -A ISSUE_MAP

# 依存順にソートされた候補リストをイテレート
for CANDIDATE in <sorted-candidates>; do
  # タイトルのサニタイズ
  SAFE_TITLE=$(printf '%s' "${TITLE}" | tr -d '`$"'\''' | head -c 200)

  # 依存関係の仮番号を実番号に置換
  DEPS_TEXT=""
  for DEP_ID in <candidate-dependencies>; do
    REAL_NUM="${ISSUE_MAP[${DEP_ID}]}"
    if [ -z "${REAL_NUM}" ]; then
      echo "WARN: 依存 '${DEP_ID}' の Issue 番号が未解決。スキップします" >&2
      continue
    fi
    DEPS_TEXT="${DEPS_TEXT}- depends-on: #${REAL_NUM}
"
  done

  # ボディをファイルに書き出し（クォート付き heredoc で展開を防止）
  cat > "${WORK_DIR}/child-issue.md" <<'ISSUE_EOF'
## 概要

__DESCRIPTION__

## Architecture Reference
<!-- arch-ref-start -->
__ARCH_REFS__
<!-- arch-ref-end -->

## Dependencies
<!-- deps-start -->
__DEPS_TEXT__
<!-- deps-end -->

## 受け入れ基準

(architect-decompose の候補リストから転記)

## Related

Parent: #__PARENT_NUM__
ISSUE_EOF

  # python3 で安全にプレースホルダを置換（シェル展開を回避）
  python3 -c "
import sys
body = open(sys.argv[1]).read()
body = body.replace('__DESCRIPTION__', sys.argv[2])
body = body.replace('__ARCH_REFS__', sys.argv[3])
body = body.replace('__DEPS_TEXT__', sys.argv[4])
body = body.replace('__PARENT_NUM__', sys.argv[5])
open(sys.argv[1], 'w').write(body)
" "${WORK_DIR}/child-issue.md" "${DESCRIPTION}" "${ARCH_REFS}" "${DEPS_TEXT}" "${PARENT_NUM}"

  # Milestone 番号を取得（jq --arg で安全に変数を渡す）
  MILESTONE_TITLE="Phase ${PHASE_NUM}: ${PHASE_TITLE}"
  MILESTONE_NUM=$(gh api repos/{owner}/{repo}/milestones 2>/dev/null | jq --arg title "${MILESTONE_TITLE}" '.[] | select(.title==$title) | .number')

  # Milestone 引数を条件付きで構築（空の場合は省略）
  MILESTONE_ARGS=()
  if [ -n "${MILESTONE_NUM}" ]; then
    MILESTONE_ARGS=(--milestone "${MILESTONE_NUM}")
  fi

  # ctx/* ラベルを scope から生成（複数 scope 対応、bash 配列で安全に構築）
  CTX_LABEL_ARGS=()
  for SCOPE in <candidate-scopes>; do
    SAFE_SCOPE=$(printf '%s' "${SCOPE}" | tr -d '`$"'\''' | tr -cd 'a-zA-Z0-9_-')
    [ -n "${SAFE_SCOPE}" ] && CTX_LABEL_ARGS+=(--label "ctx/${SAFE_SCOPE}")
  done

  # Issue 作成（ラベル + Milestone 付き）
  CHILD_URL=$(gh issue create \
    --title "${SAFE_TITLE}" \
    --label "enhancement" \
    --label "arch/skeleton" \
    "${CTX_LABEL_ARGS[@]}" \
    "${MILESTONE_ARGS[@]}" \
    --body-file "${WORK_DIR}/child-issue.md")
  CHILD_NUM=$(echo "${CHILD_URL}" | grep -oP '\d+$')

  [[ "${CHILD_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 子Issue番号の取得に失敗: ${SAFE_TITLE}" >&2; continue; }

  # マッピングテーブルに追加
  ISSUE_MAP[${CANDIDATE_ID}]="${CHILD_NUM}"
done
```

## Step 6: GraphQL Sub-Issues 親子紐付け

```bash
# 親 Issue の node ID を取得
PARENT_NODE_ID=$(gh issue view "${PARENT_NUM}" --json id -q '.id')

for CANDIDATE_ID in "${!ISSUE_MAP[@]}"; do
  REAL_NUM="${ISSUE_MAP[${CANDIDATE_ID}]}"
  if [ -z "${REAL_NUM}" ]; then
    echo "WARN: 候補 '${CANDIDATE_ID}' の Issue 番号が未解決。紐付けをスキップします" >&2
    continue
  fi
  CHILD_NODE_ID=$(gh issue view "${REAL_NUM}" --json id -q '.id')

  gh api graphql -f query='
    mutation($parentId: ID!, $childId: ID!) {
      addSubIssue(input: { issueId: $parentId, subIssueId: $childId }) {
        issue {
          subIssuesSummary { completed total percentCompleted }
        }
      }
    }
  ' -f parentId="${PARENT_NODE_ID}" -f childId="${CHILD_NODE_ID}"
done
```

## Step 7: 完了サマリー表示

```bash
# SubIssuesSummary を取得
SUMMARY=$(gh api graphql -f query='
  query($id: ID!) {
    node(id: $id) {
      ... on Issue {
        subIssuesSummary { completed total percentCompleted }
      }
    }
  }
' -f id="${PARENT_NODE_ID}" --jq '.data.node.subIssuesSummary')

echo "=== Issue 一括作成完了 ==="
echo "親 Issue: #${PARENT_NUM}"
echo "子 Issue: ${#ISSUE_MAP[@]} 件"
echo "SubIssuesSummary: ${SUMMARY}"
echo ""
echo "--- 作成された Issue ---"
for KEY in "${!ISSUE_MAP[@]}"; do
  echo "  候補 #${KEY} → GitHub #${ISSUE_MAP[${KEY}]}"
done
echo ""
echo "--- ラベル ---"
echo "  状態: arch/skeleton (全件)"
echo "  コンテキスト: ctx/* (各候補の scope に対応)"
echo ""
echo "--- Milestone ---"
echo "  Phase ごとに Milestone を設定済み"
```

