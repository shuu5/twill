# Issue 一括起票

親 Issue と子 Issue 群を一括起票し、親 Issue に子 Issue チェックリストを追記する。

## 前提

呼び出し元 controller が以下のコンテキスト変数を保持していること:
- `<plugin-name>`: 対象プラグイン名
- Step 5 のリファクタリング計画テーブル（各候補のコンポーネント名、Step番号/名、抽出先パス、型、Verdict、行数）

controller は各候補をイテレートしながら、候補ごとに `COMPONENT_NAME`, `STEP_NAME`, `DEST_PATH`, `TYPE`, `VERDICT`, `LINE_COUNT` を設定した上で本コマンドの bash テンプレートを実行する。

## セキュリティ注意（MUST）

Issue のタイトル・ボディに含める値は Loom Audit 出力由来のため、シェルメタ文字を含む可能性がある。

- `--title` の値は `printf '%s' | tr -d` でバッククォート・`$`・ダブルクォート・シングルクォートを除去してサニタイズする
- `--body` は必ず `--body-file` でファイル経由で渡す（`--body` での直接渡しは**禁止**）

---

## Step 1: 一時ディレクトリ作成

```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
```

## Step 2: 親 Issue の起票

```bash
# タイトルのサニタイズ（シングルクォートも除去）
SAFE_PLUGIN=$(printf '%s' "<plugin-name>" | tr -d '`$"'\''')

# ボディをファイルに書き出し
cat > "${TMPDIR}/parent-issue.md" <<'ISSUE_EOF'
## 概要

<plugin-name> プラグインの Loom 準拠度改善のためのリファクタリング。
Loom 監査の CRITICAL/WARNING 検出結果に基づき、インライン実装を外部コマンドに抽出する。

## 抽出候補

(Step 5 のテーブル)

## 子 Issue

(起票後にチェックリストを追記)
ISSUE_EOF

# 起票して親 Issue 番号を取得（URL から数値を抽出）
PARENT_URL=$(gh issue create \
  --title "[Refactor] ${SAFE_PLUGIN}: Loom リファクタリング" \
  --label "enhancement" \
  --body-file "${TMPDIR}/parent-issue.md")
PARENT_NUM=$(echo "${PARENT_URL}" | grep -oP '\d+$')

# 整数検証
[[ "${PARENT_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 親Issue番号の取得に失敗" >&2; exit 1; }
```

## Step 3: 子 Issue の起票

子 Issue 番号を配列に収集しながら、各抽出候補について起票。controller が候補ごとに変数を設定する:

```bash
CHILD_NUMS=()

# controller が各候補について以下の変数を設定してループ実行:
#   COMPONENT_NAME: コンポーネント名
#   STEP_NAME: Step名
#   DEST_PATH: 抽出先パス
#   TYPE: 型（atomic/composite）
#   VERDICT: 判定（CRITICAL/WARNING）
#   LINE_COUNT: 行数

for CANDIDATE in "${CANDIDATES[@]}"; do
  # 各変数を個別にサニタイズ（シングルクォートも除去）
  SAFE_STEP_NAME=$(printf '%s' "${STEP_NAME}" | tr -d '`$"'\''')
  SAFE_TYPE=$(printf '%s' "${TYPE}" | tr -d '`$"'\''')
  SAFE_TITLE=$(printf '%s' "[Refactor] ${SAFE_PLUGIN}: ${SAFE_STEP_NAME} を ${SAFE_TYPE} に抽出" | head -c 200)

  # ボディをファイルに書き出し
  cat > "${TMPDIR}/child-issue.md" <<'ISSUE_EOF'
## 概要

<コンポーネント名> の <Step番号>: <Step名> を `<抽出先パス>` に抽出する。

## 背景・動機

親 Issue: #<親Issue番号>
Loom 監査結果: <Verdict>（<行数>行 / 上限80行）

## スコープ

**含む:**
- `<抽出先パス>` の作成（type: <型>）
- `<コンポーネント名>` から該当 Step のインライン実装を移動
- deps.yaml の更新（新コンポーネント追加 + 呼び出し元の calls 更新）

**含まない:**
- 他の Step のリファクタリング（別 Issue で対応）

## 受け入れ基準

- [ ] `<抽出先パス>` が作成されている
- [ ] 元の controller から該当インライン実装が除去されている
- [ ] deps.yaml が更新されている（twl check: 0 violations）
- [ ] 既存の動作が変わらないこと

## Related

Parent: #<親Issue番号>
ISSUE_EOF

  # 起票して番号を配列に追加
  CHILD_URL=$(gh issue create \
    --title "${SAFE_TITLE}" \
    --label "enhancement" \
    --body-file "${TMPDIR}/child-issue.md")
  CHILD_NUM=$(echo "${CHILD_URL}" | grep -oP '\d+$')

  # 整数検証
  [[ "${CHILD_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 子Issue番号の取得に失敗" >&2; continue; }
  CHILD_NUMS+=("${CHILD_NUM}")
done
```

## Step 4: 親 Issue に子 Issue チェックリストを追記

全子 Issue 起票完了後、親 Issue のボディ内のマーカーを子 Issue チェックリストに置換:

```bash
# 親 Issue の既存ボディをファイルに保存（ヒアストリング展開を回避）
gh issue view "${PARENT_NUM}" --json body -q '.body' > "${TMPDIR}/parent-body.txt"

# 親 Issue のコメントを別ファイルで保存（body とは別変数で保持）
gh api "repos/{owner}/{repo}/issues/${PARENT_NUM}/comments" --jq '[.[].body] | join("\n---\n")' > "${TMPDIR}/parent-comments.txt" 2>/dev/null || true

# 子 Issue チェックリストをファイルに生成
printf '' > "${TMPDIR}/child-checklist.txt"
for NUM in "${CHILD_NUMS[@]}"; do
  printf '- [ ] #%s\n' "${NUM}" >> "${TMPDIR}/child-checklist.txt"
done

# python3 でファイル経由で安全に「## 子 Issue」セクションを置換
python3 -c "
import sys
body = open(sys.argv[1]).read()
checklist = open(sys.argv[2]).read()
marker = '(起票後にチェックリストを追記)'
print(body.replace(marker, checklist))
" "${TMPDIR}/parent-body.txt" "${TMPDIR}/child-checklist.txt" > "${TMPDIR}/parent-updated.md"

gh issue edit "${PARENT_NUM}" --body-file "${TMPDIR}/parent-updated.md"
```
