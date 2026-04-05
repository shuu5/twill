# architect-completeness-check

architecture/ ディレクトリの完全性を検証し、不足ファイル・セクションを報告する。

## 入力

- `architecture-dir-path`（省略時: `$(git rev-parse --show-toplevel)/architecture`）

## 手順

### 1. 必須ファイル存在チェック

以下のファイル/ディレクトリの存在を Glob で確認:

| パス | 必須 | 不在時レベル |
|------|------|-------------|
| `vision.md` | YES | WARNING |
| `domain/model.md` | YES | WARNING |
| `domain/glossary.md` | YES | WARNING |
| `domain/contexts/*.md` | 1つ以上 | WARNING |
| `phases/*.md` | 1つ以上 | WARNING |
| `decisions/` | NO | INFO（未作成） |
| `contracts/` | NO | INFO（未作成） |

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
```

## 禁止事項

- ファイルの作成・修正を行わない（報告のみ）
- ERROR レベルは使用しない（ユーザー判断に委ねる）
