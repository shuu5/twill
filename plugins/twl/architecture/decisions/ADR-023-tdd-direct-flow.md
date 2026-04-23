# ADR-023: deltaspec-free chain と TDD 直行 flow

**Status**: Accepted
**Date**: 2026-04-23
**Issue**: #903
**Epic**: #901 (twill Phase Z — DeltaSpec 完全除去 + quick ラベル廃止 + TDD 直行フロー再構成)
**Supersedes**: [ADR-015](ADR-015-deltaspec-auto-init.md) (DeltaSpec 自動初期化と direct モード分離)
**Related**: ADR-0007 (chain SSOT 2 レイヤー責務分離)、ADR-018 (state schema SSoT)、ADR-019 (spec implementation category — DeltaSpec と直交、KEEP)、ADR-020 (chain SSoT refinement)、ADR-022 (chain SSoT 境界明確化)

---

## Context

ADR-015 で DeltaSpec (`/deltaspec/` + chain step 5 つ: `change-propose` / `change-id-resolve` / `change-apply` / `post-change-apply` / `test-scaffold`) を「自動初期化 + propose デフォルト」に再設計して以降、本リポジトリでの実運用を観察した結果、以下の根本的な課題が確認された。

### C-1: DeltaSpec は事実上 deadweight

- ADR-015 適用以降に observer が確認した 47 件超の Issue 実行において、Worker が `propose` mode を自発選択した記録はゼロ件。全 Issue が `quick` / `scope/direct` ラベル経由で `direct` mode に落ちるか、あるいは `propose → apply` の chain で入っても Acceptance Criteria (AC) の充足判定に寄与した局面が観測されなかった。
- proposal → specs → tests のマッピング生成が Worker の context window を圧迫し、AC に集中させる本来目的を阻害する副作用が優越した。

### C-2: SSoT triangle の 3 面同期コスト

- DeltaSpec 5 step は chain.py `CHAIN_STEPS` / chain-steps.sh / deps.yaml.chains の **3 箇所** に分散管理されており、step 名の rename や順序変更のたびに 3 面同期の整合性検証 (`twl check --deps-integrity`) に追加負荷がかかる (ADR-022 D-1 の SSoT 境界下でも構造的に変えられない)。
- pre-commit hook の drift 検出、ADR-020/ADR-022 の refinement 対象拡大など、**SSoT triangle 保守コスト** が deltaspec の価値と見合わなくなった。

### C-3: quick / scope/direct ラベルは `direct` mode のスキップ制御に退化

- `QUICK_SKIP_STEPS` 9 step のうち **5 step が DeltaSpec step** (`change-propose` / `change-id-resolve` / `test-scaffold` / `change-apply` / `check`)、残りの 4 step (`crg-auto-build` / `arch-ref` / `ac-extract` / `prompt-compliance`) はそれぞれ独自の条件で既にスキップされており、quick 概念自体が `direct` ラベルの冗長表現になっている。
- `quick` + `scope/direct` 2 つのラベル体系は Worker / Pilot / Observer の 3 者に対して同時に混乱源となっている。

### C-4: TDD 直行 flow への代替可能性の確認

- AC (Acceptance Criteria) ベースで `pytest --collect-only` の RED 検証 + 実装 + GREEN 検証の直行パスは、DeltaSpec proposal → apply 経由と等価の品質担保を提供可能。
- `worker-codex-reviewer` に AC coverage 検証を追加することで、Worker 実装が AC を網羅しているかを LLM 判定で担保できる見通し。

## Decision

### D-1: DeltaSpec 機能を CLI + plugin から完全除去

- **削除対象**: `cli/twl/src/twl/spec/` 全 7 ファイル、`plugins/twl/scripts/deltaspec-helpers.sh`、`chain-runner.sh` の spec handler、`/deltaspec/` (2.8MB) + `/plugins/twl/deltaspec/` (1.8MB) ディレクトリ。
- **chain step 削減**: chain.py `CHAIN_STEPS` を **19 step → 14 step** に短縮 (DeltaSpec 5 step `change-propose` / `change-id-resolve` / `change-apply` / `post-change-apply` / `test-scaffold` を除去)。
- **auto-merge 挙動の変更**: `auto-merge.sh` 内の DeltaSpec archive block を削除。merge は squash merge + cleanup のみ実行する。
- **state 互換性**: `state.py` から `deltaspec_mode` / `change_id` / `is_quick` フィールドを削除。`_read_state_field` の unknown field silent drop により既存 `issue-*.json` の後方互換を確保。

### D-2: test-scaffold を AC-based `ac-scaffold-tests` に reshape

- 既存の `commands/test-scaffold.md` + `agents/spec-scaffold-tests.md` を **`agents/ac-scaffold-tests.md`** に reshape する。
- 入力: Issue body の Acceptance Criteria 節（`## AC` / `## Acceptance Criteria`）。
- 出力: AC 1 件につき 1 RED test を生成し、Worker が TDD 直行 flow の起点として消費する。
- `worker-spec-reviewer` は削除（phase-review / `pr-review-manifest.sh` で既に非 spawn 確認済のため、影響ゼロ）。

### D-3: Worker の TDD mental model 誘導

- `workflow-test-ready` SKILL.md 内に **RED → GREEN → REFACTOR** を明示する新セクションを追加。
- test-first guard: `pytest --collect-only` が fail を返すことを Worker 実装前の確認ステップとして組み込む。
- `worker-codex-reviewer` に **AC coverage 検証** セクションを追加 (Issue body の AC 箇条書きに対して、実装差分とテスト差分で網羅されているかを LLM 判定)。

### D-4: quick / scope/direct ラベル廃止

- GitHub `twill-ecosystem` Project Board から label `quick` および `scope/direct` を削除する (Wave E #Z15-#Z18)。
- `QUICK_SKIP_STEPS` / `DIRECT_SKIP_STEPS` / `quick`-label 判定コード / `scope/direct`-label 判定コードを chain.py・chain-steps.sh・co-issue・co-autopilot 関連 SKILL から除去。
- 以降、Issue は単一 flow（DCI → `ac-scaffold-tests` → Worker 実装 → review → merge-gate）に統一される。

### D-5: Wave 構成 (厳密逐次)

本 ADR は Epic #901 の Wave A 2/3 として起草される。Wave 構成は以下:

| Wave | 範囲 | 対象 |
|------|------|------|
| Wave A (先行) | #Z1-#Z3 (本 ADR-023 作成含む) | Architecture 先行（ADR + refs） |
| Wave B | #Z-CORE | CLI + Plugin atomic 統合削除（pre-commit hook pass 保証） |
| Wave D | #Z10-#Z14 | SKILL + workflow + refs cascade |
| Wave E | #Z15-#Z18 | quick + scope/direct ラベル廃止 |
| Wave F | #Z19-#Z20 | 物理削除 + state migration |
| Wave G | #Z21-#Z23 | Documentation + sandbox e2e + final integrity |

big-bang 戦略（feature flag なし）を採用する。feature flag 維持コストが SSoT triangle に対して高く、state.py `_read_state_field` の unknown field silent drop で既存状態ファイル互換性を確保できる。

## Consequences

### 利点

- **co-autopilot シンプル化**: chain step 数が 19→14 に減り、SSoT triangle 同期対象も削減される。`twl check --deps-integrity` の保守工数が恒常的に減少。
- **Worker の認知負荷軽減**: Worker は proposal/specs/tests のマッピングを学習する必要がなくなり、AC → 実装 → テスト というシンプルな TDD mental model に集中できる。
- **ラベル体系の整理**: `quick` / `scope/direct` / `refactor` / `enhancement` 等が混在していた Issue ラベル分類から、skip 制御専用の 2 ラベルが除去され、意味に基づく分類のみが残る。
- **将来の拡張余地**: AC-based test 生成は Acceptance Test-Driven Development (ATDD) の基盤として機能し、将来 Behavior-Driven Development (BDD) への発展を妨げない。

### 懸念 / 代償

- **Worker TDD mental model 要誘導**: RED → GREEN → REFACTOR が Worker に自明でない場合、test-first 原則が後退するリスクがある。→ 緩和策: D-3 の `workflow-test-ready` SKILL.md 明示、`worker-codex-reviewer` AC coverage 検証、`pytest --collect-only` test-first guard の 3 層防御。
- **既存 DeltaSpec ベースの Issue への対応**: DeltaSpec ベースで作成された過去 PR / archive は `/deltaspec/` 物理削除後も git history から参照可能。migration ガイドは Wave G #Z22 で documentation 化する。
- **ADR-019 (Spec Implementation category) との関係**: ADR-019 で co-architect を Spec Implementation controller に分類したが、これは architecture/ 配下 docs 変更を指しており、DeltaSpec の spec 管理とは直交する。本 ADR は ADR-019 を supersede せず KEEP する (ADR-015 Related 欄と整合)。

### ロールバック手順

万一 TDD 直行 flow が運用に耐えない場合、以下の手順で revert する。ただし **本 ADR の revert は禁止** とし、再評価は新規 ADR で行う (ADR-015 再導入禁止方針を継承):

1. 新規 ADR を起票し、DeltaSpec 再導入の新設計を Proposed 状態で提示する
2. 本 ADR を Partially Superseded マークし、D-N の範囲で revert 対象を限定する
3. `git history` から Wave B-F の削除 commit を `git revert` ではなく **再実装** として扱う (削除前の chain.py / chain-steps.sh / deps.yaml を参考コードとして扱う)

## Non-goal

- **既存 test-scaffold 互換性の保持**: `spec-scaffold-tests` → `ac-scaffold-tests` は構造的に別 agent として再設計する。旧 agent の振る舞いを 1:1 で再現することは狙わない。
- **DeltaSpec archive の自動 migration**: `/deltaspec/archive/` 配下の過去 proposal を AC 形式に自動変換することは行わない。必要な場合は手動 migration を Wave G で documentation 化する。
- **autopilot 以外の controller への影響**: 本 ADR は co-autopilot / co-issue / co-architect の範囲に限定される。co-explore / co-project / co-utility / co-self-improve / su-observer は影響を受けない。
- **spec-review-* スクリプト群の削除**: `spec-review-session-init.sh` / `manifest.sh` / `orchestrator.sh` / `issue-spec-review.md` / `pre-tool-use-spec-review-gate.sh` は Issue 品質レビューゲート用で DeltaSpec 無関係のため KEEP (Epic #901 KEEP List 参照)。
