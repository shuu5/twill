# twl

TWiLL フレームワークの CLI ツール。Claude Code プラグインの構造定義・検証・可視化��提供する。

## 構成

- bare repo: `~/projects/local-projects/twill/.bare`
- main worktree: `~/projects/local-projects/twill/main/`
- feature worktrees: `~/projects/local-projects/twill/worktrees/<branch>/`

## 開発ルール

- テスト: `pytest tests/` ���全テスト実行
- 型定義: `types.yaml` が型システムの SSOT
- CLI: `twl-engine.py` が全機能の統合エントリ���ポイント、`twl` がラッパースクリプト

## ディレクトリ構���

```
main/
├── twl-engine.py        # CLI エンジン本体
├── twl                  # ラッパースクリプト
├── types.yaml           # 型定義 SSOT
├── docs/                # フレームワークドキュメント（ref-*.md）
├── tests/               # pytest テスト
│   └── scenarios/       # シナリオテスト
└── openspec/            # 変更仕様
```
