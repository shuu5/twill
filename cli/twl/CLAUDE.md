# twl

TWiLL フレームワークの CLI ツール。Claude Code プラグインの構造定義・検証・可視化・変更仕様管理を提供する。

## 構成

- モノリポ: `~/projects/local-projects/twill/main/cli/twl/`
- Python パッケージ: `src/twl/`（pip install -e . で開発インストール）
- エントリポイント: `twl` bash wrapper → `python3 -m twl` → `src/twl/cli.py:main()`

## 開発ルール

- テスト: `pytest tests/` で全テスト実行
- 型定義: `types.yaml` が型システムの SSOT
- 依存: PyYAML 必須、tiktoken/rich はオプショナル（`pip install -e ".[full]"`）
- CLI: `src/twl/cli.py` が argparse ベースのコマンドディスパッチ

## ディレクトリ構造

```
cli/twl/
├── twl                  # bash wrapper（python3 -m twl "$@"）
├── pyproject.toml       # パッケージメタデータ・依存定義
├── types.yaml           # 型定義 SSOT
├── src/twl/
│   ├── cli.py           # argparse サブコマンドディスパッチ
│   ├── core/            # Plugin Structure, Type System, グラフ走査
│   ├── validation/      # check, validate, deep-validate, audit, complexity
│   ├── chain/           # chain generate, chain validate
│   ├── viz/             # graphviz, mermaid, tree 出力
│   ├── refactor/        # rename, promote
│   ├── spec/            # twl spec（変更仕様管理）
│   └── autopilot/       # 状態管理・オーケストレーション・merge-gate・プロジェクト管理
├── architecture/        # アーキテクチャ仕様
├── tests/               # pytest テスト
│   └── scenarios/       # シナリオテスト
```
