---
name: twl:tool-project
description: |
  tool-project: GitHub Project Board 5 領域 × 4 手段 boundary (Phase 2 で本格実装)。
  Phase 1 PoC C4 で minimum stub 配置、本格機能は Phase 2 で展開。

  Use when user: needs to manage GitHub Project Board (status transitions, field edits, option rename).
type: tool
effort: low
allowed-tools: [Bash, Read, Edit, Agent]
spawnable_by:
  - user
  - tool-architect
  - tool-sandbox-runner
# administrator は spawn 不可 (tool-architecture.html §2.1 / ADR-040 gate、boundary-matrix.html)
---

# tool-project (stub)

Phase 1 PoC C4 配置 minimum stub。
本格実装は Phase 2 で。

## 本格実装予定 (Phase 2)

- GitHub Project 5 領域 (Idea / Explored / Refined / Implementing / Merged) × 4 手段 (gh project CLI / GraphQL API / webhook / manual)
- option_id 維持 GraphQL mutation (Phase I dig Q3 確定): `updateProjectV2Field` displayName のみ rename、option_id は保全
- migration script: 旧 status (Todo / InProgress / Done) → 新 status (Idea / Implementing / Merged) rename
- branch protection auto-merge 連携 (phaser-pr が PR 作成、tool-project が merge gate verify)

## 関連 spec
- tool-architecture.html §4 (tool-project 詳細)
- boundary-matrix.html (Project Board scope、tool-project 専任)
- Phase 2 dig topic: option_id GraphQL 詳細 (Plan linked-jumping-eich.md Phase 2 dig 5 件中 1)
