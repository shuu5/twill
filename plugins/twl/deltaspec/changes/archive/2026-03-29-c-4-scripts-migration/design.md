## Context

旧 dev plugin（`~/.claude/plugins/dev/scripts/`）の 18 scripts のうち、B-3 で新リポジトリに作成済みの 10 scripts を除く残り 16 scripts（旧 18 本中 worktree-delete.sh は移植済み、autopilot-init-session.sh は autopilot-init.sh に置換済み）を移植する。

新リポジトリでは B-3 で統一状態管理（state-read.sh / state-write.sh）が導入済みであり、旧マーカーファイル（`.done`, `.fail`, `.merge-ready`, `.retry-count`）操作と `MARKER_DIR` 環境変数、`DEV_AUTOPILOT_SESSION` 環境変数への依存を排除する必要がある。

### 既存 scripts（新リポジトリ、移植不要）

| Script | 由来 |
|---|---|
| state-read.sh | B-3 新規 |
| state-write.sh | B-3 新規 |
| autopilot-init.sh | B-3 新規（旧 autopilot-init-session.sh 置換） |
| session-create.sh | B-3 新規 |
| session-archive.sh | B-3 新規 |
| session-add-warning.sh | B-3 新規 |
| worktree-delete.sh | 移植済み |
| crash-detect.sh | B-3 新規 |
| tech-stack-detect.sh | B-5 新規 |
| specialist-output-parse.sh | B-5 新規 |

### 移植対象（16 scripts）

| Script | 変更度 | 主要変更点 |
|---|---|---|
| autopilot-plan.sh | 高 | plan.yaml 生成先を `.autopilot/` 配下に変更 |
| autopilot-should-skip.sh | 中 | マーカーファイル → state-read.sh |
| merge-gate-init.sh | 高 | MARKER_DIR → state-read.sh、GATE_TYPE 判定 |
| merge-gate-execute.sh | 高 | マーカー遷移 → state-write.sh |
| merge-gate-issues.sh | 低 | tech-debt Issue 起票（変更最小限） |
| branch-create.sh | 低 | パス参照のみ変更 |
| worktree-create.sh | 低 | パス参照のみ変更 |
| classify-failure.sh | 低 | 変更最小限 |
| parse-issue-ac.sh | 低 | 変更最小限 |
| session-audit.sh | 中 | DEV_AUTOPILOT_SESSION → session.json |
| project-create.sh | 低 | パス参照のみ変更 |
| project-migrate.sh | 低 | パス参照のみ変更 |
| check-db-migration.py | 低 | 変更なし（Python、外部依存なし） |
| ecc-monitor.sh | 低 | 変更最小限 |
| codex-review.sh | 低 | 変更最小限 |
| create-harness-issue.sh | 低 | 変更最小限 |

## Goals / Non-Goals

**Goals:**

- 16 scripts を `scripts/` に移植し、新アーキテクチャに適応させる
- マーカーファイル操作を `state-write.sh` / `state-read.sh` 呼び出しに置換
- `DEV_AUTOPILOT_SESSION` 環境変数参照を排除
- `MARKER_DIR` 環境変数参照を排除（`.autopilot/` 直接参照に統一）
- deps.yaml に全 script エントリを追加
- 既存 COMMAND.md のスクリプトパス参照を更新

**Non-Goals:**

- scripts のロジック大幅リファクタリング（動作を維持する移植が目的）
- テストの追加（C-5 テスト基盤スコープ）
- loom#31（script 型サポート）への対応（deps.yaml 登録は現在の型で可能な範囲）
- branch-create / worktree-create の共通化（重複コードがあるが移植スコープ外）

## Decisions

### D1: マーカーファイル → state-read/write 置換パターン

旧パターン:
```bash
# 読み取り
if [ -f "$MARKER_DIR/${ISSUE}.merge-ready" ]; then ...
# 書き込み
jq -n '{...}' > "$MARKER_DIR/${ISSUE}.fail"
rm -f "$MARKER_DIR/${ISSUE}.merge-ready"
```

新パターン:
```bash
# 読み取り
STATUS=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE" --field status)
if [ "$STATUS" = "merge-ready" ]; then ...
# 書き込み（遷移バリデーション付き）
bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE" --role pilot --set status=failed --set reason="$REASON"
```

**理由**: state-write.sh が遷移バリデーションを内蔵しており、不正な状態遷移を防止できる。

### D2: SCRIPT_DIR 基準のパス解決

各スクリプトの冒頭で `SCRIPT_DIR` を解決し、同ディレクトリの state-read/write を呼び出す:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

**理由**: 旧プラグインの `$HOME/.claude/plugins/dev/scripts/` 固定パスを排除し、リポジトリ内の相対パスで完結させる。

### D3: autopilot-plan.sh の plan.yaml 出力先

plan.yaml を `.autopilot/` 配下に出力するように変更。`--project-dir` 引数は維持するが、plan.yaml のパスは `$PROJECT_DIR/.autopilot/plan.yaml` に固定。

**理由**: `.autopilot/` がセッション状態の一元管理ディレクトリとして B-3 で確立済み。

### D4: merge-gate-init.sh の状態ファイル読み取り

`.merge-ready` マーカーファイルの代わりに `state-read.sh` で `status=merge-ready` の issue-{N}.json を読み、PR 番号・ブランチ名を取得する。

**理由**: B-3 で issue-{N}.json に PR 情報が保存される設計。

### D5: merge-gate-execute.sh の状態遷移

マーカーファイルの作成/削除の代わりに `state-write.sh` で状態遷移を実行:
- approve: `--set status=done --set merged_at=...`
- reject: `--set status=failed --set reason=merge_gate_rejected`
- reject-final: `--set status=failed --set reason=merge_gate_rejected_final`

**理由**: state-write.sh の遷移バリデーションを活用。

### D6: autopilot-should-skip.sh の依存状態確認

マーカーファイルの代わりに state-read.sh で各依存先 Issue の status を確認:
- `failed` → skip
- `skipped` → skip
- `done` → 依存解決済み

**理由**: 統一状態ファイルへの一元化。

## Risks / Trade-offs

- **state-read/write の性能**: 毎回 jq + ファイル I/O が発生するが、autopilot の Issue 数は高々数十件であり問題なし
- **旧プラグインとの並行期間**: 移植後は旧プラグインの scripts を参照する COMMAND.md が残る可能性。COMMAND.md のパス更新も本スコープに含める
- **loom#31 未完了**: deps.yaml v3.0 の script 型がまだ loom CLI で未サポートの可能性。登録は行うが validate エラーは許容する
