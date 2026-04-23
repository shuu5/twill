# ADR-015: DeltaSpec 自動初期化と direct モード分離

**Status**: Superseded
**Date**: 2026-04-10
**Issue**: #784
**Superseded-By**: [ADR-023-tdd-direct-flow](ADR-023-tdd-direct-flow.md)
**Related**: ADR-019 (spec implementation category — DeltaSpec と直交、KEEP)、ADR-022 (chain SSoT 境界)

---

> ⚠️ **Superseded by ADR-023** — 2026-04-23 (Epic #901 Phase Z Wave A / Issue #902)
>
> 本 ADR の方針 (`deltaspec/` 自動初期化 + `propose` デフォルト化) は、Phase Z で **DeltaSpec 機能を CLI + plugin から完全除去する決定** ([ADR-023-tdd-direct-flow](ADR-023-tdd-direct-flow.md)) により無効化された。co-autopilot は `Issue → TDD → PR` の直行フローに再構成される。
>
> **決定理由（要旨）**: 本 ADR 適用後の実運用で Worker が `propose` mode を自発使用した記録はゼロ件。`direct` ラベル opt-out 前提の設計が維持コストに見合わないと判断された。
>
> **Dangling link 許容（Phase Z Wave A 厳密逐次）**: 本 ADR が参照する `ADR-023-tdd-direct-flow.md` は、Wave A 後続 Issue #903 で作成される（Wave A は #902 → #903 → #904 の厳密逐次であり、#902 で supersede-by link を先行記載する設計）。#903 merge 完了をもって本 link が解決する。
>
> **DeltaSpec chain step の除去タイミング**: `change-propose` / `change-apply` / `change-id-resolve` / `post-change-apply` / `test-scaffold` の 5 step は ADR-023 で削除が定義され、Epic #901 Wave B (#Z-CORE) 以降で `chain.py` / `chain-steps.sh` / `deps.yaml.chains` から除去される。本 PR 時点ではこれらの step は実装上残存する。

## DeltaSpec 再導入の禁止

Phase Z 完了後、本リポジトリにおける DeltaSpec 機能の再導入は以下の理由で **禁止する**:

1. **実運用で未使用** — 本 ADR 適用後も Worker が自発的に `propose` mode を活用した記録はゼロ件。`direct` ラベル opt-out 前提の設計であり、デフォルト `propose` は Worker の認知負荷を一方的に増加させただけで、品質担保への寄与が観測されなかった。
2. **SSoT 同期コストが恒常負担** — DeltaSpec 5 step (`change-propose` / `change-id-resolve` / `change-apply` / `post-change-apply` / `test-scaffold`) が、ADR-022 で定義された chain SSoT 境界（chain.py `CHAIN_STEPS` を runner step SSoT、chain-steps.sh は chain.py からの一方向 export、deps.yaml.chains は workflow orchestrate 含む独立 SSoT）の整理対象を恒常的に拡大させていた。
3. **TDD 直行フローへの代替** — Acceptance Criteria-based の `ac-scaffold-tests` + `worker-codex-reviewer` の AC coverage 検証 + RED/GREEN/REFACTOR 誘導により、DeltaSpec が担おうとしていた「仕様駆動による品質担保」はより低コストで実現される (ADR-023 D-2/D-3)。
4. **再導入時は新 ADR を起票** — 将来 spec-driven 開発が本リポジトリで必要となった場合は、本 ADR の revert ではなく、新規 ADR として設計の是非を再評価すること。

---

## Review

- 2026-04-21: Issue #784 の phase-review プロセス（worker-arch-doc-reviewer / worker-code-reviewer / worker-issue-pr-alignment / worker-security-reviewer）で Accept 判断基準4軸を検証し、全て PASS を確認した。これが co-architect レビュー合意 (plan Q2=B 準拠) に相当する。
- 2026-04-23: Epic #901 Phase Z Wave A にて本 ADR を Superseded にマーク。後続 ADR-023 が deltaspec-free TDD 直行フローを定義する。

## Context（Superseded 時点での記録）

47件の Issue 実行で DeltaSpec が**一度も使われなかった**。全て `direct` モード（コード一発生成）。

根本原因は `chain.py` の `step_init()`:
```python
deltaspec_dir = root / "deltaspec"
if not deltaspec_dir.is_dir():
    return {"recommended_action": "direct", ...}
```

Worker の worktree には `deltaspec/` ディレクトリが存在しないため、全 Worker が `recommended_action=direct` を受け取る。これは「deltaspec/ がなければ使わない」という現状追認のロジックであり、初めてのプロジェクトでは永遠に DeltaSpec が使われない構造的欠陥。

また、`QUICK_SKIP_STEPS` に `change-propose` が含まれており、`direct` 判定を受けた Worker は DeltaSpec を作る機会すら得られない。`direct` と `quick` のスキップ条件が混在している。

## Accept 判断基準

| 基準 | 評価 | 根拠 |
|------|------|------|
| 互換性 | ✓ PASS | `quick` / `scope/direct` ラベルの挙動は不変。`deltaspec/` 不在の場合のみ `direct` → `propose` に変化 |
| 実装コスト | ✓ PASS | 0（既に `chain.py:step_init()` と `change-propose.md:Step 0` に実装済み） |
| 運用影響 | ✓ PASS | DeltaSpec 強制 init は `quick` / `scope/direct` ラベルで opt-out 可能 |
| テスト容易性 | ✓ PASS | pytest `TestStepInit` に unit テスト追加済み、bats で `change-propose Step 0` をカバー |

## Decision

### 1. step_init() の再設計

`deltaspec/` 不在時の判定を `direct` から `propose + auto_init=True` に変更する。存在チェック自体は維持し、返却値のみを変更する（機能的同値: 不在 → propose という結果は同じ）:

```python
def step_init(self, issue_num: str = "") -> dict[str, Any]:
    branch = self._git_current_branch()
    is_quick = "true" if "quick" in labels else "false"
    is_direct = "true" if "scope/direct" in labels else "false"

    if branch in ("main", "master"):
        return {"recommended_action": "worktree", ...}

    # quick ラベル or scope/direct ラベル → direct
    if is_quick == "true" or is_direct == "true":
        return {"recommended_action": "direct", ...}

    root = self._project_root()
    deltaspec_dir = root / "deltaspec"

    # ADR-015: deltaspec/ 不在 → propose（change-propose で自動初期化）
    if not deltaspec_dir.is_dir():
        return {"recommended_action": "propose", "auto_init": True, "deltaspec": False, ...}

    # 既存ロジック: changes/ の状態チェック
    ...
```

**実装済み**: `cli/twl/src/twl/autopilot/chain.py:step_init()` L277-288。チェック削除ではなく返却値変更という形で実現しているが、仕様の意図（deltaspec/ 不在 → propose）は達成されている。

### 2. deltaspec/ 自動初期化（最小スコープ）

`change-propose` ステップで、`auto_init=true` の場合:
1. `mkdir -p deltaspec/changes/<change-id>/`
2. Issue body から `proposal.md` を生成
3. `.deltaspec.yaml` を作成（status: pending）

specs/ やテストマッピングは後続ステップ（test-scaffold）が生成する。

### 3. direct モードと quick モードの分離

```python
# quick: 軽微な変更（ラベルベース）
QUICK_SKIP_STEPS: frozenset[str] = frozenset([
    "crg-auto-build", "arch-ref", "change-propose",
    "ac-extract", "change-id-resolve", "test-scaffold",
    "check", "change-apply", "prompt-compliance",
])

# direct: DeltaSpec をスキップ（quick またはラベルベース）
DIRECT_SKIP_STEPS: frozenset[str] = frozenset([
    "change-propose", "change-id-resolve", "change-apply",
])
```

`next_step()` を拡張して `mode`（direct/propose/apply）を参照:
```python
def next_step(self, issue_num: str, current_step: str) -> str:
    is_quick = self._read_state_field(issue_num, "is_quick") == "true"
    mode = self._read_state_field(issue_num, "mode")
    
    for step in CHAIN_STEPS:
        if found:
            if is_quick and step in QUICK_SKIP_STEPS:
                continue
            if mode == "direct" and step in DIRECT_SKIP_STEPS:
                continue
            return step
```

### 4. scope/direct ラベルの管理

- **co-issue が推奨付与**: Issue 作成時に規模を推定し、`scope/direct` ラベルを提案
- **ユーザーが確認**: 承認または却下
- **Worker は参照のみ**: `step_init()` がラベルを読み取って判定

### 5. DeltaSpec 適用ポリシー（更新）

| 条件 | 動作 | 根拠 |
|------|------|------|
| `quick` ラベル | direct | コスト対効果 |
| `scope/direct` ラベル | direct | 明示的 opt-out |
| 上記以外 | propose → apply | 仕様駆動（デフォルト） |

`deltaspec/` の存在有無チェックは**維持**するが、不在時の返却値を `direct` から `propose + auto_init=True` に変更する（機能的同値: 不在 → propose）。

## Consequences

### Positive
- DeltaSpec が初めてのプロジェクトでも使用される
- quick と direct の概念が明確に分離
- `scope/direct` ラベルにより trivial 変更で DeltaSpec が強制されない
- テスト生成（test-scaffold）が DeltaSpec の specs/ を参照して動作する前提が成立

### Negative
- `change-propose` ステップの実行時間が増加（deltaspec/ 初期化 + proposal.md 生成）
- `scope/direct` ラベルの付け忘れで DeltaSpec パスに入る可能性（意図的な設計: デフォルトは仕様駆動）
- `_detect_direct_label()` の追加実装が必要

### Risks
- deltaspec/ 自動初期化で生成される proposal.md の品質
  → 緩和策: change-propose コマンドの品質ガイドラインを明文化
- DIRECT_SKIP_STEPS と QUICK_SKIP_STEPS の2つのスキップセットの管理コスト
  → 緩和策: chain-steps.sh と chain.py で SSOT を維持し、twl chain generate --check でドリフト検出

## Alternatives

### 案1: deltaspec/ 不在時は direct を維持（現状維持）

`step_init()` の既存ロジックを変更せず、DeltaSpec は明示的な `twl spec init` 後にのみ使用する。

- 却下理由: 初めてのプロジェクトで DeltaSpec が永遠に使われない構造的欠陥が継続する（本 ADR の Context に記述した根本原因を解決しない）。

### 案2: 環境変数によるオプトイン

`TWL_ENABLE_DELTASPEC=1` が設定された場合のみ `propose` を返す。

- 却下理由: デフォルトが無効のままでは同じ問題が継続する。`scope/direct` ラベルによる opt-out がより明示的かつ Issue 単位で制御可能。
