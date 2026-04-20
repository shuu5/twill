## 1. deps.yaml SSOT 修正

- [x] 1.1 `plugins/twl/deps.yaml` の `scripts:` セクションに `specialist-audit` エントリを追加する（`type: script`, `path: scripts/specialist-audit.sh`, `description: "specialist completeness 監査（su-observer/merge-gate）: JSONL の specialist 実行数と expected 数を照合し JSON 形式で結果を出力"`）
- [x] 1.2 `plugins/twl/deps.yaml` の `merge-gate-check-spawn` エントリに `calls:` セクションを追加する（`- script: specialist-audit`）

## 2. BATS テスト: specialist-audit.bats

- [x] 2.1 `plugins/twl/tests/bats/scripts/specialist-audit.bats` を新規作成する
- [x] 2.2 ケース1（PASS）: expected ⊆ actual で exit 0 + JSON `.status == "PASS"` を検証
- [x] 2.3 ケース2（warn-only FAIL）: missing 非空 + `--warn-only` で exit 0 + JSON `.status == "FAIL"` を検証
- [x] 2.4 ケース3（strict FAIL）: missing 非空 + default で exit 1 を検証
- [x] 2.5 ケース4（quick）: missing 非空 + `--quick` で exit 0 を検証
- [x] 2.6 ケース5（JSON 構造契約）: default 出力が jq parse 可能かつ `.status/.missing/.actual/.expected` を持つことを検証

## 3. BATS テスト: su-observer-specialist-audit-grep.bats

- [x] 3.1 `plugins/twl/tests/bats/scripts/su-observer-specialist-audit-grep.bats` を新規作成する
- [x] 3.2 SKILL.md から Wave 完了 specialist-audit ブロックを sed で抽出するコマンドの動作テストを追加
- [x] 3.3 モック JSONL（FAIL 含有）で `grep -q '"status":"FAIL"'` が exit 0 を返すことを検証
- [x] 3.4 モック JSONL（PASS のみ）で `grep -q '"status":"FAIL"'` が exit 1 を返すことを検証

## 4. ドキュメント追記

- [x] 4.1 `plugins/twl/CLAUDE.md` に「specialist-audit の JSON 出力 = grep 契約」の一文を追記する

## 5. 確認・仕上げ

- [x] 5.1 `twl check` が exit 0 で `specialist-audit` 関連 ERROR/WARNING なしで通過することを確認
- [x] 5.2 `bats plugins/twl/tests/bats/scripts/specialist-audit.bats` 全 PASS を確認
- [x] 5.3 `bats plugins/twl/tests/bats/scripts/su-observer-specialist-audit-grep.bats` 全 PASS を確認
- [x] 5.4 `(cd plugins/twl && twl --update-readme)` を実行し README に `specialist-audit` が反映されることを確認
- [x] 5.5 AC 検証コマンド（AC-1〜AC-8）を順に実行し全通過を確認
