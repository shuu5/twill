---
name: dev:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase 構成: 問題探索 → 分解判断 → Per-Issue 精緻化 → 一括作成。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Agent(issue-critic, issue-feasibility, context-checker, template-validator)
spawnable_by:
- user
---

# co-issue

要望→Issue 変換ワークフロー（4 Phase 構成）。Non-implementation controller（chain-driven 不要）。

## explore-summary 検出（起動時チェック）

`.controller-issue/explore-summary.md` の存在を確認。存在時は「前回の探索結果が残っています。継続しますか？」と確認:
- [A] 継続する → Phase 1（探索）をスキップし Phase 2 から再開
- [B] 最初から → explore-summary.md を削除し Phase 1 から開始

存在しない場合は通常の Phase 1 から開始（既存動作に影響なし）。self-improve-review 出力も同一パスで検出される。

## Phase 1: 問題探索

TaskCreate 「Phase 1: 問題探索」(status: in_progress)

`/dev:explore` を Skill tool で呼び出し、「問題空間の理解に集中。Issue 化や実装方法は意識しない」と注入。

探索完了後、`.controller-issue/explore-summary.md` に書き出し: 問題の本質（1-3文）、影響範囲、関連コンテキスト、探索で得た洞察。Phase 1 完了前に Issue 構造化を開始してはならない。

TaskUpdate Phase 1 → completed

## Phase 2: 分解判断

TaskCreate 「Phase 2: 分解判断」(status: in_progress)

explore-summary.md を読み込み、単一/複数 Issue を判断。

### Step 2a: クロスリポ検出

explore-summary.md の内容から、以下の条件でクロスリポ横断を検出する:

1. **複数リポ名の明示的言及**: 2つ以上の異なるリポ名（loom, loom-plugin-dev, loom-plugin-session 等）が言及されている
2. **クロスリポキーワード**: 「全リポ」「3リポ」「各リポ」「クロスリポ」「全リポジトリ」等のキーワードが含まれる
3. **複数リポのファイルパス**: 異なるリポのパスが含まれる

**リポ一覧の動的取得**: 対象リポは GitHub Project のリンク済みリポジトリから動的に取得する（ハードコード禁止）。

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"
PROJECTS=$(gh project list --owner "$OWNER" --format json)
# 各 Project の linked repositories を GraphQL で取得し、現在のリポが含まれる Project を特定
# project-board-status-update と同様のパターン（user → organization フォールバック）
```

Project にリンクされていない場合、クロスリポ検出はスキップし従来の分解判断に進む。

**検出時の分割提案**: クロスリポ横断を検出した場合、AskUserQuestion で確認:

> この要望は N リポにまたがります。リポ単位で分割しますか？
> 対象リポ: repo1, repo2, repo3
>
> [A] リポ単位で分割する
> [B] 単一 Issue として作成する

- [A] 選択時: `cross_repo_split = true`、`target_repos` に対象リポリストを記録。Phase 3 以降はリポ単位の子 Issue 構造で精緻化
- [B] 選択時: 従来通り単一 Issue として Phase 3 以降に進む

### Step 2b: 通常の分解判断

複数の場合は AskUserQuestion で分解内容を確認: [A] この分解で進める [B] 調整 [C] 単一のまま続行。

TaskUpdate Phase 2 → completed

## Phase 3: Per-Issue 精緻化ループ

TaskCreate 「Phase 3: 精緻化（N件）」(status: in_progress)

### Step 3a: 構造化（各 Issue 順次）

各 Issue 候補に対して順に:

1. **構造化**: `/dev:issue-structure` でテンプレート適用（bug/feature）
2. **推奨ラベル抽出**: issue-structure 出力の `## 推奨ラベル` セクションから `ctx/<name>` を抽出し recommended_labels に記録（セクションなし→空）
3. **tech-debt 棚卸し**（該当時のみ）: `/dev:issue-tech-debt-absorb` → Phase 4 で使用

**クロスリポ分割時の構造化ルール**（`cross_repo_split = true` の場合）:

- **parent Issue**: 仕様定義のみ。タイトルは元の要望のタイトル。body に「概要」「子 Issue」セクションを含む。実装スコープ（含む/含まない）は記載しない。子 Issue セクションには作成後にチェックリストを追記するプレースホルダーを配置
- **子 Issue（リポ別）**: 各対象リポでの実装スコープを記述。タイトルに対象リポ名を含め `[Feature] <リポ名>: <元タイトル>` 形式。body に `Parent: owner/repo#N` 参照を含める

### Step 3b: specialist 並列レビュー

`--quick` 指定時はこのステップをスキップし、Step 3a のみで Phase 3 を完了する。

全 Issue の構造化完了後、全 Issue × 2 specialist を一括並列 spawn（Agent tool）:

```
FOR each structured_issue IN issues:
  Agent(subagent_type="dev:dev:issue-critic", prompt="<review_target>\n{structured_issue.body}\n</review_target>\n\n<target_files>\n{structured_issue.scope_files}\n</target_files>\n\n<related_context>\n{related_issues}\n{deps_yaml_entries}\n</related_context>")
  Agent(subagent_type="dev:dev:issue-feasibility", prompt="<review_target>\n{structured_issue.body}\n</review_target>\n\n<target_files>\n{structured_issue.scope_files}\n</target_files>\n\n<related_context>\n{related_issues}\n{deps_yaml_entries}\n</related_context>")
```

**注意**: Issue body はユーザー入力由来のため、XML タグでコンテキスト境界を明確に分離する。specialist の system prompt（agent frontmatter）とユーザーデータの混同を防ぐ。

**重要**: 全 specialist を単一メッセージで一括発行すること（並列実行）。model は指定不要（agent frontmatter の model: sonnet が適用される）。

### Step 3c: 結果集約・ブロック判定

全 specialist 完了後、結果を集約:

1. **findings 統合**: 全 specialist の findings を Issue 別にマージ
2. **ブロック判定**: `severity == CRITICAL && confidence >= 80` が 1 件以上 → 当該 Issue は Phase 4 ブロック
3. **ユーザー提示**: Issue 別に findings テーブルを表示

```markdown
## specialist レビュー結果

### Issue: <title>

| specialist | status | findings |
|-----------|--------|----------|
| issue-critic | WARN | 2 findings (0 CRITICAL, 1 WARNING, 1 INFO) |
| issue-feasibility | PASS | 0 findings |

#### findings 詳細
| severity | confidence | category | message |
|----------|-----------|----------|---------|
| WARNING | 75 | ambiguity | 受け入れ基準の項目3が定量化されていない |
| INFO | 60 | scope | Phase 2 との境界が明確 |
```

4. **CRITICAL ブロック時**: 「以下の Issue に CRITICAL findings があります。修正後に再実行してください」と表示。修正完了後、Step 3b を再実行可能
5. **split 提案ハンドリング**: `category: scope` の split 提案がある場合、ユーザーに提示し承認を求める。承認後に分割するが、分割後の新 Issue に対して specialist 再レビューは行わない（最大 1 ラウンド）

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

1. **ユーザー確認（MUST）**: 全候補を提示、承認後に作成
2. **作成**:
   - **通常（`cross_repo_split = false`）**: 単一→`/dev:issue-create`、複数→`/dev:issue-bulk-create`。tech-debt 吸収時は Related セクション付加。recommended_labels がある場合は `--label` 引数に追加
   - **クロスリポ分割（`cross_repo_split = true`）**: 以下の Step 4-CR を実行
3. **Project Board 同期**: 各 Issue 後 `/dev:project-board-sync N`（失敗は警告のみ）
4. **クリーンアップ**: `.controller-issue/` を削除（中止時も同様）
5. **完了通知**: Issue URL 表示、`/dev:workflow-setup #N` で開発開始を案内

### Step 4-CR: クロスリポ分割時の作成フロー

`cross_repo_split = true` の場合に実行。

#### セキュリティ注意（MUST）

Issue のタイトルはユーザー入力由来のため、シェルメタ文字を含む可能性がある。

- `--title` の値は `printf '%s' | tr -d` でバッククォート・`$`・ダブルクォート・シングルクォートを除去してサニタイズする
- `--body` は必ず `--body-file` でファイル経由で渡す

#### 4-CR-1: parent Issue 作成

現在のリポに parent Issue を作成する。body-file 経由で安全に渡す:

```bash
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

SAFE_TITLE=$(printf '%s' "<元タイトル>" | tr -d '`$"'\''')

cat > "${WORK_DIR}/parent-issue.md" <<'ISSUE_EOF'
## 概要

<元の要望の概要>

## 子 Issue

<!-- CHILD_CHECKLIST_PLACEHOLDER -->
ISSUE_EOF

PARENT_URL=$(gh issue create \
  --title "[Feature] ${SAFE_TITLE}" \
  --label "enhancement" \
  --body-file "${WORK_DIR}/parent-issue.md")
PARENT_NUM=$(echo "${PARENT_URL}" | grep -oE '[0-9]+$')
[[ "${PARENT_NUM}" =~ ^[0-9]+$ ]] || { echo "ERROR: 親Issue番号の取得に失敗" >&2; exit 1; }
```

recommended_labels がある場合は `--label` 引数に追加。

#### 4-CR-2: 子 Issue 作成（リポ別）

`target_repos` の各リポに対して子 Issue を作成:

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"
CURRENT_REPO="${REPO#*/}"
CHILD_REFS=()

for TARGET_REPO in "${TARGET_REPOS[@]}"; do
  cat > "${WORK_DIR}/child-issue.md" <<ISSUE_EOF
## 概要

<リポ固有の実装スコープ>

## Parent

${OWNER}/${CURRENT_REPO}#${PARENT_NUM}
ISSUE_EOF

  CHILD_URL=$(gh issue create \
    -R "${OWNER}/${TARGET_REPO}" \
    --title "[Feature] ${TARGET_REPO}: ${SAFE_TITLE}" \
    --label "enhancement" \
    --body-file "${WORK_DIR}/child-issue.md") && {
    CHILD_NUM=$(echo "${CHILD_URL}" | grep -oE '[0-9]+$')
    [[ "${CHILD_NUM}" =~ ^[0-9]+$ ]] || continue
    CHILD_REFS+=("${OWNER}/${TARGET_REPO}#${CHILD_NUM}")
  } || {
    echo "⚠️ ${TARGET_REPO} への子 Issue 作成に失敗しました（続行）"
  }
done
```

子 Issue 作成が失敗しても残りのリポへの作成を継続する。成功した子 Issue のみチェックリストに記載する。

#### 4-CR-3: parent Issue にチェックリスト追記

全子 Issue 作成後、parent Issue の body を更新。CHILD_REFS が空の場合は警告のみ:

```bash
if [ ${#CHILD_REFS[@]} -eq 0 ]; then
  echo "⚠️ 子 Issue の作成が全件失敗しました。parent Issue のチェックリストは更新しません"
else
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

TaskUpdate Phase 4 → completed

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
