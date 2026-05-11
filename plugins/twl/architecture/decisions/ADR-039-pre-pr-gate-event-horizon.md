# ADR-039: PR 作成段階 event horizon — chain step reorder + pre-pr-gate hook

## Status

Proposed (2026-05-09)

## Context

### 観察された失敗パターン (Wave T、PR #1631、2026-05-09 ipatho-2 takeover)

`#1626` (PR #1629) が **B+C+D defense (merge 段階)** を main landed (`c57e6902`) した直後の Wave T 観察:

| 項目 | 値 |
|---|---|
| PR | #1631 (#1581 active hook bug fix Issue) |
| changedFiles | 2 (両方 test ファイル) |
| additions / deletions | 661 / 0 |
| labels | `red-only` (Worker が自発付与) |
| mergeStateStatus | CLEAN |
| mergeable | MERGEABLE |
| ac-verify checkpoint | FAIL (12 CRITICAL: 実装ファイル不在) |
| 次 chain step | `workflow-pr-fix` で GREEN 実装 |

→ **test-only PR が一時的に main merge 候補状態 (CLEAN)** になり、ac-verify で初めて「実装不在」を検出して fix phase で GREEN 実装する冗長 flow。`#1626` の B+C+D defense は最後の防壁として動作するが、**event horizon を「PR 作成段階」「GREEN 実装段階」へ前倒しすべき**。

### ユーザー指摘 (2026-05-09 15:54 JST)

> 「なんで test だけ作って実装しないでそのまま先に進んじゃうの？」

→ event horizon 前倒しの必要性確定。

### 構造的真因

#### 真因 1: chain step ordering が GREEN 実装フェーズを必須化していない

`workflow-test-ready` chain は `test-scaffold → check` のみ。Worker は test scaffold 完了直後に PR を作成し、GREEN 実装は後段 `workflow-pr-fix` に委ねられる。これは **TDD のフェーズ分離としては合理的だが、Defense in Depth の観点から event horizon が遅すぎる**。

#### 真因 2: PR 作成段階の事前抑止が不在

`gh pr create` を実行する PreToolUse hook が存在せず、test-only diff の検出は `ac-verify` step (PR 作成後) で初めて行われる。RED-only PR が短時間でも main merge 候補状態になることを防げない。

#### 真因 3: `#1626` defense の event horizon

`merge-gate-check-red-only.sh` (`#1626`) は **merge 段階** で動作し、PR 作成と merge の間の時間窓 (test-only PR が CLEAN 状態の期間) をカバーしない。この時間窓は壁時計上は短いが、autopilot の自動進行下では検証スキップによる主目的逸脱を許す可能性がある。

## Decision

**Defense in Depth の前倒し (3 段防衛体制)** を採用する。`#1626` の merge 段階 defense を保持しつつ、**GREEN 実装段階** と **PR 作成段階** に事前抑止を追加する。

### 3 段防衛体制

| 段階 | 責務 | 実装 | 既存/新設 |
|------|------|------|-----------|
| **GREEN 実装段階** | Worker が test-scaffold 直後に impl を生成 | `chain.py` `green-impl` step + `tdd-green-guard.sh` | **新設** |
| **PR 作成段階** | `gh pr create` 試行時に test-only diff を ABORT | `pre-bash-pre-pr-gate.sh` PreToolUse hook | **新設** |
| **merge 段階** (既存) | `red-only` label + follow-up 不在を REJECT | `merge-gate-check-red-only.sh` | `#1626` |

### chain step reorder

`workflow-test-ready` chain を:

```
test-scaffold → check
```

から:

```
test-scaffold → green-impl → check
```

に変更する。`green-impl` step は LLM dispatch (`commands/green-impl.md` を Read → 実行) で、内部的に `ac-scaffold-tests` agent を **`mode=green`** で呼び出して RED test を PASS させる実装を生成する。

### `pre-bash-pre-pr-gate.sh` PreToolUse hook

`gh pr create` 実行時に以下を AND 条件で deny:

1. `tool_input.command` に `gh pr create` が含まれる
2. `git diff --name-only origin/main` の結果が **test ファイルのみ** (`*.bats`, `*test_*.py`, `*.test.ts` 等)
3. 対象 Issue に `tdd-followup` または `test-only` label が **不在**

bypass: `SKIP_PRE_PR_GATE=1 SKIP_PRE_PR_GATE_REASON='<理由>'` で通過 (REASON 必須、`/tmp/pre-pr-gate-bypass.log` に audit)。

### Anthropic 公式仕様準拠

PreToolUse hook の deny は **JSON output (`hookSpecificOutput.permissionDecision: "deny"`) + exit 0** を採用。`exit 2 + stderr` は `permissionDecisionReason`/`additionalContext` と組み合わせ不可なため非推奨 (https://code.claude.com/docs/en/hooks)。

### Issue #1633 AC2 仕様逸脱の記録

Issue #1633 AC2 は `ac-scaffold-tests` agent の frontmatter に `inputs: {mode: ...}` を追加する仕様だったが、Anthropic 公式 subagent 仕様 (https://code.claude.com/docs/en/sub-agents) に **`inputs` フィールドは存在しない** ため、frontmatter 拡張ではなく **本文記述 + 自然言語 prompt** で同等機能を実現した。frontmatter は Claude Code がパースしても処理せず LLM にも見えないため、Issue 仕様通りでは機能しない。

## Consequences

### Positive

- **event horizon の前倒し**: `#1626` の事後検出 (merge 段階 REJECT) が事前抑止 (PR 作成段階 ABORT) に格上げ。autopilot 進行下でも test-only PR が main merge 候補状態にならない
- **Defense in Depth の強化**: 3 段防衛で、いずれかの層が fail-open しても他層が catch する冗長性
- **Worker 規律の構造化**: SKILL prompt 内の警告 (`#1626` で確認した「効かない」教訓) ではなく、機械的 hook + chain ordering で強制
- **観察可能性**: bypass log (`/tmp/pre-pr-gate-bypass.log`) で濫用パターンを定量検出可能

### Negative / Trade-offs

- **chain step 数増加** (16 → 17): autopilot 1 サイクルあたり LLM dispatch 1 件追加 (green-impl)。effort/cost が約 5-10% 増加
- **Worker 作業負荷の前倒し**: test-scaffold 直後に GREEN 実装まで完了する責務が Worker に移る (従来は workflow-pr-fix に委譲)。学習コストあり
- **既存 RED-only test (`tests/bats/ac-scaffold-tests-*.bats`) との後方互換**: `mode=red` を default 維持することで担保。既存 test の挙動は変更されない
- **Issue 仕様逸脱**: Issue #1633 AC2 の frontmatter inputs 部分は公式仕様非対応のため実装を本文記述に変更。同等機能だが Issue 文言とは厳密一致しない (本 ADR で明示記録)

### Migration Path

1. chain.py 5 辞書に `green-impl` を追加 (本 ADR を含む単一 PR 内で同期)
2. `twl chain export --shell --yaml --write` で chain-steps.sh + deps.yaml.chains を再生成
3. `pre-bash-pre-pr-gate.sh` を `.claude/settings.json` の `PreToolUse.Bash.hooks` に登録
4. 既存 `tdd-red-guard.sh` に bats 対応を追加 (twill リポジトリの test 多数派 bats への対応強化、対称的に `tdd-green-guard.sh` も bats 対応)
5. bats test 13 シナリオ (hook 8 + green-guard 5) で機能検証

### Future Considerations

- `red-only` label の semantic 矛盾 (Wave T で観察された「GREEN 実装後も `red-only` label が残存して merge 通過」現象) は別 Issue として分離。本 ADR の scope 外
- `tdd-red-guard.sh` も本 PR で bats 対応を追加 (対称性を維持)
- bypass log (`/tmp/pre-pr-gate-bypass.log`) の nightly cron 監査は別 Issue で検討

## References

- Issue #1633 — 本 ADR 起票元
- Issue #1626 — B+C+D defense (merge 段階)、本 ADR が補完
- Issue #1623, #1621 — Wave 92 RED-only merge 再発
- Issue #1612, #1614 — Wave 91 RED-only merge 連続発生
- ADR-022 — chain SSoT 境界 (chain.py / chain-steps.sh / deps.yaml.chains)
- ADR-024 — Refined Status field migration
- ADR-037 — 2 ファイル重複 (`stuck-pattern-ssot.md` / `issue-creation-flow-canonicalization.md`)、`ADR-038` 採番済のため本 ADR は `ADR-039`
- ADR-038 — Lesson 28 RED-only label-based bypass の構造的閉塞
- 不変条件 R — content-REJECT override 禁止 (`#1626` 由来)
- 不変条件 S — RED-only PR の merge 禁止 (`#1626` 由来、本 ADR で前倒し)
- Anthropic 公式 hooks 仕様 — https://code.claude.com/docs/en/hooks
- Anthropic 公式 subagent 仕様 — https://code.claude.com/docs/en/sub-agents
