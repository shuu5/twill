---
type: atomic
tools: [Bash, Skill]
effort: low
maxTurns: 10
---
# /twl:issue-create - GitHub Issue作成

GitHub Issueを作成するatomicコマンド。

## 使用方法

```
/twl:issue-create "タイトル" "本文"
/twl:issue-create "タイトル" "本文" --label enhancement --related #45 --parent #123
/twl:issue-create "タイトル" "本文" --parent #945 --closes-ac #945:AC8
```

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| タイトル | Yes | Issueのタイトル |
| 本文 | Yes | Issueの本文（Markdown対応） |
| --label | No | ラベル（複数指定可） |
| --related #N | No | 関連Issue（本文末尾に `Related: #N` 追記） |
| --parent #N | No | 親Issue（本文末尾に `Parent: #N` 追記） |
| --closes-ac #EPIC:ACN | No | 親 Epic AC 紐付け（本文末尾に `Closes-AC: #EPIC:ACN` 追記、複数指定可）。Issue close 時に親 Epic body の `- [ ] **AC{N}**` を `- [x]` に auto-flip (Issue #1070) |
| --repo owner/repo | No | 作成先リポジトリ（未指定時は現在のリポ） |

---

## 処理フロー（MUST）

### 1. 引数解析

`$ARGUMENTS` から以下を抽出:
- title: 最初の引用符で囲まれた文字列
- body: 2番目の引用符で囲まれた文字列
- labels: --label に続く値（複数可）
- related: --related に続く #N 値（複数可）
- parent: --parent に続く #N 値
- closes_ac: --closes-ac に続く #EPIC:ACN 値（複数可、Issue #1070）
- repo: --repo に続く owner/repo 値（未指定時は空）

タイトルと本文が両方指定されていることを確認。不足時は使用方法を表示。

### 2. メタデータ追記

```
IF --related が指定されている
THEN 本文末尾に "\n\n---\nRelated: #N1, #N2" を追加
IF --parent が指定されている
THEN 本文末尾に "Parent: #N" を追加（Related と同じセクション内）
IF --closes-ac が指定されている
THEN 各 #EPIC:ACN について "Closes-AC: #EPIC:ACN" を行ごとに追加（Related/Parent と同セクション、複数 AC は複数行）
```

`Closes-AC:` 規約 (Issue #1070) は Issue close 時に親 Epic body の `- [ ] **AC{N}**`
を `- [x]` に auto-flip するための機械抽出 marker。`Parent: #N` と並列に配置する。
複数 AC を満たす Issue は複数行で記述する (例: `Closes-AC: #945:AC6` + `Closes-AC: #945:AC7`)。

### 2.5 Format Guard（MUST）

以下を確認。不合格なら警告を出して続行（blocking ではない）:

| チェック | 基準 |
|---------|------|
| タイトルプレフィックス | `[Feature]`/`[Bug]`/`[Docs]` が含まれる |
| セクション構造 | 本文に `##` で始まるセクションが2つ以上 |
| 本文非空 | 本文が空でない |

```
IF タイトルプレフィックスなし
THEN "⚠️ タイトルにプレフィックス（[Feature]/[Bug]/[Docs]）がありません" を出力
IF セクション < 2
THEN "⚠️ 本文のセクション構造が不十分です" を出力
IF 本文が空
THEN "❌ 本文が空です。Issue作成を中止します" → エラー終了
```

上流の template-validator を通過済みなら全て pass するはず。

### 3. Issue作成

**--repo 未指定時（現在リポ）:**
```bash
gh issue create --title "タイトル" --body "$(cat <<'EOF'
本文（メタデータ追記済み）
EOF
)" [--label ラベル...]
```

**--repo 指定時（cross-repo）:**
```bash
# 本文をテンポラリファイルへ書き出し（shell injection 対策）
BODY_FILE="$(mktemp /tmp/.issue-create-body-XXXXXX.md)"
trap 'rm -f "$BODY_FILE"' EXIT
printf '%s\n' "本文（メタデータ追記済み）" > "$BODY_FILE"
gh issue create -R "owner/repo" --title "タイトル" --body-file "$BODY_FILE" [--label ラベル...]
```

本文に改行が含まれる場合はHEREDOCを使用。`--repo` 指定時は必ず `--body-file` 経由で渡すこと。

### 4. 結果出力

```markdown
## Issue作成完了

- **URL**: [gh出力のURL]
- **番号**: #N
- **タイトル**: [タイトル]

### 次のステップ

このIssueから開発を開始するには:
`/twl:workflow-setup` で `#N` から開発開始
```

---

## エラーハンドリング

| エラー | 対応 |
|--------|------|
| gh未認証 | `gh auth login` を案内 |
| リポジトリ外 | gitリポジトリ内で実行するよう案内 |
| 引数不足 | 使用方法を表示 |

---

## 禁止事項（MUST NOT）

- **Issue番号を推測してはならない**: gh出力から正確に取得
- **存在しないラベルを指定してはならない**: エラーになる場合は警告

---

## 次のステップ

| 呼び出し元 | 次 |
|-----------|-----|
| `co-issue` | 最終ステップ完了。ワークフローに制御を返す |

単独実行の場合: → `/twl:workflow-setup` で `#N` から開発開始
