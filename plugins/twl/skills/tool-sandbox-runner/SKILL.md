---
name: twl:tool-sandbox-runner
description: |
  tool-sandbox-runner: twill-self sandbox + EXP runner (Phase 2 で本格実装)。
  Phase 1 PoC C4 で minimum stub 配置、本格機能は Phase 2 で展開。

  Use when user: needs to run sandbox experiments (EXP fire, smoke test, lesson auto-record).
type: tool
effort: low
allowed-tools: [Bash, Read, Edit, Agent]
spawnable_by:
  - user
  - administrator
---

# tool-sandbox-runner (stub)

Phase 1 PoC C4 配置 minimum stub。
本格実装は Phase 2 で (旧 tool-self-improve から rename、第 4 弾 dig 確定)。

## 本格実装予定 (Phase 2)

- **twill-self sandbox**: test-target/main orphan branch で sandbox 環境構築 (sandbox-experiment.html catalog)
- **EXP runner**: `experiments/run-all.sh` で全 EXP fire (smoke + bats、Phase G で実装済)
- **sandbox catalog**: ts-nextjs-hono-mono / R-bioconductor-package / etc. を `plugins/twl/sandboxes/<name>/{sandbox.yaml, setup.sh, features.yaml}` 形式で listing
- **doobidoo lesson 自動記録**: severity=critical の lesson のみ Idea Issue 起票 (重複 check 後、Inv N + ADR-036)

## 関連 spec
- tool-architecture.html §5 (tool-sandbox-runner 詳細、旧 tool-self-improve rename)
- sandbox-experiment.html (sandbox catalog + EXP-id 体系)
- experiment-index.html (EXP-001〜043 listing、Phase G で実装済 smoke / bats)
