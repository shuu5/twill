## Why

旧 dev plugin (claude-plugin-dev) から新 loom-plugin-dev への切替を安全に実行する必要がある。loom-plugin-dev は chain-driven + autopilot-first アーキテクチャで再構築されており、C-1〜C-5 の移行完了後にスイッチオーバーを行う。切替時のリスク（in-flight セッション中断、状態ファイル不整合、機能退行）を最小化するため、段階的な切替手順と即時ロールバック手段が必要。

## What Changes

- スイッチオーバー実行スクリプト（symlink 切替 + 事前チェック + ロールバック）の追加
- 並行検証チェックリスト（loom validate/check/audit の全 pass 確認）の策定
- 旧プラグイン設計経緯の転記（merge-gate 2パス理由、deps.yaml 競合 Phase 分離ロジック等）
- 退役手順（claude-plugin-dev リポジトリアーカイブ）の文書化

## Capabilities

### New Capabilities

- **switchover スクリプト**: symlink 切替・ロールバック・事前チェックを 1 コマンドで実行
- **並行検証手順**: 旧プラグインと同一 Issue で動作比較する検証フロー
- **設計経緯転記**: 旧 controller の設計判断を新設計文書に記録

### Modified Capabilities

- **README.md**: スイッチオーバー手順セクションの追加
- **docs/**: 切替手順・ロールバック手順・退役手順の文書群

## Impact

- **scripts/**: `switchover.sh`（新規）— symlink 切替・ロールバック・事前チェック
- **docs/**: `switchover-guide.md`（新規）— 手順書
- **docs/**: `design-decisions.md`（新規）— 旧プラグインからの設計経緯転記
- **依存**: C-1〜C-5 の全完了が前提条件
- **外部影響**: `~/.claude/plugins/dev` symlink の差し替え、旧 claude-plugin-dev のアーカイブ
