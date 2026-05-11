# ADR-041: feature-dev spawn を spawn-controller.sh に統合し新 MCP tool を wrapper 化（co-autopilot pattern 統一）

## Status

Accepted (2026-05-11)

## Context

### 経緯

- **ADR-040 / Wave U.X (#1635, PR #1636)**: `mcp__twl__twl_spawn_feature_dev` MCP tool を新設し、承認証跡 + TTL + Status=Refined + parallel-spawn gate を Python で実装。cld-spawn を直接呼び出す pattern を採用
- **Wave U.Y dogfooding**: 上記実装で 4 bug が顕在化
  - **bug-1**: `_SPAWN_CONTROLLER_SCRIPT` の `Path.parent × 5` で `/main/cli` 起点（× 6 が正解）
  - **bug-2**: `_CLD_SPAWN_SCRIPT` 同 pattern
  - **bug-3**: handler 内 cld-spawn 直接呼び出しで skill prefix (`/feature-dev:feature-dev #<N>`) prepend が欠落（spawn-controller.sh L437 logic の再実装欠落）
  - **bug-4**: dogfooding 中の commit `d6cb9859`（docs-only ADR 編集）が **main 直接 push** で混入
- **user 訂正（2026-05-11）**: 「成功している co-autopilot pattern と統一せよ」「最適な方法を考えろ」
- **option D 採択**: spawn-controller.sh に feature-dev path を統合し、新 MCP tool を薄い wrapper に refactor する

### bug 全体構造

| Bug | 現象 | 根本原因 |
|---|---|---|
| bug-1 | `_SPAWN_CONTROLLER_SCRIPT` path 誤算 | `Path.parent × 5` で `cli/` 起点。bash 側で SCRIPT_DIR 自己解決すれば回避可能 |
| bug-2 | `_CLD_SPAWN_SCRIPT` 同 pattern | 同上 |
| bug-3 | skill prefix prepend 欠落 | Python 側で cld-spawn 直接 invoke。Pattern A (spawn-controller.sh L437) の `/<plugin>:<skill>` prepend logic を再実装していない |
| bug-4 | main 直接 push incident | cld session が `main/` worktree で起動 + bug-3 で skill skip → 自由形式 session → main 直接 push。feature-dev plugin に PR cycle 強制は無い |

### 構造的設計判断

1. **Pattern 統一**: 成功している co-autopilot pattern（spawn-controller.sh 経由 + skill prefix prepend + provenance + size guard + worktree + hook）を feature-dev にも適用すれば、bug-1〜bug-3 を**構造的に消去**できる
2. **多層防御の継承**: spawn-controller.sh L437 の `/twl:<skill>` prefix logic を skill 別分岐に拡張し、`/feature-dev:feature-dev #<N>` 形式を支援する。pre-push hook + prompt 注入の二段で main 直接 push (bug-4) を防止
3. **API 維持**: MCP tool は薄い wrapper として維持（DP-1）。observer からの呼び出し点は不変

## Decision

`mcp__twl__twl_spawn_feature_dev` を `spawn-controller.sh feature-dev <issue-number>` 経由の薄い wrapper に refactor する。承認証跡 gate + worktree 作成 + hook 設置 + skill prefix prepend + provenance + main push 防止プロンプト注入は **全て bash 側 (`spawn-controller.sh` feature-dev path)** に集約する。

### 三層変更

| Phase | 変更内容 | bug 対応 |
|---|---|---|
| **Phase 1**: spawn-controller.sh 統合 | feature-dev を VALID_SKILLS に追加。L437 prefix logic を skill 別分岐（`co-*` → `/twl:<skill>`、`feature-dev` → `/feature-dev:feature-dev #<N>`）に拡張。承認証跡 gate (schema + TTL + atomic rename) を bash で再実装。引数インタフェース拡張（`feature-dev <issue-number> [opts]`） | bug-1/2/3 構造的消去 |
| **Phase 2**: 新 MCP tool wrapper 化 | `twl_spawn_feature_dev_handler` を `subprocess.run(["bash", spawn_controller_sh, "feature-dev", str(issue), ...])` の薄い wrapper に変更。`_SPAWN_CONTROLLER_SCRIPT` / `_CLD_SPAWN_SCRIPT` 参照を handler 内から除去 | bug-1/2 を Python 側からも消去 |
| **Phase 3**: main 直接 push 防止 | `install-git-hooks.sh --worktree <PATH>` 新オプション (per-worktree `core.hooksPath = .fd-hooks/`)。spawn-controller.sh feature-dev path で skill prefix 直後に「MUST: worktree 内作業 + PR 経由 merge」を prompt 注入（多層防御 — SKILL.md 単独不足 lesson の踏襲） | bug-4 防止 |

### Skill prefix 分岐方式（DP-2）

規約ベース + hardcoded fallback を採用:
- `co-*` skill → `/twl:<skill>`（既存動作不変）
- `feature-dev` → `/feature-dev:feature-dev #<ISSUE>`
- その他: 必要時に declare 配列で明示マップ

理由: feature-dev は外部公式 plugin で `plugins/feature-dev/.claude-plugin/plugin.json` が存在しないため、plugin metadata file 判定は機能しない。規約 + 明示マップが最確実。

### Worktree 作成の責務

- spawn-controller.sh feature-dev path が `--cd <PATH>` 未指定時に **auto-create** する
- 命名: `$TWILL_ROOT/worktrees/fd-<ISSUE>` (branch=`fd-<ISSUE>`)
- idempotent: 既存ディレクトリならスキップ
- Invariant B（worktree ライフサイクル Pilot 専任）非違反: spawn-controller.sh は `main/` Pilot コンテキストから呼ばれる
- `--cd <PATH>` 指定時は worktree 作成をスキップし、その path に hook のみ設置

### pre-push hook 設置方式（DP-3）

per-worktree (`core.hooksPath = .fd-hooks/`) 方式:
- worktree 内に `.fd-hooks/pre-push` を作成
- `git -C <worktree> config core.hooksPath .fd-hooks` で対象 worktree のみに適用
- 他 worktree（main 含む）には影響しない
- bypass: `git push --no-verify`（ユーザー裁量）

### atomic rename 実装方針

- 同 filesystem: `mv -n` (atomic rename + no-clobber、並列呼び出しの 2 重消費を防ぐ)
- 異 filesystem: cross-device エラー検出後 `cp + rm` フォールバック
- race lost: source 不在検出で別プロセスが既に消費したと判定

### Migration

- `SKIP_LAYER2=1` escape hatch は **2 wave 維持**（DP-5、AC-4.6）— 完全削除は Wave U.W+2 で別 Issue
- 旧 MCP tool 直接呼び出しパターンは廃止。新 MCP tool は wrapper として API 維持（DP-1）
- 旧 bats (`issue-1620-feature-dev-fallback.bats`、`issue-1635-feature-dev-spawn-gate.bats`) は `skip` 化でアーカイブ（削除せず、設計履歴を保持）

### 採択しなかった選択肢

| Option | 不採用理由 |
|---|---|
| E (minimal: #1637 の path bug × 2 のみ fix) | bug-3 (skill prefix 欠落) と bug-4 (main push) が残る。divergence 期間中に再 bug の risk |
| F (full deprecate: 新 MCP tool 完全削除、observer 側に承認証跡 skill 追加) | MCP tool は #1635 で 1 wave 前に landed したばかり。即削除は破壊的 |
| G (hybrid: Phase 1 のみ実施、Phase 2 遅延) | divergence 期間中に再 bug の risk。Phase 1 + Phase 2 セットで bug 構造的消去 |

## Consequences

### Positive

- bug-1/2/3 の構造的消去（path resolution / skill prefix が bash 側 L437 で保証）
- bug-4 防止（pre-push hook + prompt 注入の二段）
- co-autopilot pattern との一貫性（多層防御の共有: provenance / size guard / window 命名 / SUPERVISOR_DIR validation）
- 旧 Python 側 gate logic 削除により MCP tool は ~150 行 → ~90 行に簡素化（保守コスト低減）
- bats テスト基盤の latent bug（CLD_SPAWN 絶対パス sed-replace で TWILL_ROOT が誤解決）を `CLD_SPAWN_OVERRIDE` env var 方式に migrate

### Negative

- bash 側 gate logic は Python 版より読みにくい（jq + date + grep の組み合わせ）。bats による意味的等価性検証で担保
- SKIP_LAYER2=1 escape hatch の semantics 変化（旧: fallback 手順表示 + exit 0、新: gate bypass + cld-spawn 実行）。2 wave 維持期間中に既存ユーザーの再学習コスト
- bats wrapper の sed-replace 方式から `CLD_SPAWN_OVERRIDE` env override 方式への migrate により、既存 9 spawn-controller-*.bats の wrapper を一括更新（test 本文の SUPERVISOR_DIR 絶対パス問題は **pre-existing bug** として別途調整が必要）

### Followups

- **SKIP_LAYER2=1 完全削除**: Wave U.W+2 の別 Issue で実施（DP-5）
- **#1637 close**: AC-1〜AC-2 完了確認後、`superseded by #1644` として close（AC-4.7）
- **既存 spawn-controller-*.bats の SUPERVISOR_DIR 絶対パス問題**: 各テストの個別調整は別 tech-debt Issue で対応（本 refactor のスコープ外、pre-existing wrapper bug が露呈させた問題）
- **ADR-037 二重採番**: `issue-creation-flow-canonicalization` と `stuck-pattern-ssot` の番号衝突は本 refactor と直交 → 別 tech-debt Issue で整理

## main 直接 push incident（commit `d6cb9859`）

### 経緯

- **2026-05-11**: Wave U.Y dogfooding 中、co-explore からの自律フローで commit `d6cb9859` (`docs(adr): ADR-024 Phase C 計画追加 (refs #1625)`) が **main 直接 push** された
- 内容性質: docs-only（ADR-024 Phase C taxonomy 計画を追記）、Epic #1625 child Issue 起票と整合した前方計画記載
- 直接の root cause: 新 MCP tool (Pattern B) は cld-spawn を直接 invoke し、spawn-controller.sh の skill prefix prepend (L437) を bypass → cld session が自由形式 → feature-dev plugin の PR cycle 強制が無い → main 直接 push に到達

### Rollback 判定

**rollback 不要** と判定（AC-5.1）。理由:
- 内容が valid（ADR-024 Phase C は #1625 epic と整合）
- docs-only のため動作影響なし
- rollback は履歴を汚すだけで価値が小

### 再発防止策

- **Phase 3 (AC-3.x)**: pre-push hook で worktree 内からの main push を block
- **Phase 1 (AC-3.2)**: spawn-controller.sh feature-dev path で MUST 注入（「worktree 内作業」「PR 経由 merge」「main 直接 push 禁止」）
- 多層防御: hook（機械的 enforcement）+ prompt（行動規律）の二段構え

## 関連

- 前段: ADR-040（#1635、本 refactor の対象）
- close 候補: #1637（3 bug fix、本 refactor で obsolete）
- 上位 Epic: ADR-024（5-stage Status taxonomy、#1625 と直交）
- 関連教訓: SKILL.md 単独不足 lesson（Wave 32）— 機械的ガード + prompt の多層防御が必要
- pre-existing bats wrapper bug: TWILL_ROOT が temp script コピー後 `/` に誤解決される問題（本 refactor で `CLD_SPAWN_OVERRIDE` env var 方式に migrate して回避）
