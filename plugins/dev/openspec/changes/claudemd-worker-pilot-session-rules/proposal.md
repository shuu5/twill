## Why

ADR-008 と #210 により Worker は Pilot が事前作成した worktree 内で cld セッションとして起動されるスタイルに移行済みだが、CLAUDE.md のセッション起動ルールが Pilot/Worker を区別せず「main/ 限定」を全セッションに強制しており、Worker セッションの正当な起動場所（worktree）を否定する記述になっている。

## What Changes

- CLAUDE.md「Bare repo 構造検証」セクションを Pilot 向けチェックであることを明示するよう修正
- CLAUDE.md「セッション起動ルール」を Pilot/Worker それぞれに分けて記述
- Worker が worktree 内で起動されることを CLAUDE.md 上で明記

## Capabilities

### New Capabilities

- CLAUDE.md で Pilot セッションと Worker セッションを区別したルールが参照できる

### Modified Capabilities

- 「Bare repo 構造検証（セッション起動時チェック）」セクション: Pilot 専用チェックとして明示
- 「セッション起動ルール」セクション: Pilot（main/ で起動）と Worker（worktree 内で起動）を分離記述

## Impact

- 変更対象: `CLAUDE.md`（L34-42 の「Bare repo 構造検証」「セッション起動ルール」セクション）
- 影響範囲: CLAUDE.md を参照するすべてのセッション（Pilot・Worker・手動）
- 依存 ADR: ADR-008（Worktree Lifecycle Pilot Ownership）
- 関連 Issue: #210（Worker を worktree ディレクトリで起動する）
