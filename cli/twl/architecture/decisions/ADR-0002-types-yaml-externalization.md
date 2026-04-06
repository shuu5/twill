## ADR-0002: types.yaml 外部化

## Status

Accepted

## Context

初期の twl-engine.py は型ルール（can_spawn/spawnable_by）を Python dict としてハードコードしていた。
型の追加（script 型の新設）や変更のたびに twl-engine.py を編集する必要があり、変更の影響範囲が大きかった。

また、型ルールは plugins/twl 側の ref-types ドキュメントと同期する必要があり、
単一の情報源（SSOT）が存在しないことで不整合が発生していた。

## Decision

型ルールを types.yaml として外部ファイルに分離し、twl-engine.py 起動時にロードする。

types.yaml の構造:
```yaml
types:
  <type_name>:
    section: <section_name>
    can_spawn: [<type_name>, ...]
    spawnable_by: [<type_name>, ...]
```

## Consequences

**良い点:**
- types.yaml が型ルールの SSOT となり、ref-types ドキュメントとの整合性を `twl --sync-check` で機械検証可能に
- 新しい型の追加が YAML 編集のみで完結（twl-engine.py の変更不要）
- types.yaml を複数プラグインで共有可能

**悪い点:**
- twl-engine.py 起動時に types.yaml のロードが必要（ファイルが見つからない場合のフォールバックが必要）
- twl-engine.py 内のハードコード（フォールバック用 TYPE_RULES）と types.yaml の二重管理が残る

**緩和策:**
- `_get_loom_root()` で types.yaml の配置場所を自動解決
- フォールバック TYPE_RULES は types.yaml が見つからない場合のみ使用（WARNING を出力）
