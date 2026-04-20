## Context

`merge-gate-check-spawn.sh` (L28) は `specialist-audit.sh` を呼び出すが、`plugins/twl/deps.yaml` の `merge-gate-check-spawn` エントリに `calls:` セクションが存在しない。また `specialist-audit.sh` 自体も `scripts:` セクションに未登録のため、`twl check` の SSOT カバレッジから漏れている。

さらに `su-observer/SKILL.md` の grep 契約（`grep -q '"status":"FAIL"'`）と `specialist-audit.sh` の実際の JSON 出力形式の整合性を保証するテストが存在しない。主要バグ（F3: `--summary` 不一致）は commit `2bd9130` で既修正だが、将来の回帰を防ぐ機械的テストが欠如している。

## Goals / Non-Goals

**Goals:**
- `deps.yaml` の `scripts:` セクションに `specialist-audit` を登録し `twl check` のカバレッジに含める
- `merge-gate-check-spawn` の `calls:` セクションに `specialist-audit` を追加し SSOT を完成させる
- `specialist-audit.bats`: スクリプトの基本動作（PASS/FAIL/warn-only/quick/JSON 構造）を検証
- `su-observer-specialist-audit-grep.bats`: SKILL.md grep 契約ロック
- ドキュメントに「specialist-audit の JSON 出力 = grep 契約」を記述

**Non-Goals:**
- `specialist-audit.sh` に `--check-log` オプション追加（別 Issue）
- `--summary` 互換性テスト（非推奨化意図を明示するため含めない）
- CI パイプライン統合の変更（現状 `bats` 直接実行で検証）

## Decisions

### D1: deps.yaml scripts: エントリ追加位置
`merge-gate-check-spawn` の直後（L2764 以降）に `specialist-audit` エントリを追加する。既存スクリプトの並び順は機能ドメイン別のため、`merge-gate-check-spawn` の隣接位置が最も追いやすい。

### D2: calls: 形式
`merge-gate-cross-pr-ac` の `calls:\n  - script: <name>` 形式に準拠する（`- script:` プレフィックス統一）。

### D3: BATS テスト設計（specialist-audit.bats）
既存の `plugins/twl/tests/bats/helpers/` と `plugins/twl/tests/bats/scripts/` のパターンを踏襲。モック JSONL と `pr-review-manifest.bats` の stub 手法を再利用。

5ケース:
1. expected ⊆ actual → exit 0 + JSON `.status == "PASS"`
2. missing 非空 + `--warn-only` → exit 0 + JSON `.status == "FAIL"`
3. missing 非空 + strict（default） → exit 1
4. `--quick` + missing 非空 → exit 0（WARN）
5. default 出力が jq parse 可能かつ `.status/.missing/.actual/.expected` キーを持つ

### D4: grep 契約ロック（su-observer-specialist-audit-grep.bats）
`plugins/twl/tests/bats/helpers/mock-specialists.bash` のモック生成手法で fixture JSONL を作成し、`grep -q '"status":"FAIL"'` の動作を検証する。SKILL.md から Wave 完了ブロックを sed で抽出するテストも含める。

### D5: ドキュメント追記先
`plugins/twl/CLAUDE.md` に追記する（`supervision.md` は Architecture Spec の正式文書で変更コストが高いため、まず CLAUDE.md に追記し supervision.md は将来の Architecture Review で更新）。

## Risks / Trade-offs

- **BATS CI 統合外**: `tests/run-all.sh` は `scenarios/*.test.sh` のみ実行するため、新規 BATS は CI から `bats plugins/twl/tests/bats/scripts/*.bats` で別途実行が必要。AC 検証コマンドに明示するため実害は低い。
- **specialist-audit.sh の将来変更**: `--check-log` オプション追加時に su-observer-specialist-audit-grep.bats を更新する必要があるが、grep 契約自体を変更しない限りテストは通り続ける。
