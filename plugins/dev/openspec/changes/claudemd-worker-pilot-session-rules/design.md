## Context

ADR-008 により、Autopilot の Worker は Pilot が事前作成した worktree 内で cld セッションとして起動される。しかし現行の CLAUDE.md（L30-42）は Pilot/Worker を区別せず、全セッションに「main/ 配下でのみ起動」を強制している。これは Worker セッションが worktree 内（`worktrees/<branch>/`）で正当に動作するアーキテクチャと矛盾する。

対象箇所:
- L30-36: 「Bare repo 構造検証（セッション開始時チェック）」セクション — 条件 3 が `worktrees/` 起動を全面禁止
- L38-42: 「セッション起動ルール」セクション — Worker の worktree 起動を否定する記述

## Goals / Non-Goals

**Goals:**
- CLAUDE.md の「Bare repo 構造検証」を Pilot 専用チェックとして明示
- 「セッション起動ルール」を Pilot と Worker に分けて正確に記述
- Worker が worktree 内で起動されることを CLAUDE.md 上で明記

**Non-Goals:**
- CLAUDE.md 以外のファイルへの変更（ADR, スクリプト等）
- Worker の起動フローそのものの変更

## Decisions

### CLAUDE.md の修正方針

**「Bare repo 構造検証」セクション**:
- セクションタイトルに `（Pilot セッション用）` を付記
- 条件 3「CWD が `main/` 配下である」は Pilot 向けであることを明示
- 補足として「Worker セッションは worktree ディレクトリが CWD となる」を追記

**「セッション起動ルール」セクション**:
- Pilot と Worker をそれぞれ見出しで分離
- Pilot: `main/` で起動（従来通り）、worktree 削除リスクの説明を保持
- Worker: Pilot が作成した `worktrees/<branch>/` 内で起動（ADR-008 準拠）

### 変更量

合計 10 行未満の修正（既存の2セクションを拡張・分割）。新規セクション不要。

## Risks / Trade-offs

- 変更はドキュメントのみであり、実装への影響はない
- 既存の Pilot 起動フローは変わらないため、誤読による混乱リスクは低い
- CLAUDE.md は Claude Code セッション起動時に自動参照されるため、記述の正確性が重要
