## Why

旧 dev plugin (claude-plugin-dev) は複雑性ホットスポットが累積し、controller の責務重複・状態管理の分散・specialist 出力の不統一が保守性を低下させている。loom-plugin-dev として新規構築するにあたり、chain-driven + autopilot-first アーキテクチャの設計を architecture/ に体系的に文書化し、後続 Issue（B-2〜B-7）の実装基盤を確立する必要がある。

## What Changes

- architecture/ ディレクトリの設計文書を完成させる（既存の vision.md, domain/, decisions/, contracts/ を補完）
- 全コンポーネントの旧→新マッピング表を作成する
- 主要ワークフロー（autopilot lifecycle, merge-gate, project create）の OpenSpec シナリオを作成する
- specialist 共通出力スキーマ、model 割り当て表、bare repo 検証ルール、worktree ライフサイクルルールを明文化する
- B-3/C-4 スコープ境界定義を追加する

## Capabilities

### New Capabilities

- **コンポーネントマッピング表**: 旧 dev plugin の全コンポーネントと新 loom-plugin-dev の対応関係を一覧化
- **OpenSpec シナリオ**: autopilot lifecycle, merge-gate, project create の主要フローを WHEN/THEN 形式で定義
- **Specialist 共通出力スキーマ仕様**: status/severity/confidence/findings の標準フォーマット定義
- **Model 割り当て表**: haiku(4件)/sonnet(23件)/opus(controller) の割り当て基準
- **B-3/C-4 スコープ境界定義**: セッション構造変更(B-3) vs インターフェース適応(C-4) の分類

### Modified Capabilities

- **architecture/ 既存文書の補完**: vision.md, domain/model.md, decisions/ADR-* は存在するが、不足する詳細（bare repo 検証ルール、worktree 安全ルール等）を追記

## Impact

- **影響範囲**: architecture/ ディレクトリ配下のみ（コード変更なし）
- **後続 Issue への影響**: B-2〜B-7 の全 Issue がこの設計文書を参照して実装を進める
- **依存**: loom#13 (chain generate) 完了済み
