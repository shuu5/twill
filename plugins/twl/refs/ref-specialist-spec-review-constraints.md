# ref-specialist-spec-review-constraints

tool-architect 7-phase multi-agent PR cycle の Phase F (Quality Review) 3 並列 specialist (`specialist-spec-review-{vocabulary,structure,ssot}.md`) の **共通制約** を集約する ref doc。各 agent file から本 ref を参照することで DRY を確保 (2026-05-16 F5、Phase 6 W3 fix)。

## 共通制約 (3 軸 = 3 specialist 全て適用)

以下の制約は specialist-spec-review-vocabulary / -structure / -ssot の **全 3 file で MUST**:

- **Read-only**: ファイル変更は行わない (Write / Edit 不可)
- **Task tool 禁止**: 全 check を自身で実行 (sub-agent spawn は公式制約で不可)
- **Bash は読み取り系のみ**: `git diff` / `git log` / `grep` / `cat` / `find` 等のみ (Write 系 sed/awk 禁止、ls/cat 等は安全)
- **confidence 閾値**: 80 未満の finding は出力しない (false-positive 排除、feature-dev:code-reviewer pattern 継承)
- **軸専任**: 他 軸 (用語/構造/SSoT のうち 担当外 2 軸) の問題は出力しない (overlap 排除、3 並列効率重視)

## 共通出力形式 (3 軸 = 3 specialist 全て適用)

`ref-specialist-output-schema.md` に従い JSON を出力 (stdout):

```json
{
  "status": "PASS | WARN | FAIL",
  "findings": [
    {
      "severity": "CRITICAL | WARNING | INFO",
      "confidence": 80-100,
      "file": "architecture/spec/<file>.html",
      "line": NNN,
      "message": "...",
      "category": "spec-vocabulary | spec-structure | spec-ssot"
    }
  ]
}
```

**status 導出ルール** (機械的、AI 裁量禁止):
- CRITICAL 1 件以上 → `FAIL`
- WARNING 1 件以上 (CRITICAL なし) → `WARN`
- それ以外 → `PASS`

**findings が 0 件**: `{"status": "PASS", "findings": []}`

## R-13: model=opus 固定

3 軸 specialist は `model: opus` 固定。詳細: [spec-management-rules.md R-13](../skills/tool-architect/refs/spec-management-rules.md)。

## 関連

- `architecture/spec/tool-architecture.html` §3.7.3 (3 file 別 sub-section 仕様)
- `plugins/twl/skills/tool-architect/refs/spec-management-rules.md` R-12 (MUST NOT SKIP) + R-13 (opus 固定)
- `plugins/twl/refs/ref-specialist-output-schema.md` (共通出力 schema、category enum)
- `plugins/twl/agents/specialist-spec-review-vocabulary.md` (Phase F 軸 1)
- `plugins/twl/agents/specialist-spec-review-structure.md` (Phase F 軸 2)
- `plugins/twl/agents/specialist-spec-review-ssot.md` (Phase F 軸 3)
