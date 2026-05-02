---
type: atomic
tools: [Bash, Glob, Grep, Read]
effort: low
maxTurns: 10
---
# architect-completeness-check

architecture/ ディレクトリの完全性を検証し、不足ファイル・セクションを報告する。

## 入力

- `architecture-dir-path`（省略時: `$(git rev-parse --show-toplevel)/architecture`）
- `--type=<value>`（省略時: type 解決ロジックで決定）

## type 解決ロジック（`--type` 未指定時）

後方互換のため、`--type` 未指定時は以下の順序で type を解決する:

1. `.architecture-type` ファイル（プロジェクトルートまたは architecture-dir-path の親に存在する場合）の内容を読む
2. `vision.md` frontmatter の `type:` フィールドを読む
3. いずれも存在しない場合はデフォルト `ddd` を使用

解決した type は後続ステップで使用する。既存 `architecture/` を持つプロジェクトは `.architecture-type` も `vision.md` frontmatter も持たないため、デフォルト `ddd` が適用され、影響なし（後方互換保証）。

## type 検証

有効な type 値: `ddd` | `generic`（`lib` は将来実装予定のため現時点では未対応）

未知の type（例: `--type=foo`）を受け取った場合は明示エラーで停止する:
```
ERROR: 未知の type 値 'foo'。有効な type: ddd | generic
```

## 手順

### 0. type 決定

上記「type 解決ロジック」に従い type を決定する。`ref-architecture-spec.md` の `## Project Type` セクションを Read し、有効な type 値を確認する。未知の type はエラーで停止。

### 1. 必須ファイル存在チェック

**Step 1 冒頭**: `ref-architecture-spec.md` を Read し、`## 必須ファイル` セクションの必須テーブルから各パスの `Severity (<TYPE>)` 列を動的に読み出す（type に対応する列を選択）。`RECOMMENDED` 不在は `INFO` レベルで報告する（`WARNING` より低い）。

テーブル参照例（`ref-architecture-spec.md` の `## 必須ファイル` テーブルを参照）:

| パス | 必須 | Severity（ref-architecture-spec.md から type 対応列を動的読み出し） |
|------|------|---------------------------------------------------------------------|
| `vision.md` | YES | 動的読み出し |
| `domain/model.md` | YES | 動的読み出し（type=generic では RECOMMENDED → INFO） |
| `domain/glossary.md` | YES | 動的読み出し（type=generic では RECOMMENDED → INFO） |
| `domain/contexts/*.md` | 1つ以上 | 動的読み出し（type=generic では RECOMMENDED → INFO） |
| `phases/*.md` | 1つ以上 | 動的読み出し |
| `decisions/*.md` | NO | 動的読み出し |
| `contracts/*.md` | NO | 動的読み出し |

各パスを Glob で確認し、不在時は `ref-architecture-spec.md` テーブルの type 対応 `Severity` 値に従ってレベルを決定する:
- `Severity=WARNING` → `[WARNING]`
- `Severity=RECOMMENDED` → `[INFO]`（RECOMMENDED 不在は WARNING より低い INFO レベル）

### 2. 必須セクションチェック

存在するファイルに対し、ref-architecture-spec で定義された必須セクションを Grep で検証:

**vision.md**: `## Vision`, `## Constraints`, `## Non-Goals`

**domain/contexts/*.md** (各ファイル): `# <Context名>`（H1見出し）, `## Responsibility`, `## Key Entities`, `## Dependencies`

**phases/*.md** (各ファイル): `## Scope`, `## Issues`, `## Implementation Status`

**decisions/*.md** (各ファイル): `## Status`, `## Context`, `## Decision`, `## Consequences`

不足セクション → WARNING

### 3. Context 間依存の参照先存在チェック

各 `domain/contexts/*.md` の `## Dependencies` セクションを Read し:
- 参照先 Context 名を抽出
- 対応する `domain/contexts/<参照先>.md` が存在するか確認
- 存在しない → WARNING: `<context>: 依存先 '<target>' のファイルが存在しない`

### 4. 結果出力

```
## Architecture Completeness Check

| カテゴリ | ファイル | 結果 | 詳細 |
|---------|---------|------|------|
| 必須ファイル | vision.md | OK/WARNING | ... |
| セクション | domain/contexts/auth.md | OK/WARNING | ... |
| 依存一貫性 | auth → payment | OK/WARNING | ... |

### 指摘一覧
- [WARNING] vision.md: Non-Goals セクションが未定義
- [INFO] decisions/: ディレクトリ未作成（任意）
- [INFO] domain/model.md: 未作成（generic type では任意）
```

## 禁止事項

- ファイルの作成・修正を行わない（報告のみ）
- ERROR レベルは使用しない（ユーザー判断に委ねる）ただし未知の type は ERROR で停止
