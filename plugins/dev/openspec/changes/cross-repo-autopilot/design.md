## Context

co-autopilot の全コンポーネント（plan.sh, init.sh, state-*.sh, worktree-create.sh, merge-gate-*.sh, parse-issue-ac.sh, autopilot-launch.md, SKILL.md）が単一 git コンテキスト前提で設計されている。具体的には:

- `gh issue view`/`gh pr merge` 等に `-R` フラグなし（カレントリポジトリ依存）
- `gh api "repos/{owner}/{repo}/..."` がカレントリポジトリを暗黙推論
- 状態ファイルが `.autopilot/issues/issue-{N}.json`（リポジトリ名前空間なし）
- plan.yaml の issues が bare integer（`42` のみ、`owner/repo#42` 未対応）
- Worker 起動が単一 `PROJECT_DIR` 前提（`.bare` 判定が固定パス）

Project Board は `linkProjectV2ToRepository` で複数リポジトリをリンク可能だが、autopilot 側が活用していない。

## Goals / Non-Goals

**Goals:**

- plan.yaml に repos セクションを追加し、クロスリポジトリプロジェクトを宣言可能にする
- Issue 識別を `{repo_id}#{N}` 形式に拡張（内部表現）
- 状態ファイルをリポジトリ別に名前空間化
- Worker が正しいリポジトリの bare repo main worktree で起動
- gh CLI コマンドに `-R owner/repo` を適切に付与
- repos セクション省略時の後方互換を維持

**Non-Goals:**

- 3 つ以上のリポジトリの同時管理（2 リポジトリで検証）
- リポジトリ間のコード依存解析
- 新しい Project Board フィールドの追加
- CI/CD パイプラインの統合

## Decisions

### D1: plan.yaml スキーマ拡張

```yaml
# v2: クロスリポジトリ対応
repos:
  lpd:                    # repo_id（短縮識別子）
    owner: shuu5
    name: loom-plugin-dev
    path: ~/projects/local-projects/loom-plugin-dev
  loom:
    owner: shuu5
    name: loom
    path: ~/projects/local-projects/loom

phases:
  - phase: 1
    issues:
      - { number: 42, repo: lpd }
      - { number: 50, repo: loom }

dependencies:
  "lpd#42":
    - "loom#50"
```

**後方互換**: repos セクション省略時、issues に bare integer を許可。その場合カレントリポジトリを暗黙の `_default` repo_id として扱う。

**理由**: repo_id を導入することで、plan.yaml 全体で一貫した短縮参照が可能。`owner/repo#N` を毎回書くのは冗長。

### D2: 状態ファイルの名前空間化

```
.autopilot/
  session.json              # repos フィールド追加
  repos/
    lpd/
      issues/
        issue-42.json
    loom/
      issues/
        issue-50.json
```

**後方互換**: repos/ ディレクトリ不在時は従来の `issues/issue-{N}.json` をフォールバック。

**理由**: 異なるリポジトリで同一 Issue 番号（例: lpd#10 と loom#10）が存在した場合の衝突を回避。

### D3: Worker 起動のリポジトリ解決

autopilot-launch が Worker を起動する際、Issue の repo_id から `repos[repo_id].path` を解決し:
1. bare repo 構造の場合: `{path}/main` で起動
2. standard repo の場合: `{path}` で起動

**理由**: 各リポジトリは独立した bare repo 構造を持つため、Worker はそのリポジトリの main worktree で Claude Code を起動する必要がある。

### D4: gh CLI の `-R` フラグ戦略

repo_id が `_default`（カレントリポジトリ）の場合は `-R` を付与しない（従来動作）。外部リポジトリの場合のみ `-R owner/repo` を付与。

**理由**: 後方互換を最小限の変更で実現。カレントリポジトリへの `-R` 付与は不要かつ冗長。

### D5: autopilot-plan.sh の Issue 解決

`--issues` 引数で以下の形式を受け付ける:
- `42` → `_default#42`（後方互換）
- `lpd#42` → repo_id で解決
- `shuu5/loom-plugin-dev#42` → repos セクションから repo_id を逆引き

**理由**: ユーザーは GitHub 標準の `owner/repo#N` 形式に慣れている。repo_id は plan.yaml 内部の短縮形。

### D6: session.json の拡張

```json
{
  "session_id": "...",
  "repos": {
    "lpd": { "owner": "shuu5", "name": "loom-plugin-dev", "path": "..." },
    "loom": { "owner": "shuu5", "name": "loom", "path": "..." }
  },
  "default_repo": "lpd"
}
```

**理由**: Worker が session.json から自身の担当リポジトリ情報を取得するために必要。

## Risks / Trade-offs

### R1: 複雑性の増加
repos セクション、名前空間化、repo_id 解決により全体の複雑性が増す。後方互換のフォールバックパスが多くなるためテストが重要。

### R2: bare repo パス解決の脆弱性
`repos[repo_id].path` はファイルシステム上のパスをハードコードする。ユーザーがリポジトリを移動すると壊れる。→ 初回起動時にパスの存在を検証し、不在時はエラーメッセージで案内。

### R3: Worker の git コンテキスト混乱
Worker が別リポジトリの main worktree で起動されるため、git status/diff 等がそのリポジトリのコンテキストで動作する。Pilot との通信（状態ファイル）は `.autopilot/` 経由なので、AUTOPILOT_DIR を Pilot 側のパスに固定する必要がある。

### R4: merge-gate のリポジトリ切り替え
merge-gate は Pilot セッション内で実行されるが、PR のマージ対象リポジトリが Issue ごとに異なる。`-R` フラグで解決可能だが、ローカルの git 操作（diff 確認等）には注意が必要。
