---
type: atomic
tools: [Bash, Skill, Read]
effort: medium
maxTurns: 30
---
# /twl:issue-cross-repo-create - クロスリポ分割 Issue 作成

`cross_repo_split = true` 時に parent Issue + リポ別子 Issue を作成する。

## 入力

- `original_title`: 元の要望タイトル
- `original_summary`: 元の要望の概要
- `target_repos`: 対象リポリスト
- `child_specs`: リポ別の実装スコープ（構造化済み body）
- `recommended_labels`: 推奨ラベルリスト
- `REFINED_LABEL_OK`: refined ラベル作成成功フラグ

## セキュリティ注意（MUST）

Issue のタイトルはユーザー入力由来のため、シェルメタ文字を含む可能性がある。

- `--title` の値は `printf '%s' | LC_ALL=C tr -cd '[:alnum:] ._-'` で allow-list 方式（ASCII 英数字・半角スペース・ピリオド・アンダースコア・ハイフンのみ許可）にサニタイズする。空文字になった場合は `untitled` にフォールバックする
- `--body` は必ず `--body-file` でファイル経由で渡す

## フロー（MUST）

### 4-CR-1: parent Issue 作成

現在のリポに parent Issue を作成する。body-file 経由で安全に渡す:

```bash
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

SAFE_TITLE=$(printf '%s' "<元タイトル>" | LC_ALL=C tr -cd '[:alnum:] ._-')
SAFE_TITLE="${SAFE_TITLE:-untitled}"

cat > "${WORK_DIR}/parent-issue.md" <<'ISSUE_EOF'
## 概要

<元の要望の概要>

## 子 Issue

<!-- CHILD_CHECKLIST_PLACEHOLDER -->
ISSUE_EOF

PARENT_LABELS=(--label "enhancement")
[[ "${REFINED_LABEL_OK}" == "true" ]] && PARENT_LABELS+=(--label "refined")

PARENT_URL=$(gh issue create \
  --title "[Feature] ${SAFE_TITLE}" \
  "${PARENT_LABELS[@]}" \
  --body-file "${WORK_DIR}/parent-issue.md")
PARENT_NUM=$(echo "${PARENT_URL}" | grep -oE '[0-9]+$')
[[ "${PARENT_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 親Issue番号の取得に失敗" >&2; exit 1; }
```

recommended_labels がある場合は `--label` 引数に `PARENT_LABELS` に追加すること。

### 4-CR-2: 子 Issue 作成（リポ別）

`target_repos` の各リポに対して子 Issue を作成:

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"
CURRENT_REPO="${REPO#*/}"
CHILD_REFS=()

for TARGET_REPO in "${TARGET_REPOS[@]}"; do
  # --quick 未使用時: 対象リポに refined ラベルを冪等作成
  CHILD_REFINED_OK=false
  if [[ "${REFINED_LABEL_OK}" == "true" ]]; then
    if gh label create refined --color 0E8A16 --description "co-issue specialist review completed" \
         -R "${OWNER}/${TARGET_REPO}" 2>/dev/null || \
       gh label edit refined --color 0E8A16 --description "co-issue specialist review completed" \
         -R "${OWNER}/${TARGET_REPO}" 2>/dev/null; then
      CHILD_REFINED_OK=true
    else
      echo "⚠️ ${TARGET_REPO} への refined ラベル作成に失敗しました（refined は付与されません）" >&2
    fi
  fi

  cat > "${WORK_DIR}/child-issue.md" <<ISSUE_EOF
## 概要

<リポ固有の実装スコープ>

## Parent

${OWNER}/${CURRENT_REPO}#${PARENT_NUM}
ISSUE_EOF

  CHILD_LABELS=(--label "enhancement")
  [[ "${CHILD_REFINED_OK}" == "true" ]] && CHILD_LABELS+=(--label "refined")

  CHILD_URL=$(gh issue create \
    -R "${OWNER}/${TARGET_REPO}" \
    --title "[Feature] ${TARGET_REPO}: ${SAFE_TITLE}" \
    "${CHILD_LABELS[@]}" \
    --body-file "${WORK_DIR}/child-issue.md") && {
    CHILD_NUM=$(echo "${CHILD_URL}" | grep -oE '[0-9]+$')
    [[ "${CHILD_NUM}" =~ ^[0-9]+$ ]] || continue
    CHILD_REFS+=("${OWNER}/${TARGET_REPO}#${CHILD_NUM}")
  } || {
    echo "⚠️ ${TARGET_REPO} への子 Issue 作成に失敗しました（続行）"
  }
done
```

子 Issue 作成が失敗しても残りのリポへの作成を継続する。成功した子 Issue のみチェックリストに記載する。`--quick` 未使用時は各リポへの `refined` ラベル作成成功（`CHILD_REFINED_OK=true`）を確認してから `--label refined` を追加すること（`REFINED_LABEL_OK=false` の場合はスキップ）。

### 4-CR-3: parent Issue にチェックリスト追記

全子 Issue 作成後、parent Issue の body を更新。CHILD_REFS が空の場合は警告のみ:

```bash
if [ ${#CHILD_REFS[@]} -eq 0 ]; then
  echo "⚠️ 子 Issue の作成が全件失敗しました。parent Issue のチェックリストは更新しません"
else
  # body + 全 comments を取得（content-reading ポリシー: gh-read-content.sh 経由）
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  source "${PLUGIN_ROOT}/scripts/lib/gh-read-content.sh"
  gh_read_issue_full "${PARENT_NUM}" > "${WORK_DIR}/parent-full-content.txt"
  # テンプレート置換用には body のみ使用
  gh issue view "${PARENT_NUM}" --json body -q '.body' > "${WORK_DIR}/parent-body.txt"

  printf '' > "${WORK_DIR}/child-checklist.txt"
  for REF in "${CHILD_REFS[@]}"; do
    printf '- [ ] %s\n' "${REF}" >> "${WORK_DIR}/child-checklist.txt"
  done

  python3 -c "
import sys
body = open(sys.argv[1]).read()
checklist = open(sys.argv[2]).read()
marker = '<!-- CHILD_CHECKLIST_PLACEHOLDER -->'
print(body.replace(marker, checklist))
" "${WORK_DIR}/parent-body.txt" "${WORK_DIR}/child-checklist.txt" > "${WORK_DIR}/parent-updated.md"

  gh issue edit "${PARENT_NUM}" --body-file "${WORK_DIR}/parent-updated.md"
fi
```

## 出力

作成された Issue の URL リスト（parent + children）を呼び出し元に返却する。
