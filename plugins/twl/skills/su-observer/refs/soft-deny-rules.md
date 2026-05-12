---
schema_version: 1
# soft_deny ルール定義 (SSoT)
# parse: yq 互換 yaml
# layer: confirm = Layer 1 Confirm 昇格, escalate = Layer 2 Escalate 昇格
rules:
  - id: code-from-external
    regex: "(curl|wget)\\s+\\S.*\\.sh\\s*\\|\\s*(bash|sh|sudo)"
    layer: confirm
    rationale: "外部スクリプトの直接実行はコード審査を迂回するリスクがある"
  - id: irreversible-local-destruction
    regex: "rm\\s+-rf?\\s+(/|~|\\$HOME|\\$\\{HOME\\})"
    layer: confirm
    rationale: "ファイルシステムの不可逆的な破壊につながる"
  - id: memory-poisoning
    regex: "(doobidoo.*delete|MEMORY\\.md\\s*>|memory_delete\\s)"
    layer: confirm
    rationale: "永続記憶の改ざん・削除はシステム整合性を損なう"
  - id: secret-exfiltration
    regex: "(\\.env|\\.ssh|\\.aws|GOOGLE_APPLICATION_CREDENTIALS|API_KEY=|SECRET=)"
    layer: confirm
    rationale: "秘密情報の漏洩リスクがある操作"
  - id: privilege-escalation
    regex: "(sudo |chmod\\s+\\+s|setcap )"
    layer: escalate
    rationale: "権限昇格は Layer 2 Escalate のみ（auto/confirm 禁止）"
---
# soft-deny-rules.md

Issue #973: permission UI auto-response の soft_deny ルール定義。

## 概要

observer Auto レイヤーが permission UI を自動応答する際、`soft_deny_match.py` がこのファイルを読み込み、
prompt_context に対してルールを照合する。

- `layer: confirm` → Layer 1 Confirm 昇格（exit 1）
- `layer: escalate` → Layer 2 Escalate 昇格（exit 2）
- non-match → Layer 0 Auto 承認（exit 0）

## ルール一覧

| id | layer | 概要 |
|----|-------|------|
| code-from-external | confirm | 外部スクリプトの直接実行（curl/wget \| bash） |
| irreversible-local-destruction | confirm | 不可逆的なファイルシステム破壊（rm -rf /） |
| memory-poisoning | confirm | 永続記憶の改ざん・削除 |
| secret-exfiltration | confirm | 秘密情報の漏洩リスクがある操作 |
| privilege-escalation | escalate | 権限昇格（sudo/chmod +s/setcap） |
