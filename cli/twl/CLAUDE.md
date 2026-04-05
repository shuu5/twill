# twl

TWiLL フレームワークの CLI ツール。Claude Code プラグインの構造定義・検証・可視化を提供する。

## 構成

- モノリポ: `~/projects/local-projects/twill/main/cli/twl/`

## 開発ルール

- テスト: `pytest tests/` で全テスト実行
- 型定義: `types.yaml` が型システムの SSOT
- CLI: `twl-engine.py` が全機能の統合エントリポイント、`twl` がラッパースクリプト

## ディレクトリ構造

```
cli/twl/
├── twl-engine.py        # CLI エンジン本体
├── twl                  # ラッパースクリプト
├── types.yaml           # 型定義 SSOT
├── architecture/        # アーキテクチャ仕様
├── docs/                # フレームワークドキュメント（ref-*.md）
├── tests/               # pytest テスト
│   └── scenarios/       # シナリオテスト
└── openspec/            # 変更仕様
```
