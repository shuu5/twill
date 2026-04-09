## ADR-0003: パッケージ構造への移行

## Status

Accepted

## Context

ADR-0001 で採用した Python 単一ファイル（twl-engine.py）は 6,074 行に成長した。
deltaspec CLI（bash 900 行）を twl に統合する計画により、さらに機能が増える。

単一ファイルの問題点:
- 関数間の依存が暗黙的で、IDE ナビゲーションが効かない
- テスト時に個別モジュールのモック差し替えが困難
- 6 つの Bounded Context が1ファイルに混在し、境界が曖昧

## Decision

`src/twl/` パッケージ構造に移行する。Bounded Context をモジュール境界とする。

```
cli/twl/
├── src/twl/
│   ├── __init__.py
│   ├── __main__.py      # python3 -m twl エントリポイント
│   ├── cli.py           # argparse サブコマンド定義
│   ├── cli_dispatch.py  # サブコマンド実装ロジック（cli.py から分離）
│   ├── core/
│   │   ├── plugin.py    # Plugin Structure: deps.yaml ロード、グラフ構築
│   │   ├── types.py     # Type System: types.yaml ロード、型ルール
│   │   └── graph.py     # 依存グラフのデータ構造と走査
│   ├── validation/
│   │   ├── check.py     # --check: ファイル存在確認
│   │   ├── validate.py  # --validate: 型ルール検証
│   │   ├── deep.py      # --deep-validate: 深層検証
│   │   └── audit.py     # --audit: 準拠度監査
│   ├── chain/
│   │   ├── generate.py  # chain generate: テンプレート生成
│   │   └── validate.py  # chain validate: 整合性検証
│   ├── viz/
│   │   ├── graphviz.py  # Graphviz DOT + SVG 生成
│   │   ├── mermaid.py   # Mermaid 出力
│   │   └── tree.py      # ASCII ツリー + Rich ツリー
│   ├── refactor/
│   │   ├── rename.py    # コンポーネント名変更
│   │   └── promote.py   # コンポーネント型変更
│   └── spec/            # deltaspec 統合
│       ├── new.py       # twl spec new
│       ├── status.py    # twl spec status
│       ├── validate.py  # twl spec validate
│       ├── archive.py   # twl spec archive
│       ├── instructions.py  # twl spec instructions
│       └── list.py      # twl spec list
├── twl                  # 極薄 bash wrapper（python3 -m twl "$@"）
├── types.yaml
├── tests/
└── pyproject.toml       # パッケージメタデータ
```

## Consequences

**良い点:**
- Context とモジュールが 1:1 対応し、境界が明確
- 個別モジュールの単体テスト・モック差し替えが容易
- `pip install -e .` で開発インストール可能
- deltaspec 統合の受け入れ先が自然に定まる

**悪い点:**
- デプロイが `cp` 1発では済まなくなる（pip install が必要）
- 移行作業の工数（既存6,074行の分割）

**緩和策:**
- pyproject.toml で `[project.scripts]` エントリポイントを定義し、`pip install -e .` 後は `twl` コマンドで直接実行可能
- bash wrapper を残すことで、pip install なしでも `python3 -m twl` 経由で動作可能
- 移行は Phase 分割で段階的に実施

**Addendum (2026-04, #265):** cli.py が 6,074 行に肥大化したため、argparse 定義（cli.py）とサブコマンド実装ロジック（cli_dispatch.py）に分割した。パッケージ構造自体は変更なし。
