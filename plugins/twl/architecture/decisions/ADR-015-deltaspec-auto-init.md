# ADR-015: DeltaSpec 自動初期化と direct モード分離

## Status

Accepted

## Date

2026-04-10

## Context

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

`deltaspec/` の存在有無は判定条件から**削除**。

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
