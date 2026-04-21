## 1. 不変条件ソース確認

- [x] 1.1 `plugins/twl/architecture/domain/contexts/autopilot.md` の不変条件 A-M テーブルを読み込み、全 13 件の定義・根拠・DeltaSpec 参照を記録する
- [x] 1.2 `plugins/twl/tests/bats/invariants/autopilot-invariants.bats` の invariant-J（L357-361）と invariant-K（L419-423）の現在の grep パターンを確認する

## 2. ref-invariants.md 新規作成

- [x] 2.1 `plugins/twl/refs/ref-invariants.md` を新規作成し、ファイルヘッダー（title, description, 更新日）を記載する
- [x] 2.2 不変条件 A〜G を `## 不変条件 X: <title>` 形式で記載する（定義・根拠・検証方法・影響範囲）
- [x] 2.3 不変条件 H〜M を同形式で記載する（H: "ADR なし — 慣習的制約"、L/M: "#789 生成予定"注記）
- [x] 2.4 ファイル末尾に SU-* 境界説明（`skills/su-observer/SKILL.md` へのリンク）を追加する

## 3. bats ファイル更新（定義削除と同時実施）

- [x] 3.1 `autopilot-invariants.bats` の invariant-J テスト（L357-361）: grep 対象を `refs/ref-invariants.md` に変更、パターンを `## 不変条件 J:` に更新
- [x] 3.2 `autopilot-invariants.bats` の invariant-K テスト（L419-423）: grep 対象を `refs/ref-invariants.md` に変更、パターンを `## 不変条件 K:` に更新

## 4. 既存ドキュメント更新

- [x] 4.1 `autopilot.md` の不変条件 A-M 定義テーブル（224行目付近）を削除し、`ref-invariants.md` へのリンクに置換する
- [x] 4.2 `plugins/twl/CLAUDE.md` の不変条件 B 言及を `ref-invariants.md` へのリンクに更新する
- [x] 4.3 `plugins/twl/skills/su-observer/SKILL.md` に SU-* と不変条件 A-M の境界説明と `ref-invariants.md` リンクを追加する

## 5. 構造検証 bats 作成

- [x] 5.1 `plugins/twl/tests/bats/invariants/ref-invariants-structure.bats` を新規作成し、section 存在（13 件）・半角コロン・半角大文字のlintテストを実装する

## 6. deps.yaml / README 更新

- [x] 6.1 `plugins/twl/deps.yaml` に `ref-invariants` エントリを `type: reference` で追加する
- [x] 6.2 `plugins/twl/README.md` の Refs 一覧に `ref-invariants` を追加し合計カウントを 18 → 19 に更新する

## 7. 検証

- [x] 7.1 `bats plugins/twl/tests/bats/invariants/ref-invariants-structure.bats` を実行し PASS を確認する
- [x] 7.2 `bats plugins/twl/tests/bats/invariants/autopilot-invariants.bats` の invariant-J/K テストが PASS することを確認する
- [x] 7.3 `twl --validate` を実行して deps.yaml 整合性を確認する
