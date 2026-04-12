## 1. 影響範囲調査（AC-3）

- [ ] 1.1 `grep -r '.specialist-spawned-\|.specialist-manifest-' plugins/ cli/ scripts/` で全参照箇所を列挙し、Issue コメントに報告する

## 2. issue-spec-review.md の修正（AC-1 / AC-2）

- [ ] 2.1 `issue-spec-review.md:60-63` の CONTEXT_ID 生成を `mktemp /tmp/.specialist-manifest-XXXXXXXX.txt` + `chmod 600` に書き換える
- [ ] 2.2 `CONTEXT_ID` を `$(basename "$MANIFEST_FILE" .txt | sed 's/^\.specialist-manifest-//')` で導出するよう変更する
- [ ] 2.3 クリーンアップロジック（:131-140）を `$MANIFEST_FILE` + `CONTEXT_ID` ベースに更新し、glob フォールバックを整理する

## 3. 影響箇所の更新（AC-3 続き）

- [ ] 3.1 `check-specialist-completeness.sh` の glob パターン・CONTEXT 抽出ロジックが新命名規則で動作することを確認する（変更不要の場合は確認のみ）
- [ ] 3.2 `spec-review-gate.test.sh` の `ctx` 生成・参照箇所を新命名規則に合わせて更新する
- [ ] 3.3 `check-specialist-completeness.test.sh` の `ctx` 生成・参照箇所を新命名規則に合わせて更新する

## 4. テスト追加（AC-4）

- [ ] 4.1 `tests/scenarios/` に並列起動テスト（同一秒内に 3 回 spawn）を追加し、CONTEXT_ID 衝突がないことを検証するシナリオを書く
- [ ] 4.2 新規テストが既存テストスイートと整合していることを `twl test` で確認する
