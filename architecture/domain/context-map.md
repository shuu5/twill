## Context Map

```mermaid
flowchart TD
    subgraph monorepo["twill monorepo"]
        TWL_CLI["cli/twl<br/>構造検証 CLI"]
        PLUGIN_TWL["plugins/twl<br/>開発ワークフロー"]
        PLUGIN_SESSION["plugins/session<br/>セッション管理"]
        TEST_FIXTURES["test-fixtures/<br/>テストフィクスチャ"]
    end

    PLUGIN_TWL -->|"Open Host Service<br/>(twl validate/check/chain)"| TWL_CLI
    PLUGIN_TWL -->|"spawns<br/>(session:spawn/fork)"| PLUGIN_SESSION
    PLUGIN_TWL -->|"test data"| TEST_FIXTURES
```

## 依存方向ルール

| From | To | 関係 | 備考 |
|------|-----|------|------|
| plugins/twl | cli/twl | Open Host Service | PostToolUse hook, chain generate 等で呼び出し |
| plugins/twl | plugins/session | Spawns | co-autopilot が tmux セッション管理に利用 |
| plugins/twl | test-fixtures | Test Data | テスト用の固定データ |

**禁止方向**: cli/ → plugins/（CLI はプラグインを知らない）
