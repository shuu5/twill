# loom

Loom フレームワークの CLI ツール。Claude Code プラグインの構造定義・検証・可視化を提供する。

## 構成

- bare repo: `~/projects/local-projects/loom/.bare`
- main worktree: `~/projects/local-projects/loom/main/`
- feature worktrees: `~/projects/local-projects/loom/worktrees/<branch>/`

## 開発ルール

- テスト: `pytest tests/` で全テスト実行
- 型定義: `types.yaml` が型システムの SSOT
- CLI: `loom-engine.py` が全機能の統合エントリーポイント、`loom` がラッパースクリプト

## ディレクトリ構成

```
main/
├── loom-engine.py       # CLI エンジン本体
├── loom                 # ラッパースクリプト
├── types.yaml           # 型定義 SSOT
├── docs/                # フレームワークドキュメント（ref-*.md）
├── tests/               # pytest テスト
│   └── scenarios/       # シナリオテスト
└── openspec/            # 変更仕様
```
