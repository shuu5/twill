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

## chain-integrity-drift 用 few-shot（worker-workflow-integrity 専用）

`category: chain-integrity-drift` を出力する specialist (worker-workflow-integrity) は、以下の 2 例を参考にすること。
**純 soft gate** であり、**CRITICAL は出力禁止**。severity は WARNING / INFO のみ、confidence 上限 75（例外なし）。
**逐語引用は MUST**（両方の引用がない Finding は parser が INFO に降格する）。

### 例 1: chain step 順序の宣言と実装の乖離

```json
{
  "status": "WARN",
  "findings": [
    {
      "severity": "WARNING",
      "confidence": 75,
      "file": "skills/workflow-pr-verify/SKILL.md",
      "line": 42,
      "message": "chain step 順序乖離: architecture spec は workflow-pr-verify を ts-preflight → phase-review → scope-judge → pr-test の順と規定していますが、SKILL.md 実装は scope-judge を pr-test の後に置いています。deps.yaml の calls: 順序も SKILL.md に一致しており、architecture 側が逸脱しています（あるいは実装 2 箇所が誤っています）。\n\n[architecture 引用 architecture/domain/contexts/pr-cycle.md line 56]: 'workflow-pr-verify は ts-preflight → phase-review → scope-judge → pr-test の順で実行する'\n[実装引用 skills/workflow-pr-verify/SKILL.md line 42]: '1. ts-preflight\\n2. phase-review\\n3. pr-test\\n4. scope-judge'",
      "category": "chain-integrity-drift"
    }
  ]
}
```

### 例 2: 不変条件違反の検出

```json
{
  "status": "WARN",
  "findings": [
    {
      "severity": "WARNING",
      "confidence": 75,
      "file": "scripts/auto-merge.sh",
      "line": 88,
      "message": "不変条件違反: architecture spec の Constraints は auto-merge が squash + delete-branch で実行されることを規定していますが、auto-merge.sh は rebase を試行しています。不変条件 F (auto-merge は squash only) 違反の疑いがあります。\n\n[architecture 引用 architecture/domain/contexts/pr-cycle.md line 142]: 'auto-merge は必ず --squash --delete-branch で実行する。rebase / merge commit は禁止 (不変条件 F)'\n[実装引用 scripts/auto-merge.sh line 88]: 'gh pr merge --rebase --delete-branch \"$PR_NUM\"'",
      "category": "chain-integrity-drift"
    }
  ]
}
```

**chain-integrity-drift ルール**:
- **CRITICAL 禁止** (純 soft gate、merge を block しない)
- confidence 上限 **75** (例外なし)
- 両方の引用 (`[architecture 引用 ...]` と `[実装引用 ...]`) を含まない Finding は parser が INFO に降格
- `worker-architecture` と役割分担: 本 specialist は chain 三者整合性のみ、architecture-drift 全般は worker-architecture の担当
