## 1. su-compact コマンド実装

- [ ] 1.1 `plugins/twl/commands/su-compact.md` を新規作成（atomic コマンド）
- [ ] 1.2 引数なし時の自動判定ロジック（タスク状態・Wave サマリ検出）を実装
- [ ] 1.3 `--wave` オプション: Wave 完了サマリ → Memory MCP 保存 → /compact
- [ ] 1.4 `--task` オプション: タスク状態 → `.supervisor/working-memory.md` 退避 → /compact
- [ ] 1.5 `--full` オプション: 全知識外部化 → /compact
- [ ] 1.6 `refs/memory-mcp-config.md` 参照で Memory MCP ツール名を解決する処理を追記

## 2. deps.yaml 登録

- [ ] 2.1 `plugins/twl/deps.yaml` に `su-compact` エントリを追加（type/path/dependencies）
- [ ] 2.2 `twl --check` が通ることを確認
