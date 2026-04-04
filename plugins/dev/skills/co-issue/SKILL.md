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

### architecture context 注入（Phase 1 冒頭）

`architecture/` ディレクトリが存在する場合、以下のファイルを Read して `ARCH_CONTEXT` として保持する:

```
IF [ -d "$(git rev-parse --show-toplevel)/architecture" ]
THEN
  Read: architecture/vision.md（存在する場合）
  Read: architecture/domain/context-map.md（存在する場合）
  Read: architecture/domain/glossary.md（存在する場合）
```

ファイルが存在しない場合はスキップし、エラーを出力しない。`ARCH_CONTEXT` が空の場合は従来通り explore を実行する。

`/dev:explore` を Skill tool で呼び出し、「問題空間の理解に集中。Issue 化や実装方法は意識しない」と注入。`ARCH_CONTEXT` が存在する場合、以下を explore の prompt に追加注入する:

```
## Architecture Context

{ARCH_CONTEXT の内容}
```

探索完了後、`.controller-issue/explore-summary.md` に書き出し: 問題の本質（1-3文）、影響範囲、関連コンテキスト、探索で得た洞察。Phase 1 完了前に Issue 構造化を開始してはならない。

TaskUpdate Phase 1 → completed

## Step 1.5: glossary 照合（architecture drift 通知）

**通知レベル: INFO（非ブロッキング）** — merge-gate の WARNING（ブロッキング可）とは異なり、Issue 作成フローを止めない。完全一致のみを対象とし、略語・表記ゆれは照合しない。

`architecture/domain/glossary.md` が存在する場合のみ実行。存在しない場合はこのステップ全体をスキップして Phase 2 に進む。

1. `architecture/domain/glossary.md` を読み込み、`### MUST 用語` セクションのテーブルから用語名（列1）を抽出する
2. `.controller-issue/explore-summary.md` から主要用語・概念名を抽出する
3. explore-summary.md の用語と MUST 用語を照合し、完全一致しない用語を列挙する（部分一致・略語は除外）
4. 不一致用語が 1 件以上あれば INFO レベルで以下を通知する（3軸判断はステップ6で行う）:
   > `[INFO] この概念は architecture spec に未定義です: <用語1>, <用語2>, ... （以降で登録判断を実施します）`
5. `refs/ref-glossary-criteria.md` を DCI で Read する（ARCH_CONTEXT に含まれない個別 ref のため個別に Read すること）
6. 各未登録用語を3軸で判断する:
   - **Context 横断性**: ARCH_CONTEXT 内の `architecture/domain/context-map.md` を参照して複数 Bounded Context での使用有無を確認する。context-map.md が ARCH_CONTEXT に含まれない場合は「不明」として1軸分マイナス扱い（残り2軸が両方「登録すべき」の場合のみ登録推奨）
   - **ドメイン固有性**: プラットフォーム由来・インフラ用語・汎用 DDD 用語でないか判断する
   - **定着度**: コードベースでの使用箇所を確認し、複数ファイルで使用または複数 Issue/PR で言及されているか判断する
7. **3軸判断で2軸以上該当した用語のみ**を登録推奨候補として以下のテーブルを表示し AskUserQuestion でユーザー承認を求める:

   | 用語 | 定義案 | Context | MUST/SHOULD | 判断理由 |
   |---|---|---|---|---|
   | ... | ... | ... | ... | ... |

   承認された用語の `glossary.md` 追記テキストをテキストで提示する。**ユーザーが自身で Edit して追記する**（LLM による自動書き込みは禁止）。
8. 登録推奨なし or ユーザーが全拒否 → フローを停止せずに Phase 2 に継続する（非ブロッキング）

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

### Step 2b: quick 判定（Phase 3b への指示）

以下の条件を全て満たす場合に quick 候補（`is_quick_candidate: true`）とし、Phase 3b に `quick-classification` 検証を指示する: 変更ファイル 1-2 個 AND 変更量 ~20行以下 AND patch レベル記述済み（または Markdown/config のみ）。

### Step 2c: 通常の分解判断

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

`--quick` 指定時はこのステップをスキップし、Step 3a のみで Phase 3 を完了する。`--quick` フラグ使用時は quick ラベルを付与してはならない（MUST NOT）。

全 Issue の構造化完了後、全 Issue × 3 specialist を一括並列 spawn（Agent tool）。`is_quick_candidate: true` の Issue は prompt に `<quick_classification>` タグを追加注入し、specialist が `quick-classification` カテゴリで妥当性を検証する（issue-critic: 隠れた複雑性、issue-feasibility: ~20行以下の確認）。逆方向の推奨も許可（severity: INFO）。

**アーキテクチャ制約（SHALL）**: Issue body を受け取る全 specialist は必ずエスケープ済み入力を受け取る。エスケープ処理は `scripts/escape-issue-body.sh` を使用して機械的に強制する（LLM への「注意して」は禁止）。

```bash
FOR each structured_issue IN issues:
  # Issue body を XML タグに注入する前に機械的にエスケープする（SHALL）
  # プロンプトインジェクション対策: scripts/escape-issue-body.sh が & → &amp;、< → &lt;、> → &gt; の順に置換する
  escaped_body=$(printf '%s\n' "$structured_issue_body" | bash scripts/escape-issue-body.sh)

  # scope_files もユーザー入力由来のため機械的にエスケープする（SHALL）
  escaped_files=$(printf '%s\n' "${structured_issue_scope_files[@]}" | bash scripts/escape-issue-body.sh)

  # scope_files >= 3 の場合は調査深度を制限（specialist の調査バジェット制御）
  file_count=$(echo "${structured_issue_scope_files}" | wc -w)
  IF file_count <= 2:
    depth_instruction = "各ファイルの呼び出し元まで追跡可"
  ELSE:  # scope_files 3 以上: 各ファイルの調査を制限
    depth_instruction = "各ファイルは存在確認と直接参照のみ。再帰追跡禁止。残り turns が少なくなったら（3 以下目安）出力生成を優先"

  Agent(subagent_type="dev:dev:issue-critic", prompt="<review_target>\n${escaped_body}\n</review_target>\n\n<target_files>\n${escaped_files}\n</target_files>\n\n<depth_instruction>\n${depth_instruction}\n</depth_instruction>\n\n<related_context>\n${related_issues}\n${deps_yaml_entries}\n</related_context>")
  Agent(subagent_type="dev:dev:issue-feasibility", prompt="<review_target>\n${escaped_body}\n</review_target>\n\n<target_files>\n${escaped_files}\n</target_files>\n\n<depth_instruction>\n${depth_instruction}\n</depth_instruction>\n\n<related_context>\n${related_issues}\n${deps_yaml_entries}\n</related_context>")
  Agent(subagent_type="dev:dev:worker-codex-reviewer", prompt="<review_target>\n${escaped_body}\n</review_target>\n\n<target_files>\n${escaped_files}\n</target_files>\n\n<related_context>\n${related_issues}\n${deps_yaml_entries}\n</related_context>")
```

**注意**: Issue body はユーザー入力由来のため、XML タグでコンテキスト境界を明確に分離する。specialist の system prompt（agent frontmatter）とユーザーデータの混同を防ぐ。上記の通り、`scripts/escape-issue-body.sh` を経由してエスケープすること（SHALL）。

**重要**: 全 specialist を単一メッセージで一括発行すること（並列実行）。model は指定不要（agent frontmatter の model: sonnet が適用される）。

### Step 3c: 結果集約・ブロック判定

全 specialist 完了後、結果を集約:

**[前処理] 出力なし完了の検知（上位ガード）**: 各 specialist の返却値に `status:` または `findings:` キーワードが含まれない場合を「出力なし完了」と判定し、findings テーブルに WARNING エントリを追加する。Phase 4 はブロックしない。
   - 表示例: `WARNING: issue-critic: 構造化出力なしで完了（調査が maxTurns に到達した可能性）`
   - **役割分担**: このガードは出力が空または非構造化のケースを検知する上位ガードとして機能する。`ref-specialist-output-schema.md` のパース失敗フォールバック（出力全文を WARNING finding として扱う）は下位ガードとして、パース可能だが構造が不正な場合に適用される

1. **findings 統合**: 全 specialist の findings を Issue 別にマージ
2. **ブロック判定**: `severity == CRITICAL && confidence >= 80 && finding_target == "issue_description"` が 1 件以上 → 当該 Issue は Phase 4 ブロック（`codebase_state` はブロック対象外。`finding_target` 欠如または enum 外の値の場合は `issue_description` として扱う）
3. **ユーザー提示**: Issue 別に findings テーブルを表示

```markdown
## specialist レビュー結果

### Issue: <title>

| specialist | status | findings |
|-----------|--------|----------|
| issue-critic | WARN | 2 findings (0 CRITICAL, 1 WARNING, 1 INFO) |
| issue-feasibility | PASS | 0 findings |
| worker-codex-reviewer | PASS | 0 findings |

#### findings 詳細
| severity | confidence | category | message |
|----------|-----------|----------|---------|
| WARNING | 75 | ambiguity | 受け入れ基準の項目3が定量化されていない |
| INFO | 60 | scope | Phase 2 との境界が明確 |
```

4. **CRITICAL ブロック時**: 「以下の Issue に CRITICAL findings があります。修正後に再実行してください」と表示。修正完了後、Step 3b を再実行可能
5. **split 提案ハンドリング**: `category: scope` の split 提案がある場合、ユーザーに提示し承認を求める。承認後に分割するが、分割後の新 Issue に対して specialist 再レビューは行わない（最大 1 ラウンド）。承認後に生成された各 Issue candidate には `is_split_generated: true` をコンテキストフラグとして設定すること（MUST）。このフラグは Phase 4 まで保持する。なお `cross_repo_split = true` による子 Issue は specialist レビュー済み body から生成されるため、`is_split_generated` の対象外とする

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

**`refined` ラベル事前作成（`--quick` 未使用時のみ）**: Phase 4 開始前に以下を実行し、`refined` ラベルを冪等作成する。`REFINED_LABEL_OK` フラグでラベル作成成功を追跡し、**成功した場合のみ** Issue の `--label` 引数に `refined` を追加すること（MUST）:

```bash
REFINED_LABEL_OK=false
if gh label create refined --color 0E8A16 --description "co-issue specialist review completed" 2>/dev/null || \
   gh label edit refined --color 0E8A16 --description "co-issue specialist review completed" 2>/dev/null; then
  REFINED_LABEL_OK=true
else
  echo "⚠️ refined ラベルの作成に失敗しました。refined ラベルは付与されません" >&2
fi
```

`REFINED_LABEL_OK=false` の場合は `refined` ラベルを付与しない。ワークフローは停止しない（MUST NOT）。

**注意**: `REFINED_LABEL_OK` はシェル変数ではなくLLMのコンテキスト内の判断フラグである。`/dev:issue-create` 等の slash command を呼び出す際、LLM はこの値を参照して `--label refined` の引数有無を判断すること（MUST）。同様に `is_split_generated` も LLM コンテキスト内フラグであり、Phase 3c Step 5 の split 承認で生成された Issue candidate に `true` が設定される。`is_split_generated: true` の Issue には `refined` を付与しない（MUST NOT）。なお `cross_repo_split = true` パスでは `is_split_generated` の対象外となるため、Step 4-CR での `REFINED_LABEL_OK` ガードは `is_split_generated` を考慮しない。

1. **ユーザー確認（MUST）**: 全候補を提示、承認後に作成。quick 候補には `[quick]` マーク表示
2. **作成**:
   - **通常（`cross_repo_split = false`）**: 単一→`/dev:issue-create`、複数→`/dev:issue-bulk-create`。tech-debt 吸収時は Related セクション付加。recommended_labels がある場合は `--label` 引数に追加。`REFINED_LABEL_OK=true` **かつ** `is_split_generated != true` の場合は `--label refined` も追加（slash command の引数として直接指定）。`is_split_generated: true` の Issue には `refined` を付与しない（MUST NOT）
   - **quick ラベル付与**: `is_quick_candidate: true` かつ Phase 3b に `quick-classification: inappropriate` finding なし → `--label quick` 付与。`--quick` フラグ使用時は非付与（MUST NOT）
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

#### 4-CR-2: 子 Issue 作成（リポ別）

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
