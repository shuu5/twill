## ADR-0006: state MCP 化 SSoT pattern

## Status

Proposed（#945 Epic Phase 1 開始時点）

## Context

`twl.autopilot.state`（`cli/twl/src/twl/autopilot/state.py`、586 行）は autopilot Pilot/Worker による issue/session JSON 状態管理を担う core モジュールである。Phase 0（Wave A-C）で `cli/twl` の OHS（Open Host Service）が CLI/MCP の二重チャネル化を達成したのち、`state` 系操作を MCP 経由でも提供する必要がある（Epic #945 AC6/AC7/AC8）。

### 現状（verified）

- `StateManager` class は **既に pure (kwargs-based)**。Phase 0 β #963 で行った "handler を pure kwargs 化 + `sys.exit()` 除去" 相当の作業は不要。
- `state.py` の CLI 層は `_parse_read_args(argv)` / `_parse_write_args(argv)` / `main(argv)` で構成されており、副作用は `print(result)` / `print(msg)` のみ。
- bats test は 4 ファイル / 37 tests、全てが `python3 -m twl.autopilot.state` を CLI 経由で呼ぶ。Python in-process callers は `plugins/twl/scripts/` / `hooks/` 内に **0 件**。
- Phase 0 で確立した Hybrid Path（`_handler` suffix + `json.dumps()` + `try/except ImportError`）は `cli/twl/src/twl/mcp_server/tools.py:1-122` で採用済み。

### 検討した選択肢

| 案 | 概要 | Trade-off |
|---|---|---|
| **A. Hybrid Path 継承（採用）** | `_handler` pure 関数 + `@mcp.tool()` wrapper、明示引数で CWD 推論排除 | Phase 0 と同一パターン → reviewer 慣れ済み、minimal scope |
| B. StateManager 直接 expose | `@mcp.tool()` を `StateManager` method に直接付与 | クラスに `fastmcp` 依存が混入、bats 経路の純度が崩れる |
| C. 別 module 化 | `mcp_server/state_tools.py` 新設 | tools.py 一極集中の Phase 0 方針と非対称、import path 増加 |

### 関連する architectural concern

- **OHS 二重チャネルの SSoT**: CLI/MCP 経路が同一の出力を返すことを構造的に保証する必要がある（AC7）
- **autopilot_dir resolution**: MCP server 起動時 cwd は AI session の作業ディレクトリと異なる
- **RBAC enforcement**: `_check_pilot_identity` は `os.getcwd()` を参照し、MCP context では cwd が不定
- **session.json 並行書き込み**: ADR-028（plugins/twl）で確立した bash `flock(8)` と Python `fcntl.flock()` の syscall 互換性

## Decision

`state` 系の MCP 化は **Phase 0 Hybrid Path パターンを継承し、StateManager の pure 性を活かして minimal wrapper scope で実装する**。

### 1. Hybrid Path パターン継承（5 原則）

1. `_handler` suffix で pure Python 関数を定義（`fastmcp` なしで pytest 可能）
2. MCP tool は handler を `json.dumps(...)` で str 化して返す
3. `try/except ImportError` で `fastmcp` optional 依存を gate（`mcp = None` 時は pure 関数のみ exposed）
4. 明示引数化（`autopilot_dir: str | None`、`cwd: str | None`）で CWD 推論を排除
5. `cli/twl/src/twl/mcp_server/tools.py` 1 ファイルに append（Phase 0 と同位置）

### 2. state.py 未変更原則

- `class StateManager` の interface（`read()` / `write()`）を維持
- CLI 層 `main(argv)` / `_parse_*_args(argv)` は touch しない
- `tools.py` に `twl_state_read_handler` / `twl_state_write_handler` を新設し、`StateError` / `StateArgError` を `{ok, error, error_type, exit_code}` envelope に wrap

これにより bats 経路（CLI）の regression risk は構造的に 0 となる（変更箇所と非交差）。

### 3. autopilot_dir / cwd 明示引数化

```python
def twl_state_read_handler(
    type_: str,
    issue: str | None = None,
    repo: str | None = None,
    field: str | None = None,
    autopilot_dir: str | None = None,
) -> dict: ...

def twl_state_write_handler(
    type_: str,
    role: str,
    issue: str | None = None,
    repo: str | None = None,
    sets: list[str] | None = None,
    init: bool = False,
    autopilot_dir: str | None = None,
    cwd: str | None = None,           # ← RBAC enforcement のため明示
    force_done: bool = False,
    override_reason: str | None = None,
) -> dict: ...
```

- `autopilot_dir` 省略時は `_autopilot_dir()` の既存 fallback ロジックに委ねる（CLI 経路と同一）
- `cwd` 省略時は `os.getcwd()` fallback（CLI 経路と同一挙動）
- bats 互換性: CLI 経路は引き続き `os.getcwd()` を内部参照（変更不要）

#### 適用範囲（明示）

**`autopilot_dir` / `cwd` の明示引数化は MCP handler 専用設計**である。CLI 層 `main(argv)` は既存どおり以下の挙動を維持する:

- `_parse_*_args(argv)` は `--cwd` / `--autopilot-dir` オプションを **持たない**
- `mgr.write()` 呼び出し時に `cwd` を渡さない（`_check_pilot_identity(cwd=None)` → `os.getcwd()` fallback）
- `_autopilot_dir()` の既存 git worktree fallback ロジックがそのまま機能する

これにより bats 経路（CLI subprocess）と MCP 経路（in-process handler）の両方で `_check_pilot_identity` の挙動が整合する: CLI は process cwd を参照、MCP は明示引数 or process cwd（fallback）を参照。

### 4. SSoT 検証（AC7 satisfaction）

3 経路 pytest parametric test を新設（`cli/twl/tests/test_state_dispatch_parity.py` 想定）:

| 経路 | 呼び出し | 検証目的 |
|---|---|---|
| 1 | `subprocess.run(['python3', '-m', 'twl.autopilot.state', 'read', ...])` | bats 経路と同等（CLI exit code / stdout） |
| 2 | `twl_state_read_handler(...)` | MCP handler（in-process） |
| 3 | `StateManager(...).read(...)` | Python 直接呼び出し（lowest layer） |

正規化規則:
- read 経路: 値の str 比較
- write 経路: `{ok, exit_code, error_type}` 三組比較
- 経路 1（subprocess）は stdout/stderr を分離して比較

最低 6 比較ケース: issue read with field / full JSON / session read / init / status transition / RBAC violation。

### 5. ADR-028（plugin 層 flock(2)）との整合

ADR-028（`plugins/twl/architecture/decisions/ADR-028-atomic-rmw-strategy.md`）で確立した session.json `flock(8)` advisory lock との整合は **将来の B-1 実装時に確立される**。本 ADR の MCP 化単体では新規 race を導入しないが、Python 経路の `fcntl.flock()` 適用は B-1 と本 ADR が同時実装される段階で発効する。

#### 現状（Phase 1 開始時点）の事実

- `state.py` の `_atomic_write` は `tempfile.mkstemp` + `os.replace` による **atomic rename のみ**であり、現時点で `fcntl.flock()` は呼ばれていない（verified at L371-378）
- ADR-028 の write authority matrix における Python 経路（`session_id` / `cross_issue_warnings[]` 等の `_atomic_write` 経路）は「B-1 委譲」として現状未保護
- 本 ADR の MCP wrapper も同じ `_atomic_write` を経由するため、**MCP 化単体では Python 経路 race の状況は現状維持**（悪化しない）

#### B-1 実装時の整合戦略（forward-looking）

ADR-028 「B-1 統合時の Python wrapper interface」が実装される段階で `_atomic_write` に `fcntl.flock(LOCK_EX)` が追加される。この追加は本 ADR の MCP wrapper にも自動で適用される（同一コードパスを経由するため）。発効後は以下が syscall 層で成立する:

- bash `flock(8)` と Python `fcntl.flock()` は同一 `flock(2)` syscall を用いる advisory lock であり、**プロセス境界をまたいで相互排他可能**
- MCP server 経由の write は in-process Python から `_atomic_write` + `fcntl.flock(LOCK_EX)` を呼ぶため、外部 bash `flock(8)` 保護されている caller（autopilot-retrospective.md 等）との競合時も lost-update を発生させない
- ADR-028 「B-1 統合時の Python wrapper interface」と本 ADR の MCP wrapper は **同一 syscall 層で交差** する設計

本 ADR は B-1 と独立に merge 可能だが、上記 syscall 層の整合は B-1 実装後に有効となる点を明示する。

## Consequences

### Positive

- **bats regression risk = 0**: state.py CLI 層が touch されないため、既存 37 tests は変更不要で PASS 維持
- **Phase 0 reviewer 慣性活用**: `cli/twl/src/twl/mcp_server/tools.py` 同位置 + 同パターンで append → review コスト最小
- **AC7 SSoT 検証の構造的保証**: 3 経路 parametric test により CLI/MCP 出力一致が CI で保証される
- **CWD 不定問題の解決**: `autopilot_dir` / `cwd` 明示引数化により MCP server 起動時 cwd 依存性が排除される
- **plugin 層との syscall 整合**: ADR-028 で確立した `flock(2)` advisory lock が MCP 経路でも継続有効

### Negative / Tradeoffs

- **`fastmcp` optional 依存の継続**: `mcp = None` gate により Phase 0 の `try/except ImportError` パターンを維持（保守負荷が新規発生はしない）
- **AC8 測定の独立性**: AI 失敗率測定は別 Issue（推奨案 B β）で実施。本 ADR の scope は AC6/AC7 のみ
- **subprocess 経路 test の overhead**: parametric test 経路 1 の subprocess spawn は test 実行時間を増加させる（許容範囲、CI で並列化可能）

### Future considerations（本 ADR 範囲外）

- **state 以外の autopilot module の MCP 化**: `worktree.py` / `cross_repo.py` 等は別 Phase で評価
- **`_check_pilot_identity` の cwd 引数 deprecation**: 将来的に identity を環境変数や config に外出しする選択肢
- **logging.basicConfig stderr 強制化**: stdio safety の保険として server 起動時に追加検討（Phase 0 で採用済み、本 ADR では state 系で再確認）
- **architecture 三層整合性の追従更新**（本 PR で defer、別 Issue 化候補）:
  - `architecture/domain/model.md` の classDiagram に MCP channel と `+state_read()` / `+state_write()` を追記
  - `architecture/domain/context-map.md` の mermaid 図に `AI_SESSION` ノードを外部アクターとして描画
  - `architecture/domain/glossary.md` に "AI session"・"OHS Hybrid Path"・"Bounded Context (AI session)" を用語定義として追加
  - これらは PR scope 拡大を避けるため本 ADR では deferred。Wave M Step 3 (co-issue) で別 Issue として起票候補

## Related

- ADR-028 (plugins/twl) — session.json `flock(8)` advisory lock。MCP 経路 Python `fcntl.flock()` との syscall 整合
- ADR-0001..0005 (cli/twl) — Phase 0 で確立した cli/twl パッケージ構造・型システム
- Issue #945 — Epic「`cli/twl` MCP server 化」
- Issue #962 (Phase 0 α) — FastMCP MCP server PoC（`tools.py` 初版 + Hybrid Path pattern 確立）
- Issue #963 (Phase 0 β) — `cli.py` if-chain SSoT pure 関数化（state.py の pure 性確認の precedent）
- Issue #964 (Phase 0 γ) — `.mcp.json` Path B 配布
- `architecture/contexts/twill-integration.md` § Phase 1 — 本 ADR の context 上位文書
- `architecture/domain/context-map.md` § 依存方向ルール — AI session → cli/twl (MCP channel) の規定
- `.explore/945-phase1/summary.md` — Wave M Step 1 deliverable（本 ADR の input）
