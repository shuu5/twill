## Context

`cli/twl/` 配下に `twl-engine.py`（6,074行）が存在し、すべての TWiLL CLI 機能を単一ファイルで実装している。ADR-0003 でパッケージ構造への移行が決定しており、本変更はその最初のステップ。

現在のディレクトリ構造:
```
cli/twl/
  twl-engine.py      ← 全機能実装（残す）
  tests/
  openspec/
```

目標構造:
```
cli/twl/
  pyproject.toml     ← 新規
  src/twl/
    __init__.py      ← 新規
    __main__.py      ← 新規
    cli.py           ← 新規（twl-engine.py に委譲）
  twl-engine.py      ← そのまま残す
  tests/
  openspec/
```

## Goals / Non-Goals

**Goals:**
- `python3 -m twl <args>` で起動できる Python パッケージを作成
- `pip install -e .` で開発インストール可能な状態にする
- PyYAML を必須依存、tiktoken・rich をオプショナル依存として定義
- 既存のすべての twl コマンドが引き続き動作する

**Non-Goals:**
- twl-engine.py の関数分割・リファクタリング
- bash wrapper（`twl` スクリプト）の変更
- deltaspec 関連機能の追加
- テストの追加・変更

## Decisions

### D1: src レイアウト採用

`src/twl/` を使用することで、インストール前にパッケージが Python パスに含まれることを防ぎ、開発環境と本番環境の差異を減らす。

### D2: twl-engine.py からの委譲パターン

`src/twl/cli.py` は `twl-engine.py` の `main()` を import して委譲する中継レイヤーとして機能する。この段階では twl-engine.py を変更しないことで、リグレッションリスクを最小化する。

```python
# src/twl/cli.py
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from twl_engine import main

def run():
    main()
```

注: `twl-engine.py` のモジュール名は `twl_engine`（ハイフンをアンダースコアに変換してインポート）ではなく、`importlib` または `runpy` 経由でロードする必要がある可能性がある。twl-engine.py の `if __name__ == '__main__':` ブロックを確認して適切な方法を選択する。

### D3: pyproject.toml のエントリポイント

```toml
[project.scripts]
twl = "twl.cli:run"
```

`twl` コマンドを `src/twl/cli.py` の `run()` 関数にマップ。

### D4: Python バージョン制約

`requires-python = ">=3.10"` を指定（ADR-0003 準拠）。

## Risks / Trade-offs

- **twl-engine.py のファイル名**: ハイフンを含むため通常の `import` ができない。`importlib.util` または `runpy.run_path` を使用する必要がある。
- **既存テストへの影響**: テストが `twl-engine.py` を直接 import している場合、パスの調整が必要になる可能性がある。
- **将来の分割時の互換性**: 中継パターンは一時的なものであり、モジュール分割後に cli.py を更新する必要がある。
