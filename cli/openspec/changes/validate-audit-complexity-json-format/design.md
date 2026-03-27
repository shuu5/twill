## Context

loom-engine.py の検証コマンドは2種類の出力アーキテクチャを持つ:

1. **構造化 return 型**: validate_types() → `Tuple[int, List[str]]`, deep_validate() → `Tuple[List[str], List[str], List[str]]`, check_files() → `List[Tuple[str, str, str]]`。データが関数の戻り値で取得でき、JSON シリアライズが容易。
2. **print() 直接出力型**: audit_report(), complexity_report() は内部で print() を直接呼び出し（audit: 約50箇所、complexity: 約55箇所）、return 値にデータを含まない。

現在の argparse は `--format` 引数を持たない。全コマンドは `--validate`, `--check`, `--audit` 等のフラグで起動される。

## Goals / Non-Goals

**Goals:**

- 全5コマンド（validate, deep-validate, check, audit, complexity）で `--format json` オプションによる JSON 構造化出力を提供
- 共通エンベロープで統一された JSON 構造
- Phase 1（validate, deep-validate, check）は既存 return 値を活用し低リスクで実装
- Phase 2（audit, complexity）はデータ収集とフォーマットの責務分離を行った上で JSON 対応

**Non-Goals:**

- `--format yaml` や `--format csv` 等の他フォーマット対応
- 既存テキスト出力の変更やリッチ化
- check 以外のコマンド（--tree, --mermaid, --orphans 等）の JSON 対応
- JSON Schema の公開や外部バリデーション

## Decisions

### D1: `--format` 引数の追加位置

argparse に `--format` を追加。値は `json` のみ許可（将来の拡張余地のため enum 形式）:
```python
parser.add_argument('--format', choices=['json'], help='Output format (default: text)')
```

### D2: 共通エンベロープ構造

```python
def build_envelope(command: str, plugin: str, items: list, exit_code: int) -> dict:
    summary = {"critical": 0, "warning": 0, "info": 0, "ok": 0}
    for item in items:
        sev = item.get("severity", "info")
        summary[sev] = summary.get(sev, 0) + 1
    summary["total"] = len(items)
    return {
        "command": command,
        "version": deps_version,
        "plugin": plugin,
        "items": items,
        "summary": summary,
        "exit_code": exit_code,
    }
```

### D3: Phase 1 — validate/deep-validate/check の JSON 変換

既存関数の戻り値から items を構築:

- **validate**: violations リスト内の `[code] section/name: message` パターンをパースし、severity=critical/warning/info に分類
- **deep-validate**: criticals/warnings/infos の3リストをそのまま severity にマッピング
- **check**: results タプルの status を severity にマッピング（missing→critical, no_path→warning, ok→ok, external→info）

### D4: Phase 2 — audit/complexity のリファクタ戦略

audit_report() と complexity_report() を以下の2層に分離:

1. **データ収集関数**: `audit_collect()` / `complexity_collect()` — print() なし、items リストを return
2. **表示関数**: 既存の audit_report() / complexity_report() — collect() を呼んで print()

これにより JSON 出力時は collect() のみ呼び出し、テキスト出力時は既存関数をそのまま使用。

### D5: stderr/stdout 分離

JSON 出力時:
- stdout: 純粋な JSON のみ（`json.dumps()` 1回）
- stderr: 進捗ログ等（必要に応じて）

テキスト出力時: 既存動作を維持（全て stdout）。

### D6: exit code 維持

JSON でもテキストでも同一の exit code ルール:
- violations/criticals あり → exit 1
- なし → exit 0

## Risks / Trade-offs

- **audit/complexity の print() リファクタ**: 影響箇所が多い（計105箇所程度）。既存テストの期待出力への影響を最小化するため、collect() を新設し既存関数は collect() + print() のラッパーとする
- **validate の violation パース**: 現在 violations は自由形式文字列（`[code] section/name: message`）。パースの信頼性を高めるため、validate 関数側で構造化データを返すヘルパーを追加する必要がある
- **Phase 分割のトレードオフ**: Phase 1 のみで merge-gate は動作可能だが、audit/complexity の JSON 化が遅れると loom-plugin-dev の他コンポーネントが手動パースを続ける可能性がある
