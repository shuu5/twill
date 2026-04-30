# plugin-session

tmux セッション管理 plugin。Claude Code の tmux ウィンドウ操作（spawn/observe/fork）と状態検出を提供する。

<!-- DEPS-GRAPH-START -->
| From | To |
|------|-----|
<!-- DEPS-GRAPH-END -->

## cld-observe-any 自律再起動（SessionStart hook 設定例）

ADR-031 (option B) に基づく設定。`cld-observe-any-launcher` を SessionStart hook から呼び出すことで、observer Claude session crash 後の resume 時に自動再起動する。

### 設定方法

`~/.claude/settings.json` または `twill/main/.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "pgrep -f 'cld-observe-any$' >/dev/null 2>&1 || bash /home/<user>/projects/local-projects/twill/main/plugins/session/scripts/cld-observe-any-launcher --window <監視ウィンドウ名>"
          }
        ]
      }
    ]
  }
}
```

**注意**: `~/.claude/settings.json` への追加は本 PR スコープ外。host 側 dotfiles 管理リポジトリで別途実施すること（ADR-031）。

### event ファイル

launcher は以下の event ファイルを出力する（`EVENT_DIR` または `CLD_OBSERVE_ANY_EVENT_DIR` 環境変数で指定）:

| ファイル名 | 出力タイミング | スキーマ |
|---|---|---|
| `daemon-down-<ts>.json` | 前回 PID が死亡していた場合 | `{event, reason, ts, pid}` |
| `daemon-startup-failed-<ts>.json` | 起動失敗時 | `{event, reason, ts}` |
