## Why

twl-engine.py（6,074行）は単一ファイルで全機能を実装しており、将来の deltaspec 統合・モジュール分割に対応できない。ADR-0003 に従い Python パッケージ構造へ移行する最初のステップとして、`pyproject.toml` と `src/twl/` 基盤を構築する。

## What Changes

- `cli/twl/pyproject.toml` 新規作成（メタデータ、PyYAML 必須依存、tiktoken/rich オプション依存、`[project.scripts]` エントリポイント）
- `cli/twl/src/twl/__init__.py` 新規作成
- `cli/twl/src/twl/__main__.py` 新規作成（`python3 -m twl` で既存 main() を呼び出し）
- `cli/twl/src/twl/cli.py` 骨格作成（twl-engine.py の main() を import して委譲）
- `pip install -e .` で開発インストール可能な状態にする

## Capabilities

### New Capabilities

- `python3 -m twl <args>` での起動（パッケージ経由）
- `pip install -e .` による開発インストール

### Modified Capabilities

- 既存のすべての `twl` コマンド（check、spec、validate 等）が `src/twl/cli.py` 経由で引き続き動作する

## Impact

- **追加ファイル**: `cli/twl/pyproject.toml`、`cli/twl/src/twl/__init__.py`、`cli/twl/src/twl/__main__.py`、`cli/twl/src/twl/cli.py`
- **既存コード**: `twl-engine.py` はそのまま残す（中継のみ）
- **依存**: PyYAML（必須）、tiktoken・rich（オプショナル）
- **Python バージョン**: 3.10+
- **テスト**: 既存 `pytest tests/` が引き続き通過
