## ADR-0001: Python 単一ファイルアーキテクチャ

## Status

Accepted

## Context

loom CLI は Claude Code プラグインの構造検証・可視化ツールとして開発された。
配布先は多様な開発環境（ホスト、コンテナ、CI）であり、依存関係の管理コストを最小化する必要があった。

検討した選択肢:
1. **単一ファイル（loom-engine.py）**: 外部依存最小、コピーだけでデプロイ可能
2. **パッケージ構造（src/loom/）**: モジュール分割による保守性向上、pip install でデプロイ
3. **Go/Rust バイナリ**: シングルバイナリ配布、高速実行

## Decision

Python 単一ファイル（loom-engine.py）で全機能を実装する。

理由:
- Claude Code プラグインのエコシステムが Python スクリプトを前提としている
- `python3 loom-engine.py` だけで動作し、pip install やビルドステップが不要
- 必須外部依存は PyYAML のみ（ほぼ全環境にプリインストール）
- tiktoken と rich はオプショナルで、なくても全機能が動作する

## Consequences

**良い点:**
- デプロイが `cp loom-engine.py /target/` で完結
- CI/コンテナ環境で追加セットアップ不要
- loom ラッパースクリプト経由でパス解決を抽象化

**悪い点:**
- ファイルサイズが 4000 行超に成長。関数間の依存が暗黙的
- IDE のナビゲーション（モジュール単位のジャンプ）が使えない
- テスト時に個別モジュールのモック差し替えが困難

**緩和策:**
- 関数の命名規則で論理的なモジュール境界を表現（例: `chain_*`, `audit_*`, `validate_*`）
- loom 自身の `--audit` / `--complexity` で自己検証可能
