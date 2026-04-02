# loom-plugin-dev

Claude Code dev plugin（chain-driven + autopilot-first）。claude-plugin-dev の後継として新規構築。

## 構成

- bare repo: `~/projects/local-projects/loom-plugin-dev/.bare`
- main worktree: `~/projects/local-projects/loom-plugin-dev/main/`
- feature worktrees: `~/projects/local-projects/loom-plugin-dev/worktrees/<branch>/`

## 設計哲学

**LLM は判断のために使う。機械的にできることは機械に任せる。**

## プラグイン構成

### deps.yaml = SSOT（Single Source of Truth）

deps.yaml v3.0 がプラグイン構成の唯一の情報源。

### Controller は4つのみ

| controller | 役割 |
|---|---|
| co-autopilot | Issue 実装の実行（単一 Issue も autopilot 経由） |
| co-issue | Issue 作成（要望→Issue 変換） |
| co-project | プロジェクト管理（create / migrate / snapshot） |
| co-architect | アーキテクチャ設計 |

## Bare repo 構造検証（セッション開始時チェック）

以下の3条件を全て満たすこと:

1. `.bare/` が存在する（`.git/` ディレクトリではない）
2. `main/.git` がファイル（ディレクトリではない）で `.bare` を指す
3. CWD が `main/` 配下である（`worktrees/` 配下での起動は禁止）

### セッション起動ルール

- Claude Code は必ず `main/` で起動する
- `worktrees/` 配下で起動してはならない（worktree 削除で bash CWD 消失のリスク）
- worktree 内での作業は `workflow-setup` が自動的にハンドルする

## 編集フロー（必須）

```
コンポーネント編集 → deps.yaml 更新 → loom check → loom update-readme
```

## Project Board

このプロジェクトは GitHub Project Board（`shuu5/loom-dev-ecosystem` Project #3）で Issue を管理する。
Board はクロスリポジトリ（loom-plugin-dev + loom）のため、**Board アイテムの取得には `gh project item-list` を使う**。

```bash
# 非 Done の Board アイテムを取得（正解）
gh project item-list 3 --owner shuu5 --format json --limit 200 \
  | jq -r '.items[] | select(.status != "Done") | "\(.content.number) [\(.status)] repo=\(.content.repository) \(.content.title)"'

# NG: gh issue list は現在リポジトリのみ → クロスリポジトリ Board には使えない
```

## 視覚化

`loom` CLI 必須（独自スクリプト禁止）。
