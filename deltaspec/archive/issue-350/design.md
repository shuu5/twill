## Context

ADR-014 で `observer` 型を `supervisor` 型に再定義。Issue #348 で types.yaml・Python ソースコードの置換は完了済み。本 Issue (#350) はテストコードの残存 `observer` 参照を修正する。

対象ファイルは `cli/twl/tests/test_observer_type.py` の 1 ファイルのみ（grep 確認済み）。

## Goals / Non-Goals

**Goals**
- `test_observer_type.py` を `test_supervisor_type.py` にリネーム
- テストクラス名・docstring の observer → supervisor 置換
- `spawnable_by` assertion から `launcher` を除去（ADR-014 準拠: `spawnable_by: [user]` のみ）
- `pytest tests/` が全件 PASS すること

**Non-Goals**
- types.yaml・Python ソースの変更（Issue #348 で完了済み）
- 新機能追加

## Decisions

| 決定 | 理由 |
|------|------|
| ファイルリネーム（rename ではなく新規作成 + 削除） | git mv で履歴を保持 |
| `test_supervisor_type.py` に `test_observer_type.py` の全テストを移植 | 型名 supervisor に合わせた完全置換 |
| `spawnable_by` assertion から `launcher` を除去 | ADR-014: supervisor の spawnable_by は `[user]` のみ |

## Risks / Trade-offs

- リスクなし（テストファイルのみの変更、実装コードへの影響なし）
