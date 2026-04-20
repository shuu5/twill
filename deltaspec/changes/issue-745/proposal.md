## Why

`merge-gate-check-spawn` は実装上 `specialist-audit.sh` を呼び出すが、`plugins/twl/deps.yaml` の当該エントリに `calls:` セクションが存在せず、`specialist-audit.sh` 自体も `scripts:` セクションに未登録（SSOT 違反）。また SKILL.md の grep 契約（`"status":"FAIL"`）と実際の JSON 出力形式の整合性を保証するテストが存在しないため、将来の変更による回帰を機械的に防止できない。

## What Changes

- `plugins/twl/deps.yaml` の `scripts:` セクションに `specialist-audit` エントリ（`type: script`, `path: scripts/specialist-audit.sh`, `description`）を追加
- `plugins/twl/deps.yaml` の `merge-gate-check-spawn` エントリに `calls:\n  - script: specialist-audit` を追加（`merge-gate-cross-pr-ac` の形式に準拠）
- `plugins/twl/tests/bats/scripts/specialist-audit.bats` を新規追加（PASS/FAIL/warn-only/quick/JSON 契約の5ケース）
- `plugins/twl/tests/bats/scripts/su-observer-specialist-audit-grep.bats` を新規追加（SKILL.md grep 契約ロック）
- `plugins/twl/CLAUDE.md` または `plugins/twl/architecture/domain/contexts/supervision.md` に「specialist-audit の JSON 出力 = grep 契約」の記述を追加

## Capabilities

### New Capabilities

- **deps.yaml SSOT 完全化**: `specialist-audit` がスクリプトとして登録され、`merge-gate-check-spawn` の依存関係が明示される。`twl check` で自動検証可能になる
- **specialist-audit BATS テスト**: PASS/FAIL/warn-only/quick/JSON 出力構造の5ケースを機械的に検証し、スクリプトの基本動作を保証する
- **grep 契約ロック**: `SKILL.md` の `grep -q '"status":"FAIL"'` が specialist-audit の JSON 出力に対して正しく動作することをテストで固定する

### Modified Capabilities

- **README.md 反映**: `twl --update-readme` により `specialist-audit` が登録済みコンポーネントとして表示される

## Impact

- `plugins/twl/deps.yaml`: `scripts:` セクション追加 + `merge-gate-check-spawn` エントリ修正
- `plugins/twl/tests/bats/scripts/specialist-audit.bats`: 新規追加
- `plugins/twl/tests/bats/scripts/su-observer-specialist-audit-grep.bats`: 新規追加
- `plugins/twl/CLAUDE.md` または `plugins/twl/architecture/domain/contexts/supervision.md`: ドキュメント追記
- 既存 runtime コードへの変更なし → 回帰リスク極小
