## ADR-0005: Python エントリポイントへの一本化

## Status

Accepted

## Context

現行の twl は bash wrapper が case 文でサブコマンドを解析し、python3 twl-engine.py に --flag 形式で渡す二重構造だった。
deltaspec 統合により `twl spec <cmd>` のネストされたサブコマンドが必要となり、bash での解析が複雑化する。

また、ADR-0003 でパッケージ構造への移行が決定済みであり、argparse のサブコマンド機能で自然にルーティングできる。

## Decision

CLI のコマンド解析を Python（argparse）に一本化する。

- `src/twl/__main__.py` で `python3 -m twl` を実現
- `src/twl/cli.py` で argparse サブコマンドを定義
- bash wrapper `twl` は `exec python3 -m twl "$@"` の1行に簡素化
- pyproject.toml の `[project.scripts]` で `twl` エントリポイントも定義

### コマンド体系

```
twl check             # 既存コマンド群（従来のフラグ → サブコマンドに移行）
twl validate
twl deep-validate
twl audit
twl tree
twl graph
twl mermaid
twl rename <old> <new>
twl promote <name> <type>
twl chain generate <name>
twl spec new <name>   # 新規（deltaspec 統合）
twl spec status <name>
twl spec list
...
```

## Consequences

**良い点:**
- コマンド解析のロジックが Python 1箇所に集約
- argparse の自動ヘルプ生成が使える
- ネストされたサブコマンド（`twl spec <cmd>`, `twl chain <cmd>`）が自然に実装可能
- フラグベース（--check, --validate）からサブコマンドベースへの移行で CLI が直感的に

**悪い点:**
- 既存の `twl --check` 等のフラグベースインターフェースが破壊的変更になる
- bash wrapper からの呼び出し元（CI スクリプト等）の更新が必要

**緩和策:**
- 移行期間中は旧フラグも受け付ける互換レイヤーを検討（ただし YAGNI の可能性大）
- 利用者が限定的（自分のみ）のため、破壊的変更の影響は小さい
