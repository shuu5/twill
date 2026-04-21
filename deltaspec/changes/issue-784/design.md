## Context

ADR-015 は「DeltaSpec が使われない」という構造的問題に対応するため 2026-04-10 に作成されたが、Proposed 状態で停滞している。一方、ADR の Decision で示された核心的変更（`deltaspec/` 不在時に `recommended_action=propose + auto_init=True` を返す）は既に以下に実装済みである:

- `cli/twl/src/twl/autopilot/chain.py:step_init()` — `deltaspec_dir.is_dir()` が `False` のとき `auto_init=True` を返す（L277-288）
- `plugins/twl/commands/change-propose.md:Step 0` — `MODE=propose` かつ `DELTASPEC_EXISTS=false` のとき auto_init パスに分岐し `twl spec new` を実行する

既存の pytest テスト `test_no_deltaspec_non_quick_non_direct_returns_propose_auto_init`（`test_autopilot_chain.py:TestStepInit`）が `step_init()` の auto_init ケースを検証済み。

## Goals / Non-Goals

**Goals:**
- ADR-015 の Accept 判断基準（互換性・実装コスト・運用影響・テスト容易性）を ADR 本文に明文化する
- ADR-015 Status を `Proposed` → `Accepted` に更新する
- `step_init()` auto_init パスのテストカバレッジを補完する（issue_num あり のケース追加）
- `change-propose.md:Step 0` の auto_init フローを bats でテスト追加する
- `step_init()` auto_init ブロックに docstring を補強し、ADR-015 との紐付けを明示する

**Non-Goals:**
- `step_init()` のロジック変更（既実装の挙動を維持する）
- `DIRECT_SKIP_STEPS` や `QUICK_SKIP_STEPS` の再構成（ADR-015 の Decision 3 は実装済みのため）
- `change-propose.md` の処理フロー変更

## Decisions

### 1. Accept 判断基準

| 基準 | 評価 | 根拠 |
|------|------|------|
| 互換性 | ✓ PASS | `quick` / `scope/direct` ラベルの挙動は不変。`deltaspec/` 不在の場合のみ `direct` → `propose` に変化 |
| 実装コスト | ✓ PASS | 0（既に chain.py と change-propose.md に実装済み） |
| 運用影響 | ✓ PASS | DeltaSpec 強制 init は `quick` / `scope/direct` ラベルで opt-out 可能 |
| テスト容易性 | ✓ PASS | pytest Unit テスト追加済み（TestStepInit）、bats テストを本 PR で追加 |

ADR-015 の実装は上記4基準を全て満たしている。Accepted とする。

### 2. 実装とADR仕様の乖離（許容）

ADR の Decision 1 は「`deltaspec/` の存在チェックを削除」と記述しているが、現実装は チェックを維持したまま返却値を変更（`direct` → `propose + auto_init`）している。これは機能的同値（`deltaspec/` 不在 → `propose` という結果は同じ）であり、むしろ段階的な状態遷移を明確にする構造として受け入れる。ADR のテキストをこの実装に合わせて更新する。

### 3. テスト追加スコープ

- **pytest 追加**: `step_init()` で `issue_num` が与えられた場合の auto_init ケース（state への `mode=propose` 書き込みを検証）
- **bats 追加**: `change-propose` Step 0 の auto_init フロー（MODE=propose + DELTASPEC_EXISTS=false → `twl spec new` 実行 + Step 3 へスキップ）

## Risks / Trade-offs

- **ADR テキストと実装の微差**: Decision 1 の「チェック削除」と実際の「チェック維持・返却値変更」の乖離は ADR テキスト更新で対処。実装は変更しない。
- **bats テスト範囲**: `change-propose.md:Step 0` は LLM 実行フローのため E2E よりも `chain-runner.sh` の呼び出しレベルで検証する。完全な統合テストは別 Issue（#786 等）に委ねる。
