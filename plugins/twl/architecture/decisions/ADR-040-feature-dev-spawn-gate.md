# ADR-040: feature-dev spawn gate — user 明示依頼許可 + MCP tool 化 + Status gate（SU-10 改訂）

## Status

Accepted (2026-05-11)

## Context

### 経緯

- **#1620 (ADR-038 と同時期)**: SU-10 を新設し、observer が feature-dev plugin を自律 spawn することを SHALL NOT で禁止
  - 背景: Wave 90/91/92 で RED-only merge × 3 PR が連続発生し、co-autopilot 経由の自律実装が test bypass 経路を見逃した
  - 当時の対処: `spawn-controller.sh` で feature-dev を allow-list 外として完全 block。`SKIP_LAYER2=1 SKIP_LAYER2_REASON='<reason>'` env override 時は intervention-log に bypass 記録した上で cld-spawn を呼ばずに手順を出力 (Layer 2 Escalate)
- **2026-05-11 user 訂正**:
  > 「user が observer に明示的に依頼した場合のみ observer は `feature-dev:feature-dev` window を spawn して Refined Issue を実装可能」

  現状 SU-10 は「完全 block」だが、user 意図は「明示依頼時 ALLOW」。乖離を解消しつつ、過去事故パターン (RED-only merge × 3) を再発させない多層 gate が必要。

### 構造的設計判断

1. **過剰防衛緩和**: 完全 block は user 操作性を損ない、SKIP_LAYER2 escape hatch への過依存を生む（intervention-log 上 5+ 件/Wave）。
2. **明示依頼の検証**: 「user が依頼した」ことを machine-readable な形で証拠化する必要がある。
3. **多層 gate**: 承認証跡（依頼確証）+ Status gate（refined gate）+ parallel gate（SU-4）の三層で過去事故と等価な安全性を担保する。

## Decision

feature-dev plugin spawn を **`mcp__twl__twl_spawn_feature_dev` MCP tool 経由でのみ許可（SHALL）**。tool は user 明示依頼の確証として承認証跡ファイル（TTL 内）の存在を確認し、Status=Refined と parallel-spawn の両 gate を満たすことを確認した上で cld-spawn を起動する。

### 三層 gate（A + B + C）

| Layer | 内容 | 実装 AC |
|---|---|---|
| **A**: 承認証跡ファイル + TTL | `.supervisor/feature-dev-request-<N>.json` (schema: `{issue, requested_at, requested_by, ttl_seconds, intervention_id, notes?}`、TTL=1800s) を observer が user 明示依頼時に書き出す。MCP tool は schema + TTL を検証し、検証成功後 atomic rename で `.supervisor/consumed/` に移動（one-shot 消費） | AC1, AC2, AC4 |
| **B**: Status=Refined 検証 | `spawn-controller.sh --check-refined-status <N>` 新サブコマンドへ shell-out（既存 `--pre-check-issue` ロジックの SSoT 再利用）。`gh project item-list` で Status を取得し Refined でなければ DENY | AC3 |
| **C**: parallel-spawn check | `spawn-controller.sh --check-parallel-only <N>` 新サブコマンドへ shell-out（既存 `_check_parallel_spawn_eligibility` 関数の早期 exit 版）。SU-4 の同時 supervised controller ≤ 10 を担保 | AC4 |

### Migration（deprecation）

- `spawn-controller.sh` の SKIP_LAYER2=1 直接 path は **deprecation period（2 wave 後廃止）** で運用継続
- deprecation warning を stderr に出力し、`mcp__twl__twl_spawn_feature_dev` への移行を推奨
- 完全削除は別 follow-up Issue で追跡

### 採択しなかった選択肢

| Option | 不採用理由 |
|---|---|
| 完全 ALLOW（gate なし） | 過去事故パターンの再発リスク (RED-only merge × 3)。SU-10 母艦としての防衛意義を喪失 |
| Approval/Spawn 分離 MCP tool (`twl_check_spawn_approval` + 別 spawn 経路) | Issue AC1「spawn を行う MCP tool」と乖離。observer が複数 tool を順次呼ぶ必要があり flow 複雑化 |
| Python で Status check 再実装 | SSoT 二重化。`spawn-controller.sh --pre-check-issue` の `gh project item-list + python3 -c` パターンと重複し保守コスト増大 |
| ApprovalRequest Python class の独立モジュール化 | 本 Issue 範囲では 1 handler のみが利用。YAGNI で `tools.py` 内 inline 関数として保持 |

### Rationale

- **machine enforcement**: 承認証跡ファイル + atomic rename で「one-shot 消費」を構造的に保証（reuse 不可、race condition は POSIX rename で原子性確保）
- **SSoT 維持**: Status check と parallel check は既存 bash 関数を再利用し Python での re-implementation を回避
- **observer 操作性**: user 明示依頼時の即時 spawn が可能、SKIP_LAYER2 escape hatch への過依存を解消
- **過去事故パターン回避**: Status=Refined gate により co-issue refine 未完了の Issue への spawn を防ぐ

## Consequences

### Positive

- **user 明示依頼時の即時 spawn**: Discord/AskUserQuestion 経由で依頼 → 承認証跡作成 → MCP tool 呼び出しで spawn 完了（manual cld セッション起動の手間を削減）
- **machine enforcement**: 承認証跡 + TTL + one-shot 消費で「明示依頼の証拠」を構造的に保証
- **SSoT 整合**: supervision.md SSoT に SU-10 が追加され、mirror-only の異常状態を解消（#1620 時の見落とし）
- **Layer 1 Confirm への昇格**: パターン 14 を Layer 1 へ降格させることで「user 承認証跡をもって supervisor が実行」を明示化

### Negative / Trade-offs

- **observer プロセス信頼性依存**: 承認証跡ファイルの作成は observer 側で行う。observer が自身で書いて自身で消費する spoof リスクは残る。本 Issue scope では 1-user 前提で許容
- **MCP failure 時の回復**: MCP server がダウンすると spawn 不可。SKIP_LAYER2 escape hatch を 2 wave 維持することで MCP 障害時の回復可能性を確保
- **migration cost**: 既存 SKIP_LAYER2 直接呼び出しコードベース（手動運用 + bats test）は deprecation period 中段階的に MCP tool 経路へ移行

### Migration Path

| Wave | Action |
|---|---|
| 現在 | ADR-040 採択 + MCP tool 公開 + deprecation warning 開始 |
| +1 wave | observer SKILL.md に承認証跡作成 skill を追加（follow-up Issue） |
| +2 wave | SKIP_LAYER2=1 直接 path を完全削除（follow-up Issue） |
| Phase 2 拡張 | #1625 (5-stage taxonomy) 完成後、Status gate を「Refined && timeline に Explored が存在」へ拡張（別 Issue） |

## Future Work

- **multi-user 認証**: 承認証跡の `requested_by` に `git config user.email` を embed し、複数 user 環境で誰の依頼かを記録する設計余地
- **Discord webhook 連携**: 承認証跡ファイル作成を Discord bot が webhook 受信時に自動実行する経路
- **audit log 集約**: `.supervisor/consumed/` 30 日超の自動 cleanup + audit summary 生成

## ADR-029 関係

`mcp__twl__twl_spawn_feature_dev` は既存 bash 経路からの移行ではなく net-new tool のため、[ADR-029](ADR-029-mcp-tool-migration.md) の shadow rollout pattern の適用外とする。ADR-029 は既存経路の移行 SSoT として定義されており、新規 tool は shadow log（`/tmp/mcp-shadow-spawn-feature-dev.log`）への記録で audit 性を担保する。

## References

- Issue #1635: feat(supervision): observer feature-dev spawn gate
- Issue #1620: SU-10 母艦（feature-dev fallback の Layer 2 Escalate 化）
- ADR-038: Lesson 28 — RED-only label-based bypass の構造的閉塞（過去事故）
- ADR-039: pre-pr-gate event-horizon の整理（同時期の Defense in Depth 強化）
- `plugins/twl/architecture/domain/contexts/supervision.md` SU-10 行
- `plugins/twl/refs/intervention-catalog.md` パターン 14（Layer 1 Confirm）
- `plugins/twl/skills/su-observer/refs/su-observer-controller-spawn-playbook.md` feature-dev 起動手順
- `cli/twl/src/twl/mcp_server/tools.py` `twl_spawn_feature_dev_handler` 実装
- `plugins/twl/skills/su-observer/scripts/spawn-controller.sh` `--check-parallel-only` / `--check-refined-status` subcommands
