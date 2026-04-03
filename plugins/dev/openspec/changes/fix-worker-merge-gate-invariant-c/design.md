## Context

autopilot セッションで Worker が `commands/merge-gate.md` を Read すると、PASS セクション（L94-100）に記載された raw bash コマンド（`gh pr merge --squash` / `state-write --role pilot`）を Worker LLM が直接 Bash tool で実行するパスが存在する。これにより auto-merge.sh と merge-gate-execute.sh の4層防御（CWD/tmux/state-read/fallback）が完全にバイパスされ、不変条件 C（Worker マージ禁止）が破られる。

現行の問題点:
- `commands/merge-gate.md` L94-100: raw コマンドが記載されており、Worker が直接実行可能
- `scripts/state-write.sh` L94-107: `--role` は引数渡しのみで、呼び出し元 identity の検証なし
- `scripts/auto-merge.sh` L95-96: Layer 1 が `status == "running"` のみ判定（`merge-ready` 未対応）
- `scripts/merge-gate-execute.sh`: autopilot 判定なし（Pilot でも Worker でも実行可能）

## Goals / Non-Goals

**Goals:**
- merge-gate.md PASS セクションから raw コマンドを除去し、merge-ready 宣言 + スクリプト呼び出し案内に変更
- state-write.sh に `--role pilot` 呼び出し時の identity 検証を追加（tmux/CWD 多層）
- auto-merge.sh Layer 1 が `merge-ready` 状態でも autopilot を正しく検出する
- merge-gate-execute.sh に autopilot 判定（state-read ベース）を追加

**Non-Goals:**
- worktree-delete.sh と merge-gate-execute.sh のインライン実装統一
- merge-gate.md 全体のリファクタリング
- 完全な cryptographic identity 検証（bash スクリプトの制約上、tmux/CWD は改ざん可能）

## Decisions

### 1. merge-gate.md の PASS セクション書き換え

**決定**: raw `gh pr merge` / `state-write --role pilot` を除去し、Worker フローとして「merge-ready 宣言して停止 → Pilot が merge-gate-execute.sh を実行」に統一。

**根拠**: LLM は文書内に記載された実行可能なコマンドを忠実に実行しようとする。コマンド記載を排除することで、実行パスを機械的に制御する（LLM の「注意」には依存しない）。

PASS 時 Worker フロー（autopilot 時）:
```bash
bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set status=merge-ready
echo "merge-gate: PASS。merge-ready 宣言済み。Pilot による merge を待機中。"
```

Pilot 実行（非 autopilot 時）:
```bash
ISSUE="${ISSUE_NUM}" PR_NUMBER="${PR_NUMBER}" BRANCH="${BRANCH}" bash scripts/merge-gate-execute.sh
```

### 2. state-write.sh identity 検証（defense-in-depth）

**決定**: `--role pilot` かつ `--type issue` かつ status フィールド更新時に、呼び出し元が Worker でないことを多層検証する。いずれか1つで Worker を検出したら拒否。

検証層:
1. **tmux window 名**: `$CURRENT_WINDOW =~ ^ap-#[0-9]+$` → Worker 拒否
2. **CWD**: `$PWD =~ /worktrees/` → Worker 拒否

**根拠**: 2層の独立した検証により、単一チェックの回避を困難にする（defense-in-depth）。完全な identity 保証ではないが、不変条件 C 違反を機械的に防ぐ補助層として有効。

### 3. auto-merge.sh Layer 1 の拡張

**決定**: `AUTOPILOT_STATUS == "running"` の判定に `|| [[ "$AUTOPILOT_STATUS" == "merge-ready" ]]` を追加。

**根拠**: merge-gate.md の PASS セクション書き換えにより、Worker が merge-ready を宣言した後に auto-merge.sh が呼ばれるパスが生じた場合の安全弁。merge-ready 状態でも autopilot を検出し、直接 merge を拒否する。

### 4. merge-gate-execute.sh autopilot 判定

**決定**: 既存の CWD/tmux ガードの後に、state-read ベースの autopilot 検出を追加。`merge-ready` 状態の場合は autopilot 配下と判定し、merge-gate-execute.sh から直接 merge を許可（Pilot セッションからの呼び出しのため）。

**根拠**: Pilot セッション（main/ CWD、非 `ap-#N` window）から merge-gate-execute.sh を呼び出す場合は CWD/tmux ガードを通過する。autopilot 判定は「ISSUE が autopilot 管理下か」の確認（追加の安全チェック）。

## Risks / Trade-offs

- **tmux/CWD 改ざん**: Worker が `cd main/` や tmux window 名変更でチェックを回避できる。ただし identity 検証はあくまで defense-in-depth の補助層であり、主防御はコマンド記載の排除（Decision 1）。
- **merge-gate.md の autopilot 判定ロジック**: Worker 側で IS_AUTOPILOT 判定が必要。state-read スクリプト呼び出しをコマンドに追加する（raw コマンドは含めない）。
- **後方互換**: merge-gate.md の PASS セクション変更により、非 autopilot 時の Pilot フローが明示化される。従来は Worker が直接 merge していたが、今後は Pilot が merge-gate-execute.sh を呼ぶフローに統一。
