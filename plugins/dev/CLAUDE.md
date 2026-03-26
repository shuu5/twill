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

## 編集フロー（必須）

```
コンポーネント編集 → deps.yaml 更新 → loom --check → loom --update-readme
```

## 視覚化

`loom` CLI 必須（独自スクリプト禁止）。
