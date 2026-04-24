# Architecture Doc Review: Phase Z Wave A-G1

実施日: 2026-04-24
対象: plugins/twl/architecture/ + refs/ (62e67a3..b7ad439 変更後の現状)

## CRITICAL (ADR/spec の矛盾)

なし。

## WARNING (一貫性の懸念)

### W1: ADR-015 本文に歴史的 quick/QUICK_SKIP_STEPS/DIRECT_SKIP_STEPS 設計が残存

- **場所**: `plugins/twl/architecture/decisions/ADR-015*.md` (Decision 本文 L67-131)
- **詳細**: Phase Z で quick モードと QUICK_SKIP_STEPS が廃止されたが、ADR-015 の Decision 本文はその設計を詳細に記述したまま。読者が現状と混同するリスク。
- **推奨**: ADR-015 に "廃止: Wave A-G1 (#901) にて quick/QUICK_SKIP_STEPS を削除" 注記を追加
- **Priority**: LOW (ADR は変更履歴のため削除は不要、注記推奨)

### W2: ADR-023 D-4 「scope/direct ラベルを廃止」と chain.py の矛盾

- **場所**: ADR-023 D-4 と `cli/twl/src/twl/autopilot/chain.py` (step_init L328, L341, L347)
- **詳細**: ADR-023 D-4 が「`quick` / `scope/direct` ラベルを廃止」と記述しているが、chain.py の `step_init()` は `scope/direct` ラベルを参照し続けている (direct モードとして有効利用)。
- **実態**: `scope/direct` は quick の後継として維持されており、廃止されたのは `scope-direct` (ハイフン) のみ。ADR-023 の記述が不正確。
- **推奨**: ADR-023 D-4 を「`quick` ラベルを廃止 (`scope/direct` は direct mode として維持)」に修正
- **Priority**: MEDIUM → Phase AA

## PASS (問題なし)

### 1. ADR-023 (TDD 直行フロー) と workflow-test-ready の整合性
workflow-test-ready SKILL.md (Wave F #907 で reshape) が ADR-023 の TDD 直行フロー仕様と一致。AC-based test-scaffold + RED guard が実装済み ✅

### 2. ref-invariants.md
不変条件 A/B/C は Phase Z 変更後も正確。DeltaSpec 関連の記述が適切に削除または注記済み ✅

### 3. ADR-022 Chain SSOT 境界
chain.py CHAIN_STEPS と chain-steps.sh の整合性は `twl check --deps-integrity` で自動検証済み (OK: 283) ✅

## 総評

ADR-015 と ADR-023 に minor な不整合あり。機能的には問題ないが、ドキュメントの正確性向上のため Phase AA で修正推奨。
全体的に architecture docs の整合性は維持されている。
