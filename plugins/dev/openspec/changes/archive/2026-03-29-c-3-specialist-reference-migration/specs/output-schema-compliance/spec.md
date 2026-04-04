## ADDED Requirements

### Requirement: 共通出力スキーマ準拠

全 27 specialists の出力が ADR-004 共通出力スキーマに準拠しなければならない（MUST）。出力は以下の JSON 構造を持つこと（SHALL）:

```json
{
  "status": "PASS | WARN | FAIL",
  "findings": [
    {
      "severity": "CRITICAL | WARNING | INFO",
      "confidence": 0-100,
      "file": "path/to/file",
      "line": 42,
      "message": "説明",
      "category": "カテゴリ名"
    }
  ]
}
```

#### Scenario: PASS 出力
- **WHEN** specialist が CRITICAL/WARNING の finding を検出しなかった
- **THEN** status が `PASS` で findings が空配列または INFO のみ

#### Scenario: FAIL 出力
- **WHEN** specialist が CRITICAL の finding を 1 件以上検出した
- **THEN** status が `FAIL` で findings に severity=CRITICAL のエントリが含まれる

#### Scenario: findings の必須フィールド
- **WHEN** specialist が finding を出力する
- **THEN** 各 finding に severity, confidence, file, line, message, category の 6 フィールドが全て含まれる

### Requirement: severity 3 段階統一

全 specialist の severity 表記を CRITICAL/WARNING/INFO の 3 段階に統一しなければならない（MUST）。旧表記からのマッピングは以下に従うこと（SHALL）:

- High / Critical / Error → CRITICAL
- Medium / Warning → WARNING
- Low / Suggestion / Info → INFO

#### Scenario: 旧 severity 表記の排除
- **WHEN** 移植完了後に全 specialist ファイルを検索する
- **THEN** "High", "Medium", "Low", "Suggestion", "Error" の severity 表記が存在しない

### Requirement: 出力形式セクションの追記

全 specialist のプロンプト末尾に出力形式セクションを追記しなければならない（SHALL）。このセクションは ref-specialist-output-schema を参照し、JSON 構造の出力を指示すること（MUST）。

#### Scenario: 出力形式セクションの存在
- **WHEN** 任意の specialist ファイルを確認する
- **THEN** `## 出力形式（MUST）` セクションが存在し、ref-specialist-output-schema への参照が含まれる

#### Scenario: specialist-output-parse.sh との互換性
- **WHEN** specialist の出力を specialist-output-parse.sh に渡す
- **THEN** status と findings が正しくパースされる
