## Context

ADR-001 で autopilot-first 設計を決定し、Worker 層のフラグベース分岐（`--auto`/`--auto-merge`）を `issue-{N}.json` ベースの状態判定に置き換える方針を定めた。`state-read.sh` と `state-write.sh` は既に実装済みだが、Worker 層のコマンド・スキルが旧フラグを参照し続けている。

影響ファイル:
- `commands/autopilot-launch.md` — プロンプトに `--auto --auto-merge` が残存
- `skills/workflow-setup/SKILL.md` — `--auto`/`--auto-merge` 引数解析が残存
- `commands/opsx-apply.md` — `--auto` モード分岐が残存
- `commands/pr-cycle-analysis.md` — `--auto` 引数が残存
- `commands/self-improve-propose.md` — `--auto` 引数が残存
- `skills/co-autopilot/SKILL.md` — `--auto-merge` 言及が残存
- `openspec/changes/c-2d-.../specs/session-management/spec.md` — 矛盾する記述

## Goals / Non-Goals

**Goals:**

- Worker 層の全コンポーネントから `--auto`/`--auto-merge` フラグ参照を完全除去
- `state-read.sh` による統一 autopilot 判定パターンを全対象コンポーネントに導入
- chain 自動継続を `workflow-test-ready`/`workflow-pr-cycle` と同じ「autopilot 配下→自動、standalone→案内」パターンに統一
- openspec c-2d session-management の矛盾を解消

**Non-Goals:**

- co-autopilot の `--auto`（計画確認スキップ）の廃止。これは Pilot 層フラグであり Worker 層の問題とは独立
- テストシナリオの大規模書き換え（最小限のアサーション修正のみ）
- `state-read.sh`/`state-write.sh` 自体の変更（既に完成済み）

## Decisions

### D1: autopilot 判定パターン

各コンポーネントで以下の統一パターンを使用:

```bash
AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status)
IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
```

- `status=running` → autopilot 配下（自動継続）
- 空文字列（ファイル不在）→ standalone 実行（案内表示で停止）

**根拠**: `state-read.sh` はファイル不在時に空文字列を返す既存動作（state-read.sh:94-96）を利用。Worker が autopilot-launch.md 経由で起動された場合のみ `issue-{N}.json` が初期化される（autopilot-launch.md Step 2）。

### D2: chain 自動継続の統一

| コンポーネント | 変更前 | 変更後 |
|--------------|--------|--------|
| workflow-setup | `--auto` → 自動継続 | IS_AUTOPILOT → 自動継続 |
| opsx-apply | `--auto` → 自動継続 | IS_AUTOPILOT → 自動継続 |
| pr-cycle-analysis | `--auto` → 自動起票 | IS_AUTOPILOT → 自動起票 |
| self-improve-propose | `--auto` → 自動承認 | IS_AUTOPILOT → 自動承認 |

### D3: autopilot-launch プロンプト変更

```
# Before
PROMPT="/twl:workflow-setup --auto --auto-merge #${ISSUE}"

# After
PROMPT="/twl:workflow-setup #${ISSUE}"
```

フラグが不要になるため Issue 番号のみ渡す。Worker は `state-read.sh` で自身の状態を確認する。

### D4: co-autopilot での `--auto-merge` 除去

`--auto-merge` は完全に死んだフラグ（独立して消費される箇所が皆無）。co-autopilot の `--auto` は Pilot 層フラグとして存続させるが、`--auto-merge` への言及は全て除去する。

### D5: openspec 矛盾解消

c-2d session-management spec の Line 44:
```
# Before
Worker 起動プロンプトは `/twl:workflow-setup --auto --auto-merge #${ISSUE}` を使用しなければならない（SHALL）。

# After
Worker 起動プロンプトは `/twl:workflow-setup #${ISSUE}` を使用しなければならない（SHALL）。
```

## Risks / Trade-offs

### R1: standalone 実行時の判定

standalone で `workflow-setup #47` を実行した場合、`issue-47.json` が存在しないため空文字列が返り、案内表示で停止する。これは意図通りの動作。ただし、前回の autopilot セッションの `issue-47.json` が残存している場合は誤判定の可能性がある。

**緩和策**: `state-write.sh --init` は autopilot-launch.md でのみ呼ばれ、autopilot 終了時に session.json と共にクリーンアップされる（既存の設計）。

### R2: openspec の過去 change への影響

過去 change（c-2d, b-3, b-4, b-5 等）に `--auto-merge` 参照が残るが、これらは archive またはマージ済み。実装コードとの整合性のために修正するが、影響は軽微。
