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

## Architecture Spec 三層継承関係

```mermaid
flowchart TD
    subgraph arch_layers["Architecture Spec 層"]
        MONO["architecture/<br/>Monorepo層<br/>(vision, model, glossary)"]
        CLI_ARCH["cli/twl/architecture/<br/>CLI層<br/>(vision, domain, decisions)"]
        PLUGIN_ARCH["plugins/twl/architecture/<br/>Plugin層<br/>(vision, domain, decisions)"]
        SESSION_ARCH["plugins/session/architecture/<br/>Session Plugin層<br/>(vision, domain)"]
    end

    MONO -->|"制約継承<br/>(依存方向の一方向性)"| CLI_ARCH
    MONO -->|"制約継承<br/>(TWiLL フレームワーク準拠)"| PLUGIN_ARCH
    MONO -->|"制約継承<br/>(一方向依存・read-only観察)"| SESSION_ARCH
```

| 層 | パス | 役割 |
|----|------|------|
| Monorepo | `architecture/` | モノリポ全体の上位制約・コンポーネント間依存ルール |
| CLI | `cli/twl/architecture/` | twl CLI 固有の設計制約・型システム・検証ルール |
| Plugin | `plugins/twl/architecture/` | ワークフロープラグイン固有の設計制約・autopilot 仕様 |
| Session Plugin | `plugins/session/architecture/` | tmux セッション操作の抽象化層。spawn/fork/observe の3概念を定義 |

## 依存方向ルール

| From | To | 関係 | 備考 |
|------|-----|------|------|
| plugins/twl | cli/twl | Open Host Service | PostToolUse hook, chain generate 等で呼び出し |
| plugins/twl | plugins/session | Spawns | co-autopilot が tmux セッション管理に利用 |
| plugins/twl | test-fixtures | Test Data | テスト用の固定データ |

**禁止方向**: cli/ → plugins/（CLI はプラグインを知らない）
