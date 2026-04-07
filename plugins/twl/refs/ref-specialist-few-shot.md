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
- category: vulnerability / bug / coding-convention / structure / principles / ac-alignment / ac-alignment-unknown
- findings が空の場合: `findings: []` と出力し status: PASS とする
````

## ac-alignment 用 few-shot（worker-issue-pr-alignment 専用）

`category: ac-alignment` および `ac-alignment-unknown` を出力する specialist は、以下の 2 例を参考にすること。
**逐語引用は MUST**（引用なしの CRITICAL は parser が WARNING に自動降格する）。

```json
{
  "status": "FAIL",
  "findings": [
    {
      "severity": "CRITICAL",
      "confidence": 80,
      "file": "Issue body",
      "line": 1,
      "message": "AC「~90 件のコンポーネントに worker-prompt-reviewer を実行し PASS 判定を得る」が PR diff にゼロ言及。Issue 引用: 「worker-prompt-reviewer による品質レビュー PASS」。diff 引用: 「diff にゼロ言及（worker-prompt-reviewer の実行記録なし、deps.yaml への refined_by フィールド追加のみ）」。",
      "category": "ac-alignment"
    },
    {
      "severity": "INFO",
      "confidence": 50,
      "file": "Issue body",
      "line": 1,
      "message": "AC「運用初期の段階的導入用に gate_role: soft フィールドを追加」の達成度が判断不能。Issue 引用: 「deps.yaml の specialist エントリに gate_role: soft を追加」。判断不能の理由: gate_role フィールドの semantics が他コンポーネントで未定義のため、追加のみで運用効果が発揮されているか LLM 単独では判定できない。人間レビューを推奨。",
      "category": "ac-alignment-unknown"
    }
  ]
}
```

**ac-alignment ルール**:
- CRITICAL は「diff にゼロ言及」かつ「ac-verify 未検出」かつ「Issue body の AC が明示的」の 3 条件を満たすときのみ
- 部分達成 / 軽量解釈 / 拡大解釈はすべて WARNING（confidence 70-75）
- 逐語引用が無い Finding は parser が CRITICAL → WARNING に自動降格する
