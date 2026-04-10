## Context

ADR-014 が `observer` 型を `supervisor` 型に再定義した。`types.yaml` および Python 実装（types.py, validate.py, graph.py）に `observer` 参照が残存しており、`twl check` が失敗する。変更はすべて文字列置換で完結する。

## Goals / Non-Goals

**Goals:**

- `cli/twl/types.yaml` の `observer` 型を `supervisor` に rename
- `spawnable_by` 内の全 `observer` 参照を `supervisor` に更新（atomic, specialist, reference 型）
- `spawnable_by: [user, launcher]` の `launcher` を削除し `spawnable_by: [user]` に変更（ADR-014 準拠）
- Python 実装の `observer` 参照を `supervisor` に更新（types.py, validate.py, graph.py）
- `twl check` が PASS すること

**Non-Goals:**

- supervisor 型の新機能追加
- 他の ADR-014 関連変更（Supervisor エージェントの実装など）

## Decisions

1. **文字列置換のみ**: observer → supervisor の rename は単純な文字列置換。ロジック変更なし。
2. **graph.py のキー名**: `observers` キー（L150）も `supervisors` に rename。分類ロジックの `observer` 分岐を `supervisor` に更新。
3. **spawnable_by の launcher 削除**: ADR-014 に従い supervisor は `spawnable_by: [user]` のみ。
4. **can_supervise 維持**: `can_supervise: [controller]` は変更なし。

## Risks / Trade-offs

- **後続 Issue の依存**: B1-B5, C4 が supervisor 型定義を前提としている。本 Issue が先行 Issue のため影響は minimal。
- **プラグイン deps.yaml**: `cli/twl/deps.yaml` に observer 参照がある場合は別途更新が必要だが、本 Issue のスコープ外（Issue スコープは上記4ファイルのみ）。
