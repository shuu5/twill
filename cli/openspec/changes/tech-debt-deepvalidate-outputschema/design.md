## Context

`deep_validate()` section E（line 2910-2914）で specialist の `output_schema` フィールドを検証する。現在のロジック:

```python
output_schema = cdata.get('output_schema', None)
if output_schema == 'custom':
    pass  # valid
if output_schema is not None and output_schema != '':
    add_warning(...)  # invalid value
```

`output_schema != ''` ガードにより、空文字列が検証をすり抜けてしまう。

## Goals / Non-Goals

**Goals:**

- `output_schema: ""` を invalid value として警告する
- `None`（未宣言）と `""`（空文字列）を明確に区別する

**Non-Goals:**

- 他の `deep_validate()` セクションの修正
- `model_specialist_validate` や `validate_plugin` 内の類似ロジックの変更（別 Issue で対応）

## Decisions

1. **空文字列専用の警告メッセージを追加**: `output_schema == ""` を独立条件として検出し、`empty output_schema value` という専用メッセージで警告する。汎用の invalid value メッセージとは区別する。

2. **条件分岐の再構成**: `!= ""` ガードを削除し、`if/elif` で `""` と その他の invalid value を分離する。

```python
if output_schema is not None:
    if output_schema == "":
        add_warning(f"[specialist-output-schema] {cname}: empty output_schema value (expected 'custom' or omit)")
    elif output_schema != "custom":
        add_warning(f"[specialist-output-schema] {cname}: invalid output_schema value '{output_schema}' (expected 'custom' or omit)")
```

## Risks / Trade-offs

- **リスク低**: 変更は 1 箇所の条件分岐のみ。既存の `custom` / `None` パスは不変
- `output_schema: ""` を意図的に設定しているユーザーがいた場合、新たに警告が出る。ただし空文字列は有効な値ではないため、これは正しい動作
