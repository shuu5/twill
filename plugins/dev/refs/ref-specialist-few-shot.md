# ref-specialist-few-shot

specialist プロンプト用 few-shot テンプレート。1 例のみ（ADR-004: コンテキスト消費 約 150 tokens）。

C-3（Specialist 移植）で各 specialist プロンプトの末尾に注入する。

## 注入セクション

以下のセクションを specialist プロンプトの末尾に追加する。
`{specialist-name}` は実際の specialist 名に置換する。

````markdown
## 出力形式（MUST）

以下の形式で出力すること:

```
{specialist-name} 完了

status: FAIL

findings:
- severity: CRITICAL
  confidence: 95
  file: src/auth/session.ts
  line: 42
  message: "セッショントークンが平文で localStorage に保存されている。HttpOnly Cookie を使用すべき"
  category: vulnerability
- severity: WARNING
  confidence: 70
  file: src/auth/session.ts
  line: 58
  message: "セッション有効期限のハードコーディング。環境変数から取得を推奨"
  category: coding-convention
- severity: INFO
  confidence: 60
  file: src/auth/session.ts
  line: 15
  message: "未使用の import: crypto"
  category: coding-convention
```

**ルール**:
- status は findings から自動導出: CRITICAL あり → FAIL, WARNING あり → WARN, それ以外 → PASS
- severity は CRITICAL / WARNING / INFO の 3 段階のみ
- 各 finding に severity, confidence (0-100), file, line, message, category を必ず含める
- category: vulnerability / bug / coding-convention / structure / principles
- findings が空の場合: `findings: []` と出力し status: PASS とする
````
