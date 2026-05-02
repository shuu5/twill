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
- `skip:`（省略可）— explore-summary の Recommended Structure から渡される skip リスト。リスト内の必須ファイルを FAIL → INFO に降格する（スキップ対象として扱う）

## 手順

### 0. skip リスト処理（Recommended Structure 連携）

`skip:` パラメータが渡された場合、リスト内のパスを降格対象として記録する。
以降のチェックで当該パスが必須ファイルとして検出された場合でも、
`[FAIL]` ではなく `[INFO]` として報告する（demote: FAIL → INFO）。

```
例: skip: [domain/model.md, domain/glossary.md] が渡された場合
  → domain/model.md が不在でも [INFO] で報告（[FAIL] に昇格させない）
```

これにより、explore フェーズでユーザーが「DDD は不要」と判断したファイルが
完全性チェックをブロックするのを防ぐ。

### 1. 必須ファイル存在チェック

**Step 1 冒頭**: `ref-architecture-spec.md` を Read し、`## 必須ファイル` セクションの必須テーブルから各パスの `Severity` 列を動的に読み出す。`RECOMMENDED` 不在は `INFO` レベルで報告する（`WARNING` より低い）。

**skip リスト降格**: Step 0 で記録した skip リスト内のパスが必須ファイルとして検出された場合、`[FAIL]` / `[WARNING]` ではなく `[INFO]` に降格して報告する。

テーブル形式（`ref-architecture-spec.md` の `## 必須ファイル` テーブルを参照）:

| パス | 必須 | Severity（ref-architecture-spec.md から読み出し） |
|------|------|------------------------------------------------|
| `vision.md` | YES | 動的読み出し |
| `domain/model.md` | YES | 動的読み出し |
| `domain/glossary.md` | YES | 動的読み出し |
| `domain/contexts/*.md` | 1つ以上 | 動的読み出し |
| `phases/*.md` | 1つ以上 | 動的読み出し |
| `decisions/*.md` | NO | 動的読み出し |
| `contracts/*.md` | NO | 動的読み出し |

各パスを Glob で確認し、不在時は `ref-architecture-spec.md` テーブルの `Severity` 値に従ってレベルを決定する:
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
```

## 禁止事項

- ファイルの作成・修正を行わない（報告のみ）
- ERROR レベルは使用しない（ユーザー判断に委ねる）
