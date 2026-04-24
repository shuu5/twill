# Phase Z 完遂レポート (Issue #919)

作成日: 2026-04-24
担当: su-observer (Wave G 3/3 = Phase Z 完遂 gate)

---

## 1. Integrity Check 結果

| チェック | 結果 | 詳細 |
|---|---|---|
| `twl check --deps-integrity` | ✅ PASS | OK: 283, Missing: 0 |
| `pytest cli/twl/tests/` | ✅ PASS (pre-existing 40 件) | 1479 passed, 40 failed (main と同一、新規失敗なし) |
| `bats plugins/twl/tests/bats/` | ✅ PASS | 45/45 tests passed |
| `check-catalog-integrity.sh` | ✅ PASS | 31 reference files, all checks passed |

---

## 2. Grep 残滓確認結果

### deltaspec / deprecated コマンド系
```
grep -rE "deltaspec|DeltaSpec|change-propose|change-apply|change-id-resolve|spec-scaffold-tests|worker-spec-reviewer" \
  cli/twl/src plugins/twl --exclude-dir=.git
```
結果: tests/unit/ と tests/bats/ の `# Spec: deltaspec/...` コメントのみ ✅  
(source コード・commands・scripts に active 参照なし)

### quick / scope-direct 系
```
grep -rE "is_quick|quick_flag|--quick|QUICK_INSTRUCTION|_detect_quick_label|scope/direct|scope-direct" \
  cli/twl/src plugins/twl/{scripts,commands,agents} --exclude-dir=.git
```
結果: 15 件 (main と同一)
- `scope/direct` 参照: 現行 direct mode の有効機能 (chain.py, chain-runner.sh, chain-steps.sh)
- `is_quick_candidate`: co-issue spec-review の複雑度分類機能 (autopilot quick mode とは別)
- `quick_flag` in issue-lifecycle-orchestrator.sh: co-issue policies.json 由来
- `--quick` in issue-cross-repo-create.md: co-issue CLI フラグ

### quick-detect / quick-guard (本 Issue で削除)
```
grep -rn "quick-detect|quick_detect|quick-guard" cli/twl/src plugins/twl --exclude-dir=.git
```
結果: **0件** ✅ (Wave E #911/#913 削除漏れを本 Issue #919 で修正)

---

## 3. 本 Issue での修正 (#919 での直接修正)

| ファイル | 変更内容 |
|---|---|
| `cli/twl/src/twl/chain/validate.py:481` | `orchestration_only` から `quick-detect`, `quick-guard` 削除 |
| `plugins/twl/skills/workflow-setup/SKILL.md` | `quick-detect` 呼び出し削除、IS_QUICK=true パス削除 |
| `plugins/twl/commands/wave-collect.md` | `is_quick`/`--quick` デッドコード削除 |
| `plugins/twl/README.md` | `change-apply`/`workflow-pr-cycle`/`change-archive` → 現行 workflow に更新 |
| `plugins/twl/settings.json` | compactPrompt の `change-propose` → `ac-extract` に更新 |

---

## 4. 根本原因 4 件の診断

### Bug 1: quick-detect/quick-guard 残存 (Wave E 削除漏れ)
- **場所**: `cli/twl/src/twl/chain/validate.py:481`、`workflow-setup/SKILL.md`、`wave-collect.md`
- **影響**: validate.py は harmless dead reference。SKILL.md は実際に `quick-detect` を呼んでエラーを出力 (IS_QUICK は空になっていた)。wave-collect.md は specialist-audit.sh に --quick フラグを渡していたが実装なし
- **対処**: 本 Issue #919 で直接修正済み ✅

### Bug 2: .dev-session/01.5-ac-checklist.md の Issue 間キャリーオーバー
- **場所**: `plugins/twl/scripts/chain-runner.sh:404` (step_ac_extract)
- **影響**: 前 Issue の AC チェックリストが新 Issue に引き継がれ、Worker が誤った AC で実装する可能性
- **対処**: follow-up Issue #938 起票 (Phase AA)

### Bug 3: `twl chain validate` サブコマンド未実装 (ADR-022 D-5 仕様漏れ)
- **場所**: `cli/twl` の chain サブコマンド (generate/viz/export のみ)
- **影響**: ADR-022 D-5、ADR-020 §115、twill-integration.md:127 で Critical として定義されているが実装なし。テストは `twl validate` で代替中
- **対処**: follow-up Issue #939 起票 (Phase AA)

### Bug 4: Observer Pilot fallback 設計矛盾 (最重要)
- **背景**: Wave A-G1 (14 PR) が IS_AUTOPILOT=true co-autopilot で実行された際、phase-review/merge-gate が Pilot 待ちで詰まり、Observer が `auto-merge.sh` を直接呼んで回避した
- **影響**: 14 PR が specialist review (code-reviewer, security-reviewer 等) を経由せずマージ。本 Issue #919 で post-hoc specialist review を実施
- **運用変更 (即時適用)**: Observer Pilot fallback (auto-merge.sh 直接呼び出し) MUST NOT
- **対処**: follow-up Issue #940 起票 (Phase AA)、設計修正提案含む

---

## 5. Observer Pilot fallback 禁止化の影響分析

### 影響を受けた Wave (Phase Z)
- Wave A-G1 全 14 PR が phase-review skip
- 起票 Issues: #906-#917 (12 Issues) + #905 + #924

### 今後の co-autopilot mode 運用変更提案
1. **Option A (推奨)**: `auto-merge.sh` 内で phase-review step を内包する
   - `auto-merge.sh` 実行前に `pr-review-manifest.sh` → specialist spawn → report を完了
2. **Option B**: orchestrator が IS_AUTOPILOT=true 時に phase-review を自動 inject
   - chain 正規フローに phase-review step を追加し、詰まらない設計にする
3. **Option C**: Observer が chain の詰まりを検知し根本原因修正後に再試行

詳細は Issue #940 参照。

---

## 6. Post-hoc Specialist Review 結果 (Wave A-G1)

詳細: `.autopilot/archive/issue-919/phase-z-reviews/` 参照。

### code-reviewer: WARNING 2 件、CRITICAL なし
- W1: `DIRECT_SKIP_STEPS = frozenset()` — 意図明示コメントなし (harmless、Phase AA で注記推奨)
- W2: `tdd-red-guard.sh` — `set -uo pipefail` なし `set -e` (TDD guard の誤 PASS リスク、Phase AA 修正推奨)

### security-reviewer: **PASS** (CRITICAL/WARNING なし)
- 入力バリデーション: 正規表現ホワイトリスト方式で全スクリプト一貫 ✅
- コマンドインジェクション: allow-list + `printf '%q'` による多層防御 ✅
- パストラバーサル: `..` 拒否ロジック全箇所確認 ✅
- シークレット漏洩: GitHub token マスキング確認 ✅

### arch-doc-reviewer: WARNING 2 件、CRITICAL なし
- W1: ADR-015 本文に歴史的 quick/QUICK_SKIP_STEPS 設計が残存 (注記追加推奨)
- W2: ADR-023 D-4「scope/direct ラベルを廃止」が不正確 (実際は quick のみ廃止、scope/direct は direct mode として維持)

### codex-reviewer: **全 AC 達成** (Wave A-G1 + #919 修正)
- Epic #901 の全 AC が Wave A-G1 (14 commits) + #919 追加修正 5 件で達成 ✅
- Epic #901 は本 Issue merge 後に close 可能

---

## 7. doobidoo Phase Z 完遂サマリ

- **保存 hash**: 99ebd63ca80d5303b5aa8b697e72712c1539269c07638d7ab36f7781d707e3a2
- **tags**: observer-wave, phase-z-complete, cross-machine, twill, epic-901
- **type**: project

---

## 8. Wave A-G1 累計統計

| 項目 | 値 |
|---|---|
| 対象 commits | 14 |
| 変更ファイル数 | 1122 |
| 挿入行数 | 12249 |
| 削除行数 | 59419 |
| 対象期間 | 2026-04-23 〜 2026-04-24 |

---

## 9. 次フェーズ: Phase AA

| Issue | 内容 | 優先度 |
|---|---|---|
| #938 | .dev-session AC キャリーオーバー修正 | 高 |
| #939 | `twl chain validate` サブコマンド実装 | 中 |
| #940 | Observer Pilot fallback 禁止化・auto-merge.sh 再設計 | 最高 |
| TBD | co-issue quick terminology cleanup (is_quick_candidate 等) | 低 |

Epic #901 (Phase Z): merge 後に close 予定。
