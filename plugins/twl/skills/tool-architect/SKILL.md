---
name: twl:tool-architect
description: |
  tool-architect: architecture/spec/* edit の唯一 author。
  spec edit boundary hook (pre-tool-use-spec-write-boundary.sh、Cluster 1 配置) で caller を機械的に enforce。
  spec 編集時に `export TWL_TOOL_CONTEXT=tool-architect` を必須。
  recursive PR cycle (spec edit → PR → review → merge) + verify-coverage.sh 連携 (Phase 2 で本格実装)。

  Use when user: needs to edit architecture/spec/* files (e.g., dig, refactor, verify upgrade).
type: tool
effort: medium
allowed-tools: [Bash, Read, Edit, Write, Skill, Agent]
spawnable_by:
  - user
  - administrator
---

# tool-architect

architecture/spec/* edit の唯一 author。
hook (pre-tool-use-spec-write-boundary.sh、Cluster 1 配置) で機械的 enforce。

## 前提

- spec 編集前に `export TWL_TOOL_CONTEXT=tool-architect` を必須 (caller marker)
- 他 caller (phaser-* / tool-project / etc.) からの spec 編集は hook が deny (JSON permissionDecision: deny)
- spec 編集後は `unset TWL_TOOL_CONTEXT` で clean (caller marker leak 防止)

## Phase 1 PoC C4 stub (本格実装は Phase 2 で)

本 SKILL.md は Cluster 4 で minimum entry point として配置、本格機能は Phase 2 で展開:

- **recursive PR cycle**: spec edit → workflow-pr-cycle → review → merge (tool-architecture.html §3.3)
- **verify-coverage.sh 連携**: spec 内 verify-status badge (inferred/deduced/verified/experiment-verified) と EXP 整合性 audit (EXP-027 で検証済)
- **specialist-spec-review agent**: spec edit の cross-AI review (Sonnet model、本 session の Opus と異なる視点で findings)
- **spec drift cleanup**: 旧 用語 (worker / phase-* / pilot) → 新 (specialist / phaser-* / 等) の機械的 rename

## 使い方 (current minimal、Phase 2 で expand)

```bash
# 1. caller marker set
export TWL_TOOL_CONTEXT=tool-architect

# 2. LLM が architecture/spec/* を Edit/Write/NotebookEdit
#    (例: spec refactor、dig 結果反映、verify-status upgrade)

# 3. caller marker unset (clean)
unset TWL_TOOL_CONTEXT

# 4. (Phase 2 で本格化) workflow-pr-cycle を呼んで PR 作成 + review + merge
```

## 関連 spec
- tool-architecture.html §3 (tool-architect 詳細)
- hooks-mcp-policy.html §4 (twill 実装現状、Phase 1 PoC で spec-write-boundary hook 配置)
- gate-hook.html (PreToolUse gate 全般)
