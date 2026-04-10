# plugin-twl

Claude Code twl plugin（chain-driven + autopilot-first）。TWiLL モノリポ `plugins/twl/` として管理。

## 構成

- モノリポ: `~/projects/local-projects/twill/main/plugins/twl/`

## 設計哲学

**LLM は判断のために使う。機械的にできることは機械に任せる。**

## プラグイン構成

### deps.yaml = SSOT（Single Source of Truth）

deps.yaml v3.0 がプラグイン構成の唯一の情報源。

### Controller は6つ

| controller | 役割 |
|---|---|
| co-autopilot | Issue 実装の実行（単一 Issue も autopilot 経由） |
| co-issue | Issue 作成（要望→Issue 変換） |
| co-project | プロジェクト管理（create / migrate / snapshot） |
| co-architect | アーキテクチャ設計 |
| co-utility | スタンドアロンユーティリティ操作 |
| co-self-improve | ライブセッション観察と能動的 self-improvement（out-of-process observation） |

### Supervisor は1つ

| supervisor | 役割 |
|---|---|
| su-observer | プロジェクト常駐のメタ認知・Wave 管理・知識外部化（ADR-014） |

## Bare repo 構造検証（セッション開始時チェック）

以下の3条件を全て満たすこと:

1. `.bare/` が存在する（`.git/` ディレクトリではない）
2. `main/.git` がファイル（ディレクトリではない）で `.bare` を指す
3. CWD が `main/` 配下である（Pilot セッション）、または Pilot が作成した worktree 配下である（Worker セッション）

### セッション起動ルール

**Pilot（制御側）:**
- 必ず `main/` で起動する
- `worktrees/` 配下で直接起動してはならない（worktree 削除で bash CWD 消失のリスク）

**Worker（実装側、autopilot 経由で起動）:**
- Pilot が事前作成した worktree ディレクトリで起動される（ADR-008 準拠）
- Worker は worktree 内で作業し、完了後に merge-ready を宣言する
- Worker が自ら worktree を作成・削除してはならない（不変条件 B）

## 編集フロー（必須）

```
コンポーネント編集 → deps.yaml 更新 → twl check → twl update-readme
```

## Project Board

- Project: `twill-ecosystem` (#6)、Owner: `shuu5`
- リンク済みリポ: twill

## 視覚化

`twl` CLI 必須（独自スクリプト禁止）。
