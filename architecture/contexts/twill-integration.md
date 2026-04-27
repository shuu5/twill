# twill-integration (Phase 0 γ #964 更新済み)

## 概要

`cli/twl` を **MCP server 経由で提供**するコンテキスト境界。

- **Phase 0 α (#962)**: FastMCP stdio server 実装（`cli/twl/src/twl/mcp_server/`）
- **Phase 0 β (#963)**: cli.py if-chain → SSoT pure 関数化
- **Phase 0 γ (#964)**: Deploy 戦略確立（`.mcp.json` Path B primary 採用）

## 提供ツール (Phase 0)

| MCP ツール名 | 対応 twl コマンド | 説明 |
|---|---|---|
| `twl_validate` | `twl validate` | 型ルール・body refs・v3 schema・chain 整合性の検証 |
| `twl_audit` | `twl audit` | 10 セクションにわたる TWiLL コンプライアンス監査 |
| `twl_check` | `twl check` | ファイル存在確認と chain integrity チェック |

## OHS (Open Host Service) パターン拡張

cli/twl の公開インターフェースは従来の CLI コマンドに加えて MCP ツールとして **二重チャネル化** されている。

| チャネル | コマンド | 用途 |
|---|---|---|
| CLI | `twl validate/audit/check` | 直接実行・CI・degradation path |
| MCP | `twl_validate/twl_audit/twl_check` | AI session からの呼び出し |

plugins/twl からの呼び出し経路選択は plugins/twl 側の責務。

## インターフェース

```
stdio MCP server (FastMCP, Layer 1 系のみ Phase 0)
```

## 起動方法

開発時の手動起動（MCP auto-connect とは独立した手順）:
```bash
cd cli/twl
uv run --extra mcp fastmcp run src/twl/mcp_server/server.py
```

AI session からの自動接続は下記「Deploy 戦略」セクションを参照。

## Deploy 戦略 (Phase 0 γ)

> 「起動方法」セクション（手動起動）との違い: 本セクションは AI session からの **自動接続経路** を扱う。

### 採用方針: Path B (.mcp.json) primary

`.mcp.json` を git-tracked で管理することで、全 worktree・将来の全ホスト・コンテナへ `git pull` のみで配布する。

**Path B primary 採用理由**:
- `.mcp.json` は **per-repo MCP 設定の SSOT**（deps.yaml/types.yaml とは責務領域が異なる）
- git checkout / git worktree add 時に自動継承（追加の deploy 手順不要）
- 既存 code-review-graph entry と共存（JSON merge で冪等追加）

### MCP サーバー設定 (`.mcp.json` エントリ)

```json
{
  "mcpServers": {
    "twl": {
      "type": "stdio",
      "command": "uv",
      "args": [
        "run",
        "--directory",
        "/home/shuu5/projects/local-projects/twill/main/cli/twl",
        "--extra", "mcp",
        "fastmcp", "run",
        "src/twl/mcp_server/server.py"
      ],
      "env": {}
    }
  }
}
```

**`--directory` 絶対パス制約 (Phase 0)**:
`/home/shuu5/projects/local-projects/twill/main/cli/twl` を hardcode。
ipatho-1 / shuu5 user 依存であり、他ホストへ展開時に無音失敗する。
**Phase 1 で相対化する方針**（worktree の WIP は main merge まで反映されない点も含めて改善対象）。

### worktree 振る舞い

`.mcp.json` は git-tracked であるため、`git worktree add` で作成された全 worktree に自動継承される。`main/.mcp.json` が単一 source of truth。

```
twill/main/.mcp.json (git-tracked, per-repo MCP 設定 SSOT)
       │ git checkout / git worktree add
       ▼
全 worktree が同一 .mcp.json を保持
```

### host scope (Phase 0 γ)

**ipatho-1 only**。Phase 1 で以下を展開予定:
- ipatho-2（host expansion 別 Issue）
- コンテナ 3 種（omics-dev / webapp-dev / repordev）— Python/uv 有無の事前調査が前提
- Path C（plugin manifest `mcpServers`）— enabledPlugins 整理後に再評価

### Path A (将来検討)

user-global 用途（`~/.claude.json` の `mcpServers`）。
Path B と重複・衝突しない merge 戦略が必要。別 Issue で議論予定（ipatho-1 では現在不在）。

### CLI fallback (degradation path)

MCP server 接続成功時も、CLI 直接呼び出しは引き続き機能する（degradation path として）:

```bash
cd cli/twl && uv run --extra mcp twl --validate
```

**Phase 1 実装予定 — MCP server 起動失敗時の自動 fallback**:
- 現 Phase 0 では MCP 接続失敗時の自動 degradation は未実装
- Phase 1 で plugins/twl 側に fallback ロジックを追加する
- 必要な検証項目: (1) MCP 接続状態の検知方法、(2) CLI への自動切り替えトリガー、(3) fallback 時のユーザー通知

## Phase 1: state MCP 化 (#945 Epic)

### 概要

`twl.autopilot.state` の MCP server 経由公開。Epic #945 の AC6/AC7/AC8 で設計範囲を定義する。

- **AC6**: bats PASS 100% 維持で `twl.autopilot.state` を MCP 化
- **AC7**: CLI と MCP の SSoT 検証（integration test or shared coverage）
- **AC8**: AI 失敗率 50% 以上削減を統計的に実証（binomial proportion test, α=0.05, N≥20/操作）

### state MCP 化方針（Phase 0 Hybrid Path 継承）

Phase 0 α (#962) / β (#963) で確立した core パターンを Phase 1 でも適用する:

1. **`_handler` suffix で pure Python 関数を定義** — `fastmcp` なしで pytest 可能
2. **MCP tool は handler を `json.dumps(...)` で str 化して返す**
3. **`try/except ImportError` で fastmcp optional 依存を gate** — `mcp = None` 時は pure 関数のみ exposed
4. **明示引数化**（Phase 0 `plugin_root` → Phase 1 `autopilot_dir`）で CWD 推論を排除
5. **`tools.py` 1 ファイルに集約** — `cli/twl/src/twl/mcp_server/tools.py` に append

### 既存 state.py 構造との整合（relevant fact）

`StateManager` class は **既に pure (kwargs-based)**。Phase 0 β #963 で行った "handler を pure kwargs 化 + `sys.exit()` 除去" 相当の作業は **不要** である。

このため Phase 1 α 実装は **MCP wrapper の minimal scope** で済む:

- `state.py` の `_parse_*_args(argv)` / `main(argv)` は **touch しない**（CLI 経路保全）
- `tools.py` に `twl_state_read_handler` / `twl_state_write_handler` を追加
- `StateError` / `StateArgError` を `{ok, error, error_type, exit_code}` envelope に wrap

### autopilot_dir resolution 設計

#### 問題

`state.py` 内 `_autopilot_dir()` の git worktree fallback ロジックは、MCP server 起動時の cwd と AI session の作業ディレクトリが異なるため、意図通り動作しない可能性がある（server プロセスは起動時の cwd で fix される）。

#### 解決方針

MCP tool に **`autopilot_dir: str | None = None` を明示引数化** し、AI session 側で正しい絶対パスを渡せるようにする:

```python
def twl_state_read_handler(
    type_: str,
    issue: str | None = None,
    repo: str | None = None,
    field: str | None = None,
    autopilot_dir: str | None = None,
) -> dict:
    from twl.autopilot.state import StateManager
    from pathlib import Path
    ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
    return StateManager(autopilot_dir=ap_dir).read(...)
```

省略時は `_autopilot_dir()` の既存 fallback ロジックに委ねる（CLI 経路と同一挙動）。

### RBAC enforcement の cwd 引数設計

#### 問題

`_check_pilot_identity`（state.py）は `os.getcwd()` を参照して role authentication を行うが、MCP server context では cwd が不定。bats 経路（CLI）では `os.getcwd()` が AI session の cwd を反映するため整合する。

#### 解決方針

MCP tool に **write 時のみ `cwd: str | None = None` を明示引数化** し、`_check_pilot_identity(cwd=cwd)` に伝播する:

```python
def twl_state_write_handler(
    type_: str,
    role: str,
    ...,
    autopilot_dir: str | None = None,
    cwd: str | None = None,    # ← RBAC enforcement のため明示
) -> dict:
    # StateManager.write 経由で _check_pilot_identity(cwd=cwd) に伝播
```

`cwd` 省略時は `os.getcwd()` fallback（CLI 経路と同一挙動）。bats 互換性は維持される（CLI 経路の `os.getcwd()` 参照は変更しない）。

### bats 経路と MCP 経路の SSoT 担保

#### 検証戦略

3 経路で同一 input に対する出力一致を検証する pytest parametric test を新設（`cli/twl/tests/test_state_dispatch_parity.py` 想定）:

| 経路 | 呼び出し | 検証目的 |
|---|---|---|
| 1 | `subprocess.run(['python3', '-m', 'twl.autopilot.state', 'read', ...])` | bats 経路と同等（CLI exit code / stdout） |
| 2 | `twl_state_read_handler(...)` | MCP handler（in-process） |
| 3 | `StateManager(...).read(...)` | Python 直接呼び出し（lowest layer） |

正規化規則:

- read 経路: 値の str 比較
- write 経路: `{ok, exit_code, error_type}` 三組比較
- 経路 1（subprocess）は stdout/stderr を分離して比較

最低 6 比較ケース（issue read with field / full JSON / session read / init / status transition / RBAC violation）。

#### bats 互換性（regression risk = 0）

`state.py` の `main()` / `_parse_*_args()` は **未変更**。bats は CLI 経路を呼び続けるため、構造的に regression risk は 0 となる（MCP 化が独立的拡張であることが保証されている）。

### Phase 0 OHS 二重チャネル拡張

「OHS パターン拡張」セクションは Phase 0 のスナップショット。Phase 1 完了後の二重チャネル状態は以下のとおり拡張される:

| チャネル | コマンド | 用途 | Phase |
|---|---|---|---|
| CLI | `twl validate/audit/check` | 直接実行・CI・degradation path | 0 |
| CLI | `python3 -m twl.autopilot.state read/write` | bats / shell hook | 既存 |
| MCP | `twl_validate / twl_audit / twl_check` | AI session（Phase 0） | 0 |
| MCP | `twl_state_read / twl_state_write` | AI session（Phase 1） | 1 |

### 関連 ADR

- **ADR-0006 (cli/twl)**: state MCP 化 SSoT pattern — 本 Phase の中心 ADR
- **ADR-028 (plugins/twl)**: session.json `flock(2)` atomic strategy — MCP 経路の Python `fcntl.flock()` と bash `flock(8)` は同一 `flock(2)` syscall で相互排他されるため、MCP 化後も lost-update リスクは増加しない

## 依存関係

- `fastmcp>=3.0` (optional, `mcp` extra — `pyproject.toml` の `[project.optional-dependencies]`)
- `twl` コアロジック (`twl.validation`, `twl.chain`, `twl.core`)
