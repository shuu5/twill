# AC Coverage Review: Epic #901 vs Wave A-G1

実施日: 2026-04-24
対象: Epic #901 の AC vs 62e67a3..b7ad439

## AC一覧と達成状況

| AC | 達成 | 根拠 |
|---|---|---|
| DeltaSpec CLI 完全削除 | ✅ | 26dc68f: feat(#Z-CORE) remove DeltaSpec CLI |
| plugin core から deltaspec 依存削除 | ✅ | 26dc68f, d0d4905 |
| /deltaspec/ ディレクトリ物理削除 | ✅ | ac0adbc: chore physical removal |
| refs/architecture から deltaspec 参照削除 | ✅ | 1d8fdc5, 28f2b89 |
| quick ラベル廃止 (GitHub labels) | ✅ | b7ad439: delete quick/scope-direct labels |
| chain.py から QUICK_SKIP_STEPS 削除 | ✅ | 40e99aa: refactor #Z15 |
| state.py から is_quick/is_direct 削除 | ✅ | 40e99aa: refactor #Z15 |
| bash scripts から quick 検出ロジック削除 | ✅ | 6aee0ea: refactor #913 |
| orchestrator.py から quick 削除 | ✅ | 090b35e: refactor #Z16 |
| deps.yaml から quick/scope-direct 削除 | ✅ | d3b1b72: refactor #914 |
| workflow-test-ready TDD 直行 reshape | ✅ | 7aad30f: refactor #907 |
| workflow-setup から change-propose 削除 | ✅ | eebd2a1: refactor #906 |
| backward-compat migration tests | ✅ | 6600087: test #916 |
| docs/GitHub labels cleanup | ✅ | b7ad439: docs #917 |

## #919 で追加修正 (Wave A-G1 削除漏れ)

| 修正 | 場所 | 状態 |
|---|---|---|
| validate.py の quick-detect/quick-guard | orchestration_only set | ✅ 修正済み |
| workflow-setup SKILL.md の quick-detect 呼び出し | IS_QUICK=true パス | ✅ 修正済み |
| wave-collect.md の is_quick デッドコード | specialist-audit --quick | ✅ 修正済み |
| README.md の deprecated workflow | change-apply 等 | ✅ 修正済み |
| settings.json の change-propose 例 | compactPrompt | ✅ 修正済み |

## 未達成 AC

なし (本 Issue #919 での追加修正を含め全 AC 達成)

## 総評

Epic #901 の全 AC が Wave A-G1 + #919 修正で達成されている。
Epic #901 は本 Issue merge 後に close 可能。
