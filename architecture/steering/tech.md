# Tech Steering: twill plugin

twill plugin の技術選択 + 言語 constraint + tool 制約。

## 言語

| 用途 | 言語 | 根拠 |
|---|---|---|
| TWL CLI engine | Python 3.10+ | uv で依存管理、SDK 統合 (yaml/pydantic) |
| Plugin scripts (hooks/automation) | bash | Claude Code Hooks 標準、stdio JSON I/O |
| MCP server tools | Python 3.10+ | Anthropic SDK、stdio protocol |
| spec / docs | HTML | Diátaxis Reference、ReSpec semantic markup 適用 |
| ADR / steering / change package | Markdown | 業界標準 (MADR / Spec Kit) |
| test | bats (shell) + pytest (Python CLI core) | bats は plugin component test、pytest は CLI engine test |
| CI workflow | GitHub Actions YAML | merge gate enforce |

## Tool Constraint

### 必須 tool

| Tool | 用途 | 制約 |
|---|---|---|
| `bats` | plugin component test | dependency injection は test fixture (test-fixtures/) で |
| `pytest` | TWL CLI core test | uv run --extra test で実行 |
| `python3` (std lib only for hooks) | hook handler | hook script に外部 dependency 禁止 (uv subprocess 不可) |
| `vale` | prose linter (L4 pre-commit) | regexp2 で日本語日付 pattern 検出 |
| `mmdc` (mermaid-cli) | mermaid diagram syntax check | bats integration で diagram 構文検証 |

### 禁止

| 禁止事項 | 理由 |
|---|---|
| hook script から `uv` / `node` 呼び出し | hook は std lib only、起動コスト最小化 |
| spec/*.html 内に実行可能コード (bash/python/js) | R-15、デモコード drift 防止 |
| 中国語混入 (日本語 + 英語のみ) | プロジェクト規約 |
| Co-Authored-By Claude in commit message | プロジェクト規約 |
| tmux 破壊 (`kill-server` / `-C` / `-f` / `kill-session without -t`) | 2026-04-22 incident、PreToolUse hook で機械 block |

## MCP Server

| 要件 | 内容 |
|---|---|
| Protocol | stdio (JSON-RPC 2.0) |
| Server entry | `cli/twl/src/twl/mcp_server/main.py` |
| Tool 登録 | `cli/twl/src/twl/mcp_server/tools.py` |
| 新規 tool 実装 | `cli/twl/src/twl/mcp_server/tools_<domain>.py` (例: `tools_spec.py`) |
| HTML parse | `html.parser` (std lib) のみ、BeautifulSoup 不可 |
| JSON I/O | std `json` module、`indent=2` 推奨 |

## Testing

### bats (plugin component)

| location | 用途 |
|---|---|
| `tests/bats/skills/` | SKILL.md 構造 + rule 参照 静的検証 |
| `tests/bats/agents/` | agent .md frontmatter + content 静的検証 |
| `tests/bats/integration/` | cross-file 整合 (deployment + cross-repo) |
| `tests/bats/structure/` | registry.yaml / deps.yaml / chain-definition 静的検証 |
| `tests/bats/scripts/` | bash script 単体テスト + MCP tool handler 単体 + 統合 |
| `tests/bats/refs/` | ref doc 静的検証 |

### pytest (CLI core)

`cli/twl/tests/` で TWL CLI engine の unit + integration test。`uv run --extra test` で実行。

## Lint / Format

### L4 pre-commit (本 task で確立、R-19)

| Tool | 対象 | rule 例 |
|---|---|---|
| Vale | spec/*.html prose | `Twill.PastTense` / `Twill.DeclarativeOnly` / `Twill.CodeBlock` |
| textlint | changelog.html / MD | linkbreak / TODO 検出 |
| `spec-anchor-link-check.py` | spec/ link integrity | broken link 0 / orphan 0 (R-8) |
| `twl check --deps-integrity` | chain SSoT 整合 | chain.py / chain-steps.sh / deps.yaml.chains |

### L5 CI (本 task で確立、R-20)

| Workflow | 対象 |
|---|---|
| `spec-link-check.yml` | broken/orphan (R-8、既存) |
| `spec-content-check.yml` | twl_spec_content_check + Vale (新規、R-20) |
| `spec-respec-build.yml` | ReSpec CLI build success (新規、R-18) |

## Build / Deploy

twill plugin はライブラリ deploy なし (Claude Code plugin として直接読み込み)。CI は merge gate のみ。

## 参照

- `architecture/steering/product.md` — product vision + goals
- `architecture/steering/structure.md` — dir 構造 + R-N 適用範囲
- `plugins/twl/CLAUDE.md` — plugin-twl 編集フロー + Project Board + tmux 安全規約
- `plugins/twl/skills/tool-architect/refs/spec-management-rules.md` — R-1〜R-20 詳細
