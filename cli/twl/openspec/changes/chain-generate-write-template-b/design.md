## Context

`chain_generate_write()` の Template B 処理（行3120-3138）は検出ロジックのみ実装済みで書き込みが未実装。`chain_generate_check()` は Template A のドリフト検出のみ。Issue body に確定済み設計判断（called-by パターン、正規表現置換方式）がある。

現在のコード構造:
- `chain_generate()`: template_b を `{comp_name: called_by_text}` 辞書で返す（実装済み）
- `chain_generate_write()`: Template B を検出するが書き込まない（未完成）
- `chain_generate_check()`: Template A のみ検証（Template B 未対応）

## Goals / Non-Goals

**Goals:**

- Template B の `--write` 完全実装（frontmatter description への called-by 追記/更新）
- Template B の `--check` ドリフト検出
- 既存 description テキストの保持

**Non-Goals:**

- Template A / Template C の変更
- `chain_generate()` 関数自体の変更（既に正しい出力を生成）
- frontmatter パーサーの汎用化

## Decisions

### 1. called-by パターンの正規表現

Issue body の確定設計に従い:

```python
CALLED_BY_PATTERN = r'。\S+ (?:Step \d+ )?から呼び出される。$'
```

- 既存 called-by 文検出 → 正規表現で置換
- 未検出 → description 末尾に `。{called_by_text}` を追記

### 2. frontmatter description の解析方式

YAML frontmatter の `description:` 行を直接文字列操作する。理由:
- 既存コードが行ベース解析を使用（行3123-3136）
- YAML パーサーを使うとコメントやフォーマットが変わるリスク
- description は単一行保証（twl の制約）

### 3. --check の Template B 検出方式

`_extract_called_by()` ヘルパー関数を追加:
- frontmatter description から called-by 部分を抽出
- `chain_generate()` が生成した期待値と正規化比較

### 4. description が空または未設定の場合

- `description:` 行が存在 → called-by 文を追記
- `description:` 行が存在しない → Warning + スキップ（frontmatter 構造を変更しない）

## Risks / Trade-offs

- **正規表現の脆弱性**: called-by パターンに一致する手書きテキストが誤置換される可能性 → パターンを厳密に定義することで軽減
- **複数行 description**: 現在は単一行前提。複数行 YAML (`|`, `>`) には対応しない → twl の既存制約として許容
