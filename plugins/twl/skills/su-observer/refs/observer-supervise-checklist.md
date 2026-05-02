# observer supervise checklist

supervise loop 各 cycle で MUST verify する 7 項目チェックリスト（#1189 AC9.2）。

## cycle MUST verify チェックリスト

1. **MUST**: Monitor primary break condition が controller type に対応しているか確認
   → `refs/monitor-channel-catalog.md` の「controller type 別 primary completion signal mapping」table を参照
2. **MUST**: `IDLE_COMPLETED_AUTO_KILL=1` が Wave 起動時 env として設定されているか確認
3. **MUST**: window 消失単独依存ではなく多軸 AND 条件（completion phrase event + window 消失 OR session-state idle）を採用しているか確認
4. **SHOULD**: log mtime / pane state / LLM idle indicator の少なくとも 2 軸で session 状態を判定しているか確認
5. **SHOULD**: completion phrase の grep regex が `refs/pilot-completion-signals.md` SSOT と一致しているか確認
6. **MAY**: STAGNATE event 監視 task が起動しているか確認（長時間 idle 時の自動介入用）
7. **MAY**: Discord DM 自律報告 channel が活きているか確認（compaction 後の reset 検知用）

## 使用タイミング

`refs/su-observer-supervise-channels.md` の supervise 1 iteration 開始時に参照する（SHOULD）。

各チャンネル起動前に本 checklist を確認し、未設定の項目があれば起動前に補完すること。
