## ADDED Requirements

### Requirement: specialist-audit JSON 契約ドキュメント

`plugins/twl/CLAUDE.md` または `plugins/twl/architecture/domain/contexts/supervision.md` のいずれかに「specialist-audit の JSON 出力 = grep 契約」を一文以上記述しなければならない（SHALL）。将来 `--summary` に戻した場合の回帰防止根拠を残す。

#### Scenario: grep 契約が文書化されている
- **WHEN** `grep -qE "specialist-audit.*(JSON|json).*grep|grep.*specialist-audit.*(JSON|json)" plugins/twl/CLAUDE.md plugins/twl/architecture/domain/contexts/supervision.md` を実行する（2>/dev/null 付き）
- **THEN** exit 0 を返す（少なくとも1ファイルにマッチが存在する）
