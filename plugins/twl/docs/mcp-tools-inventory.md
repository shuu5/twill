# MCP Tools Inventory — twl MCP server

統合 epic #1101 / 子 Issue #1102 成果物。
Phase 0/1 既存 5 tool の棚卸し + Phase 2 全 54 tool の拡充計画。
ADR-029 (twl-mcp-integration-strategy) Decision 2 準拠。

---

## AC1 — 既存 5 tool 棚卸し表 (Phase 0/1、verified 2026-04-29)

`cli/twl/src/twl/mcp_server/tools.py` (255 行、verified 2026-04-29) に登録済の 5 tool:

| tool 名 | 責務 | 引数 | 戻り値 | handler path | source Phase |
|---|---|---|---|---|---|
| `twl_validate` | プラグイン構造検証 (型ルール / body refs / v3 schema / chain 整合性) | `plugin_root: str \| None = None` | JSON envelope str | `tools.py:27` (`twl_validate_handler`) / `tools.py:152` (`@mcp.tool`) | Phase 0 α #962 |
| `twl_audit` | 10 セクション TWiLL コンプライアンス監査 | `plugin_root: str \| None = None, ...` | JSON envelope str | `tools.py:49` / `tools.py:157` | Phase 0 α #962 |
| `twl_check` | ファイル存在確認 + chain 整合性検査 | `plugin_root: str \| None = None, ...` | JSON envelope str | `tools.py:61` / `tools.py:162` | Phase 0 α #962 |
| `twl_state_read` | autopilot state JSON / フィールド read | `type_, issue?, repo?, field?, autopilot_dir?` | dict (`{ok, result, error_type, exit_code}`) → str | `tools.py:90` / `tools.py:167` | Phase 1 (Wave M / #1018 系) |
| `twl_state_write` | autopilot state write | `type_, role, issue?, repo?, sets?, init, autopilot_dir?, cwd?, force_done, override_reason?` | dict (`{ok, message/error, error_type, exit_code}`) → str | `tools.py:111` / `tools.py:182` | Phase 1 (Wave M / #1018 系) |

### Hybrid Path 5 原則 (Phase 0 α + ADR-006 で確立、子 2-5 全 tool に踏襲必須)

原則一覧: (1) handler pure / (2) json.dumps / (3) try/except ImportError / (4) 明示引数 / (5) 1ファイル集約

1. **handler pure**: `_handler` suffix で pure Python 関数を定義 (in-process testable、fastmcp なしで pytest 可能)
2. **json.dumps**: MCP tool は handler を `json.dumps(...)` で str 化して返す
3. **try/except ImportError**: fastmcp optional 依存を gate (`mcp = None` 時は pure 関数のみ exposed)
4. **明示引数**: `plugin_root`、`autopilot_dir`、`cwd` を明示的に受け取る (CWD 推論排除)
5. **1ファイル集約**: `cli/twl/src/twl/mcp_server/tools.py` 1 ファイル集約 (Phase 2 末期に分割、§7 参照)

実機検証 ✅: `mcp__twl__twl_validate / twl_audit / twl_check / twl_state_read / twl_state_write` が全て connected (2026-04-29 explore 起動時に deferred tool として観測)。

---

## AC4 — tool 命名規則の確定

### 規則: `twl_<module>_<action>` snake_case (MUST)

新規 tool は **必ず module prefix を付与** する。これにより:
- 衝突回避が機械的 (string match で identity 判定)
- 探索容易性 (`grep '^def twl_<module>_'` で同一 module の tool 群を抽出可)
- ADR-029 Decision 2 共通フォーマット準拠

### 既存 5 tool との互換性方針

`twl_validate / twl_audit / twl_check / twl_state_read / twl_state_write` は **変更なし** で維持する。
- Phase 0/1 で実機接続済 (degradation cost 大)
- AI session が学習している tool 名の変更は混乱の原因となる
- `twl_state_*` は既に `_read / _write` action suffix を持ち、規則と整合

### 衝突分析 (3 ケース)

| 衝突候補 | 状況 | 対応 |
|---|---|---|
| `twl_audit` (既存、plugin compliance) vs `twl_audit_*` (新規、autopilot run audit) | string match で別 tool、衝突なし | docstring で意味区別 (「autopilot execution history audit」 vs 「TWiLL plugin compliance audit」) |
| `twl_state_read/write` (既存) vs `twl_get_session_state` (子 3 新規) | 別 string、責務分離可 | 子 3 で read-heavy / observer 用と明記 |
| `twl_check` (既存) vs `twl_check_completeness / twl_check_specialist` (子 2 新規) | 別 string | docstring で「plugin file integrity check」 vs 「specialist completeness check」を区別 |

### docstring MUST rule

- docstring 1 行目に「対象 module + 主要 action」を明記 (例: "audit module: get execution history")
- `_handler` suffix は pure Python 関数に必須
- 新規 tool は `twl_<module>_<action>` 形式に限る (既存 5 tool 名の変更禁止)

---

## AC2 — 残 15 モジュール MCP 化候補 tool 案

### モジュール棚卸し (`cli/twl/src/twl/autopilot/*.py`)

`__init__.py` (1 行)、`state.py` (Phase 1 で MCP 化済)、`mergegate_guards.py` / `mergegate_ops.py` (helper / mixin、main() なし) を除外した **15 モジュール** が対象。

| # | module | 行数 | main() | 既存 CLI caller |
|---|---|---|---|---|
| 1 | `audit.py` | 310 | ✓ | 0 |
| 2 | `audit_history.py` | 362 | ✓ | 0 |
| 3 | `chain.py` | 1040 | ✓ | 0 (chain-runner.sh が独立 SSOT) |
| 4 | `checkpoint.py` | 309 | ✓ | 2 (`merge-gate-check-pr.sh`, `merge-gate-checkpoint-merge.sh`) |
| 5 | `github.py` | 739 | ✓ | 5 (`chain-runner.sh`, `project-board-backfill.sh`) |
| 6 | `init.py` | 265 | ✓ | 0 |
| 7 | `launcher.py` | 468 | ✓ | 0 |
| 8 | `mergegate.py` | 328 | ✓ | 0 |
| 9 | `orchestrator.py` | 906 | ✓ | 0 |
| 10 | `parser.py` | 315 | ✓ | 0 |
| 11 | `plan.py` | 721 | ✓ | 0 |
| 12 | `project.py` | 721 | ✓ | 0 |
| 13 | `resolve_next_workflow.py` | 88 | ✓ | 0 (orchestrator が import) |
| 14 | `session.py` | 454 | ✓ | 0 |
| 15 | `worktree.py` | 717 | ✓ | 1 (`chain-runner.sh`) |
| **合計** | | **8,043** | | |

### tool 案 (read 系 / write 系 / action 系 分類)

| module | tool 案 (R=read / W=write / A=action) | 推定 tool 数 |
|---|---|---|
| `audit` | `twl_audit_on(W/A)` / `twl_audit_off(W/A)` / `twl_audit_status(R)` / `twl_audit_snapshot(W/A)` | 4 |
| `audit_history` | `twl_audit_history_mine(R)` / `twl_audit_history_reconstruct(R)` / `twl_audit_history_compare(R)` | 3 |
| `chain` | `twl_chain_next_step(R)` / `twl_chain_quick_guard(R)` / `twl_chain_autopilot_detect(R)` / `twl_chain_quick_detect(R)` / `twl_chain_record_step(W)` / `twl_chain_export_deps(R)` / `twl_chain_export_steps_sh(R)` | 7 |
| `checkpoint` | `twl_checkpoint_read(R)` / `twl_checkpoint_write(W)` | 2 |
| `github` | `twl_github_extract_ac(R)` / `twl_github_extract_parent_epic(R)` / `twl_github_extract_closes_ac(R)` / `twl_github_resolve_project(R)` / `twl_github_get_pr_findings(R)` / `twl_github_flip_epic_ac(W/A)` / `twl_github_update_epic_ac_checklist(W/A)` / `twl_github_create_issue(W/A)` / `twl_github_add_to_project(W/A)` | 9 |
| `init` | `twl_init_session(W/A)` / `twl_init_check_session(R)` | 2 |
| `launcher` | `twl_launcher_spawn(W/A)` / `twl_launcher_record_failure(W)` / `twl_launcher_log_gate_event(W)` | 3 |
| `mergegate` | `twl_mergegate_run(W/A)` / `twl_mergegate_reject(W/A)` / `twl_mergegate_reject_final(W/A)` | 3 |
| `orchestrator` | `twl_orchestrator_phase_review(W/A)` / `twl_orchestrator_get_phase_issues(R)` / `twl_orchestrator_summary(R)` / `twl_orchestrator_resolve_repos(R)` | 4 |
| `parser` | `twl_parser_parse(R)` / `twl_parser_classify(R)` | 2 |
| `plan` | `twl_plan_generate(W/A)` / `twl_plan_validate(R)` | 2 |
| `project` | `twl_project_create(W/A)` / `twl_project_migrate(W/A)` | 2 |
| `resolve_next_workflow` | `twl_resolve_next_workflow(R)` | 1 |
| `session` | `twl_session_create(W)` / `twl_session_add_warning(W)` / `twl_session_extract_tool_calls(R)` / `twl_session_extract_skill_calls(R)` / `twl_session_extract_ai_text(R)` | 5 |
| `worktree` | `twl_worktree_create(W/A)` / `twl_worktree_delete(W/A)` / `twl_worktree_list(R)` / `twl_worktree_generate_branch_name(R)` / `twl_worktree_validate_branch_name(R)` | 5 |
| **合計** | | **54** |

### R/W/A 分布

- **R (read 系)**: 24 tool — 副作用なし、in-process pure
- **W (write 系)**: 12 tool — file write のみ、副作用は state mutation
- **W/A (write + action 系)**: 18 tool — 外部プロセス起動 / git / gh / tmux 等の副作用あり

**総 tool 数 = 54** (R: 24 / W: 12 / W&A: 18) — A 系は `timeout_sec` 引数を必須化する (§6 設計指針 4 準拠)。

---

## AC3 — #1037 Tier 0 統合計画

### 検証系 5 tool (子 2 入力確定、由来: 既存 Bash hook MCP 化)

| tool | 由来 hook | 用途 |
|---|---|---|
| `twl_validate_deps(plugin_root)` | `pre-tool-use-deps-yaml-guard.sh` | deps.yaml YAML syntax + integrity 検証 |
| `twl_validate_merge(branch, base, timeout_sec?)` | `pre-bash-merge-guard.sh` | merge 前の不変条件 (worktree, worker_window, status) 検証 |
| `twl_validate_commit(message, files, timeout_sec?)` | `pre-bash-commit-validate.sh` | commit 前の `twl --validate` 実行 |
| `twl_check_completeness(spec_path, context?)` | `check-specialist-completeness.sh` | specialist spawn manifest との突合 |
| `twl_check_specialist(spec_path)` | (新規) | specialist 設計の整合性検証 |

### 状態系 3 tool (子 3 入力確定、由来: #1037 Tier 0 状態系 + #945 Phase 2 一部)

既存 `twl_state_read / twl_state_write` (Phase 1) と責務分離。本 Issue 群は **read-heavy / observer 用** に特化。

| tool | 用途 |
|---|---|
| `twl_get_session_state(session_id?, autopilot_dir?)` | session.json 全体 read (observer 用) |
| `twl_get_pane_state(pane_id)` | tmux pane 状態 read (observer 用、ADR-014 補完) |
| `twl_audit_session(autopilot_dir?)` | session.json validate (ADR-018 SSOT 準拠) |

### 通信系 3 tool (子 5 入力確定、由来: #1037 Tier 2 + #1034 Tier C 案 A)

| tool | 用途 |
|---|---|
| `twl_send_msg(to, type_, content, reply_to?)` | sibling / supervisor / pilot へのメッセージ送信 |
| `twl_recv_msg(receiver, since?, timeout_sec?)` | メッセージ受信 (blocking 可) |
| `twl_notify_supervisor(event, payload)` | supervisor 通知専用 (su-observer ADR-014 連携) |

### 統合 tool 数まとめ

| カテゴリ | 子 Issue | tool 数 | 行数試算 |
|---|---|---|---|
| 検証系 | 子 2 | +5 | +250 |
| 状態系 | 子 3 | +3 | +150 |
| autopilot 系 第 1 Wave (mergegate / orchestrator / worktree) | 子 4 | +12 | +600 |
| 通信系 (mailbox MCP hub) | 子 5 | +3 | +180 |
| **小計 (子 2-5)** | | **+23** | **+1,180** |
| 残 12 モジュール (子 4-2 / 4-3 で段階起票) | | ~+31 | ~+1,550 |
| **Phase 2 完了総計** | | **~54** | **~2,730** |

---

## AC5 — MCP RPC stdio deadlock 設計指針

### #754 真因分析の逆輸入 (H1 + H3)

#754 では 4 並列 Worker が CRG MCP server に同時 RPC を発行した結果:

- **H1 (並列スケーラビリティ)**: 同一ホスト上で複数プロセスが tree-sitter 共有リソースで競合
- **H3 (RPC stdio half-deadlock)**: CRG プロセス内部 deadlock または write block で stdio buffer flush 不可、Worker LLM が `ep_poll` / `unix_stream_data_wait` で無限待機

`maxTurns: 10` は LLM turn 消費前提のガードのため、RPC 応答待ち中は無効。最終対処は `timeout 600 + uvx CLI ラップ` で MCP RPC を回避。参照: `plugins/twl/docs/crg-auto-build-hang-analysis.md`

### 子 2-5 全 tool に適用される 6 MUST design rule

1. **Long-running tool は CLI ラップを優先**: 重い計算 / 外部プロセス起動は handler 内で `subprocess.run(timeout=...)` を使うか Bash CLI 経由で呼ばせる
2. **並列 RPC 衝突点を特定**: 同一 file/lock を read-modify-write する tool 群は flock 持続時間 << timeout を保証 (ADR-028 atomic RMW 準拠)
3. **stdio buffer flush guard**: handler 内で long-running 出力を生成する場合は `logging.basicConfig(stream=sys.stderr)` を server 起動時に明示
4. **action 系 tool には `timeout_sec` 引数を必須**: 上限を設計時に決定 (CRG 600s 教訓継承、デフォルトは tool 性質ごとに設定)
5. **graceful fail**: timeout 到達時は `{ok: false, error: "timeout", error_type: "timeout", exit_code: 124}` で返す。RPC 自体は完了させる
6. **依存方向の明確化**: tool が他 Bounded Context の internal モジュールを import する場合、context-map.md の OHS 方向 (TWiLL Integration → 該当 Context) と整合する依存方向を維持する contract を子 Issue body に明記

### 並列 RPC hang 予防ルール表 (5 観点)

| 観点 | ルール |
|---|---|
| 同時実行 tool 数 | FastMCP は async handler を 1 server プロセス内で sequential 実行。Worker 数 = MCP server プロセス数 (並列 Worker 各々が独立 server に接続) |
| stdio chunk size | FastMCP の MCP message size limit を超える長文出力を返さない (1 tool あたり JSON envelope < 1 MB 推奨) |
| handler 内 stdin 待機禁止 | handler 内で `input()` / `sys.stdin.read()` を呼んではならない (RPC stdio と衝突) |
| log 経路 | `print` → stdout はメッセージ汚染の可能性。`logging` 経由で `stream=sys.stderr` のみ使う |
| spawn 系 tool の wait timeout | `twl_launcher_spawn`、`twl_orchestrator_phase_review`、`twl_mergegate_run` 等は `timeout_sec` を必須引数にし、wall-clock guard を組み込む |

---

## AC6 — 子 Issue 2-5 詳細 AC

## 子 Issue 共通フォーマット (ADR-029 Decision 2 準拠、全子 Issue MUST)

各子 Issue body は以下 9 項目を含む (全子 Issue に MUST 適用):

- [ ] **共通-1**: 対象 module / tool 名の確定 (本 inventory §AC2 の表を参照) — MUST
- [ ] **共通-2**: handler 関数 (pure Python、in-process testable) の追加 (`_handler` suffix 必須) — MUST
- [ ] **共通-3**: MCP tool 登録 (`@mcp.tool()` decorator + `try/except ImportError` gate) — MUST
- [ ] **共通-4**: pytest による handler unit test (fastmcp 経由 + 直接呼出 2 経路、両方で PASS) — MUST
- [ ] **共通-5**: 既存 bash wrapper / bats test の互換性維持確認 — MUST
- [ ] **共通-6**: `tools.py` (or 分割後の `tools_*.py`) の行数増加 + drift 確認 (`twl --validate` PASS) — MUST
- [ ] **共通-7**: Bounded Context 整合 contract (必要時): tool が他 Bounded Context の internal モジュールを import する場合、OHS 方向と整合する依存方向を維持する contract を子 Issue body に明記 — MUST
- [ ] **共通-8**: ADR-028 整合確認: write 経路追加時、ADR-028 の write authority matrix への追記要否を判定 — MUST
- [ ] **共通-9**: action 系 tool は `timeout_sec` 引数を必須化 (§AC5 設計指針 4 準拠) — MUST

### 子2: 検証系 (validation)

由来: #1037 Tier 0「検証系 tool 追加」、既存 Bash hook の MCP 化前提。
effort: 2-3 日。依存: 子 1 完了。

- [ ] **AC2-1**: 5 tool 追加 — `twl_validate_deps(plugin_root) / twl_validate_merge(branch, base, timeout_sec?) / twl_validate_commit(message, files, timeout_sec?) / twl_check_completeness(spec_path, context?) / twl_check_specialist(spec_path)`
- [ ] **AC2-2**: 各 handler は pure Python (in-process testable)、Hybrid Path 5 原則準拠
- [ ] **AC2-3**: pytest 5 件 (各 tool)、fastmcp 経由 + 直接呼出 2 経路で PASS
- [ ] **AC2-4**: 既存 Bash hook (`pre-tool-use-deps-yaml-guard.sh` / `pre-bash-merge-guard.sh` / `pre-bash-commit-validate.sh` / `check-specialist-completeness.sh`) は維持
- [ ] **AC2-5**: action 系 tool (`twl_validate_merge`, `twl_validate_commit`) に `timeout_sec` 引数を追加し、graceful timeout fail を実装 (`{ok: false, error_type: "timeout", exit_code: 124}`)
- [ ] **AC2-6**: tools.py 行数 + drift 確認 (`twl --validate` PASS) + 累計行数 ~505 確認
- [ ] **AC2-7**: Bounded Context 整合 contract: `validate_*` 系は cli/twl 内部完結のため、TWiLL Integration → cli/twl の OHS 方向と整合

### 子3: 状態系 (state)

由来: #1037 Tier 0「状態系 tool 追加」+ #945 Phase 2 一部。既存 `twl_state_read/write` との責務分離。
effort: 2 日。依存: 子 1 完了 (子 2 と並走可)。

- [ ] **AC3-1**: 3 tool 追加 — `twl_get_session_state(session_id?, autopilot_dir?) / twl_get_pane_state(pane_id) / twl_audit_session(autopilot_dir?)`
- [ ] **AC3-2**: 既存 `twl_state_read / twl_state_write` (Phase 1) と責務分離 (本 Issue は read-heavy / observer 用、ADR-018 SSOT 準拠)
- [ ] **AC3-3**: handler は pure Python、Hybrid Path 5 原則準拠
- [ ] **AC3-4**: pytest 各 tool が PASS (fastmcp + 直接呼出)
- [ ] **AC3-5**: ADR-028 整合確認: session.json read 経路追加では race リスクなし、ADR-028 改訂は不要 (要確認のみ Issue body に明記)
- [ ] **AC3-6**: flock(2) 整合性: bash `flock(8)` と Python `fcntl.flock()` が同一 syscall で相互排他可能なことを bats で検証 (既存 ADR-028 整合)
- [ ] **AC3-7**: tools.py 行数 + drift 確認、累計 ~655 行
- [ ] **AC3-8**: Bounded Context 整合 contract: state 系は Autopilot Context internal を読むため、TWiLL Integration → Autopilot の OHS 方向と整合 (handler 内 import 規約を明記)

### 子4: autopilot系 (mergegate / orchestrator / worktree)

由来: #945 Phase 2 (AC9) 第 1 Wave。
effort: 3-5 日。依存: 子 1 完了 (子 2/3 と並走可)。

- [ ] **AC4-1**: mergegate 系 3 tool 追加 — `twl_mergegate_run(pr_number, autopilot_dir?, timeout_sec=600) / twl_mergegate_reject(pr_number, reason, ..., timeout_sec=300) / twl_mergegate_reject_final(pr_number, reason, ..., timeout_sec=300)`
- [ ] **AC4-2**: orchestrator 系 4 tool 追加 — `twl_orchestrator_phase_review(phase, plan_file, autopilot_dir?, timeout_sec=1800) / twl_orchestrator_get_phase_issues(phase, plan_file) / twl_orchestrator_summary(autopilot_dir) / twl_orchestrator_resolve_repos(repos_json)`
- [ ] **AC4-3**: worktree 系 5 tool 追加 — `twl_worktree_create(branch, base="main", ..., timeout_sec=300) / twl_worktree_delete(branch, ..., timeout_sec=120) / twl_worktree_list() / twl_worktree_generate_branch_name(issue_number, repo?) / twl_worktree_validate_branch_name(branch)`
- [ ] **AC4-4**: handler は既存 `cli/twl/src/twl/autopilot/{mergegate,orchestrator,worktree}.py` の pure 関数を直接呼ぶ (Phase 1 state.py の Hybrid Path 継承)
- [ ] **AC4-5**: 不変条件 B (Worktree ライフサイクル Pilot 専任) を `twl_worktree_create / _delete` に組み込み (handler 内で role check、Worker からの呼び出しは StateError で拒否)
- [ ] **AC4-6**: pytest 各 tool (12 件)、fastmcp + 直接呼出で PASS
- [ ] **AC4-7**: 既存 bash wrapper / bats test 互換性維持確認 (`plugins/twl/scripts/worktree-*.sh`、`mergegate-*.sh` 等)
- [ ] **AC4-8**: #945 AC9 充足の宣言 + 手動更新タスク: 本 Issue merge 時に Pilot/Observer が `gh issue view 945` で AC9 を確認 + body 直接編集で `[x]` に更新 + memory に AC9 充足を記録 (ADR-029 Decision 3 準拠)
- [ ] **AC4-9**: tools.py 分割実施判断: 累計行数 ~1,255 → 1,500 行到達直前の判断点。ADR-029 Mitigations の 4 ファイル分割案 (§7) を参照し、分割 PR を別 Issue 起票するか本 Issue 内で実施するかを判定 (子 4 worker 判断、Pilot 承認)
- [ ] **AC4-10**: Bounded Context 整合 contract: autopilot 系 tool は Autopilot Context internal モジュール (`mergegate.py`, `orchestrator.py`, `worktree.py`) を直接 import するため、context-map.md の TWiLL Integration → Autopilot の OHS 方向と整合
- [ ] **AC4-11**: ADR-028 整合確認: `twl_mergegate_run` / `twl_orchestrator_phase_review` で session.json への write 経路が追加されるため、ADR-028 §Implementation の write authority matrix への追記が必要 (同 ADR 改訂 PR を本 Issue とセット起票)

### 子5: 通信系 (mailbox MCP hub)

由来: #1037 Tier 2 + #1034 Tier C 案 A。#1033 close trigger。
effort: 4-6 日。依存: 子 1, 2 完了。

- [ ] **AC5-1**: 3 tool 追加 — `twl_send_msg(to, type_, content, reply_to?) / twl_recv_msg(receiver, since?, timeout_sec=0) / twl_notify_supervisor(event, payload)`
- [ ] **AC5-2**: dispatch ロジックは MCP server 内部で管理 (file-based jsonl + flock or in-memory dict; 子 5 explore で再判断)
- [ ] **AC5-3**: bidirectional / sibling 通信の dispatch table 設計 (送信側 to / 受信側 receiver の名前空間を確定、衝突回避ルール)
- [ ] **AC5-4**: handler は pure Python、Hybrid Path 5 原則準拠
- [ ] **AC5-5**: pytest 各 tool が PASS。**並列 100 メッセージ送受で損失ゼロ** が必須 (concurrent.futures + ThreadPoolExecutor で検証)
- [ ] **AC5-6**: `twl_recv_msg` の `timeout_sec=0` は non-blocking poll、`timeout_sec>0` は blocking。timeout 到達時は `{ok: true, msgs: []}` で graceful return
- [ ] **AC5-7**: #1033 close: 本 Issue merge により #1033 (Tier C 単独 Issue) を rationale "新統合 epic 子 5 に吸収" で close (自動化検討)
- [ ] **AC5-8**: tools.py 分割: 子 4 で分割済の前提で `tools_comm.py` に追加 (累計 ~1,435 行)
- [ ] **AC5-9**: Bounded Context 整合 contract: comm 系は Communication Context (新設候補 / 既存 Autopilot Context 配下のサブ) として位置づけ、context-map.md 更新の必要性を子 5 で判定
- [ ] **AC5-10**: ADR-028 整合確認: `twl_send_msg` / `twl_recv_msg` で mailbox file への write 経路が追加されるため、ADR-028 write authority matrix への追記要否を子 5 で判定

---

## AC7 — ADR-029 整合性確認

本 Issue 成果物が ADR-029 Decision 1-4 と整合することを確認:

| ADR-029 Decision | 本 inventory での反映 | 整合状況 |
|---|---|---|
| **Decision 1**: 部分統合 (案 B) | 本 Issue が「新統合 epic 子 1」として ADR-029 構造に従い起票 | ✅ |
| **Decision 2**: 5 子 Issue 構造 + 共通フォーマット AC | §AC6 で子 2-5 詳細 AC を確定、共通フォーマットを各子 Issue に展開 | ✅ |
| **Decision 3**: #945/#1034/#1036/#1037 更新方針 | §AC6 子 4 AC4-8 で #945 AC9 手動更新タスク明記、§AC6 子 5 AC5-7 で #1033 close trigger 明記 | ✅ |
| **Decision 4**: Wave 単位実行 + controller 振り分け | Wave 1 (子 1) → Wave 2 (子 2/3/4 並走) → Wave 3 (子 5) を確認 | ✅ |

不整合: **なし**。ADR-029 改訂 PR の必要性は **不要**。

---

## §7 — tools.py 行数試算 + 分割 proposal (ADR-029 Mitigations 準拠)

### 行数試算 (verified 2026-04-29)

| 段階 | tool 数 | 累計行数 |
|---|---|---|
| 現状 | 5 | 255 |
| 子 2 完了 | 10 | ~505 |
| 子 3 完了 | 13 | ~655 |
| 子 4 完了 | 25 | ~1,255 ← **分割判断点** |
| 子 5 完了 | 28 | ~1,435 |
| Phase 2 末期 (残 12 module 取り込み完了) | ~54 | ~2,985 |

### 分割 proposal (4 ファイル)

| 分割ファイル | 含む tool | 推定行数 |
|---|---|---|
| `tools.py` (entry, 共通 helper, Phase 0/1 5 tool) | `twl_validate / twl_audit / twl_check / twl_state_read / twl_state_write` | ~300 |
| `tools_validation.py` (子 2) | `twl_validate_deps / _merge / _commit / twl_check_completeness / _specialist` | ~250 |
| `tools_state.py` (子 3) | `twl_get_session_state / _pane_state / twl_audit_session` | ~150 |
| `tools_autopilot.py` (子 4 + 残 12 module) | mergegate / orchestrator / worktree + 残 12 module tool 群 | ~1,800 |
| `tools_comm.py` (子 5) | `twl_send_msg / _recv_msg / twl_notify_supervisor` + dispatch logic | ~250 |

分割実施タイミング: **子 4 第 1 Wave merge 後** (累計 ~1,500 行到達直前)。
import 互換性: `tools.py` から `from .tools_<X> import *` で集約し、外部 caller の import path は変更不要。

---

## 親 epic body 更新 input (AC6-6)

親 epic #1101 body 更新のための入力情報をまとめる。実際の body 更新は本 Issue merge 後 observer 経由で実施 (本 Issue scope 外)。

### 子 2-5 起票順序 + Wave 計画

| Wave | 対象子 Issue | 並走可否 | 依存 |
|---|---|---|---|
| Wave 2-A | 子 2 (検証系 5 tool) | — | 子 1 完了 |
| Wave 2-B | 子 3 (状態系 3 tool) | 子 2 と並走可 | 子 1 完了 |
| Wave 2-C | 子 4 (autopilot 系 12 tool) | 子 2/3 と並走可 | 子 1 完了 |
| Wave 3 | 子 5 (通信系 3 tool) | — | 子 1, 2 完了 |

pitfalls 11.3「≤2 並列 MUST」のため、Wave 2 の 3 件並走時は段階化必須 (co-issue refine → co-autopilot 順次起動)。

### 本 Issue merge trigger

本 Issue (#1102) merge により以下を実施:
- 親 epic #1101 body の子 Issue チェックリスト `[ ] 子 1` を `[x] 子 1` に更新
- 子 2-5 起票の入力として本 inventory を参照
- ADR-029 Decision 4 の Wave 計画を更新

## 変更が必要な spec 一覧 (AC9 参照)

| spec ファイル | 本 Issue での変更 | 子 2-5 での更新 |
|---|---|---|
| `plugins/twl/architecture/domain/glossary.md` | 4 用語追加 (epic / MCP server / MCP tool / tools.py) | — |
| `plugins/twl/architecture/domain/contexts/twill-integration.md` | Phase 2 章 stub 追加 | 各子 Issue 完了後に更新 |
| `plugins/twl/architecture/domain/context-map.md` | — | Phase 2 完了時に依存方向更新 |
