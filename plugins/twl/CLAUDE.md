# plugin-twl

Claude Code twl plugin（chain-driven + autopilot-first）。TWiLL モノリポ `plugins/twl/` として管理。

## 構成

- モノリポ: `~/projects/local-projects/twill/main/plugins/twl/`

## 設計哲学

**LLM は判断のために使う。機械的にできることは機械に任せる。**

## プラグイン構成

### プラグイン構成の SSoT

deps.yaml v3.0 がプラグイン構成（コンポーネント定義）の唯一の情報源。

**chain SSoT 境界 (ADR-022)**:
- chain.py `CHAIN_STEPS` = chain-runner.sh dispatch 対象 step (runner step) の SSoT
- chain-steps.sh = chain.py の bash mirror (`twl chain export` computed artifact)
- deps.yaml.chains = workflow skill 内 orchestrate step を含む拡張 metadata (独立 SSoT)

### Controller は7つ

| controller | 役割 |
|---|---|
| co-autopilot | Issue 実装の実行（単一 Issue も autopilot 経由） |
| co-issue | Issue 作成（explore-summary → Issue 変換） |
| co-explore | 問題探索（explore-summary 出力 + Issue リンク） |
| co-project | プロジェクト管理（create / migrate / snapshot） |
| co-architect | アーキテクチャ設計 |
| co-utility | スタンドアロンユーティリティ操作 |
| co-self-improve | ライブセッション観察と能動的 self-improvement（out-of-process observation） |

### Supervisor は1つ

| supervisor | 役割 |
|---|---|
| su-observer | プロジェクト常駐のメタ認知・Wave 管理・知識外部化（ADR-014） |

## Bare repo 構造検証（セッション開始時チェック）

以下の4条件を全て満たすこと:

1. `.bare/` が存在する（`.git/` ディレクトリではない）
2. `main/.git` がファイル（ディレクトリではない）で `.bare` を指す
3. CWD が `main/` 配下である（Pilot セッション）、または Pilot が作成した worktree 配下である（Worker セッション）
4. `.bare/config` および全 worktree の `remote.origin.fetch` が `+refs/heads/*:refs/remotes/origin/*` を含む（欠落時は `worktree-health-check.sh --fix` で修復。欠落すると `git fetch origin` が `origin/main` を更新せず mergeability 判定が壊れる）

### セッション起動ルール

**Pilot（制御側）:**
- 必ず `main/` で起動する
- `worktrees/` 配下で直接起動してはならない（worktree 削除で bash CWD 消失のリスク）

**Worker（実装側）:**
- Pilot が事前作成した worktree ディレクトリで起動される（autopilot: ADR-008 準拠、co-issue v2: workflow-issue-lifecycle）
- Worker は worktree 内で作業し、完了後に merge-ready を宣言する
- Worker が自ら worktree を作成・削除してはならない（[不変条件 B](refs/ref-invariants.md#不変条件-b-worktree-ライフサイクル-pilot-専任)）

## 編集フロー（必須）

```
コンポーネント編集 → deps.yaml 更新 → twl check → twl update-readme
chain 定義変更  → chain.py 編集   → twl check --deps-integrity → chain-steps.sh 同期確認
```

commit 前に `twl check --deps-integrity` を実行し、chain.py CHAIN_STEPS と deps.yaml.chains・chain-steps.sh の整合性を確認する（MUST）。

### Pre-commit hook セットアップ (optional)

deps-integrity drift をローカル commit 時点で検知するため、以下 1 回実行で pre-commit hook を設置できる:

```bash
bash plugins/twl/scripts/install-git-hooks.sh
```

hook は `chain.py` / `chain-steps.sh` / `deps.yaml` のいずれかが staged のとき `twl check --deps-integrity` を実行し、errors 検出時に commit を abort する。`git commit --no-verify` で bypass 可能（user 裁量）。

## specialist-audit JSON 出力契約

`specialist-audit.sh` はデフォルトで JSON を stdout に出力し、`su-observer/SKILL.md` の Wave 完了ステップは `grep -q '"status":"FAIL"'` でこの出力を判定する。`--summary` フラグは非推奨（`2bd9130` で SKILL.md から除去済み）。将来 `--summary` 形式に戻した場合、この grep 契約が破綻するため、変更時は `plugins/twl/tests/bats/scripts/su-observer-specialist-audit-grep.bats` の全 PASS を確認すること。

## Project Board

- Project: `twill-ecosystem`、Owner: `shuu5`（番号・URL は `project-links.yaml` 参照 → `twl config get project-board.number`）
- リンク済みリポ: twill

## 視覚化

`twl` CLI 必須（独自スクリプト禁止）。

## 主要不変条件（Invariants）リファレンス

不変条件の正典: [refs/ref-invariants.md](refs/ref-invariants.md)

- **不変条件 B**: Worktree ライフサイクル Pilot 専任（worktree 作成・削除は Pilot のみ）
- **Invariant N** (lesson 19): Lesson Structuralization — lesson 保存後は 4-step chain（doobidoo保存→Issue起票→Wave実装→永続文書化）を完遂すること（[ADR-036](architecture/decisions/ADR-036-lesson-structuralization.md)）
