## 1. scripts/autopilot-launch.sh 新設

- [x] 1.1 `scripts/autopilot-launch.sh` のスケルトン作成（shebang, set -euo pipefail, usage 関数）
- [x] 1.2 フラグ引数パーサー実装（--issue, --project-dir, --autopilot-dir, --context, --repo-owner, --repo-name, --repo-path）
- [x] 1.3 SCRIPTS_ROOT 自動解決（`$(cd "$(dirname "$0")" && pwd)`）
- [x] 1.4 入力バリデーション実装（ISSUE 数値チェック、パストラバーサル防止、絶対パス検証、repo-owner/repo-name 形式チェック）
- [x] 1.5 cld パス解決 + 不在時の state-write failed 記録
- [x] 1.6 state-write.sh --init による issue state 初期化（クロスリポジトリ --repo 対応含む）
- [x] 1.7 LAUNCH_DIR 計算（bare repo 検出: `.bare/` → `$PROJECT_DIR/main`）
- [x] 1.8 AUTOPILOT_DIR / REPO_ENV 環境変数構築
- [x] 1.9 tmux new-window + cld 起動コマンド構築（printf %q クォーティング、--context → --append-system-prompt 変換）
- [x] 1.10 クラッシュ検知フック設定（remain-on-exit on + pane-died → crash-detect.sh）
- [x] 1.11 終了コード体系実装（0=成功, 1=バリデーション, 2=外部コマンド不在）

## 2. commands/autopilot-launch.md 簡素化

- [x] 2.1 Step 0.5〜3, 4.5, 5, 6 を削除し `bash $SCRIPTS_ROOT/autopilot-launch.sh` 呼び出しに置換
- [x] 2.2 Step 4（コンテキスト注入テキスト構築）を維持、結果を --context フラグで渡す形に修正
- [x] 2.3 前提変数セクションの更新（不要な変数の削除、フラグマッピングの説明追加）

## 3. deps.yaml 更新と検証

- [x] 3.1 deps.yaml の autopilot-launch エントリに `script: autopilot-launch` を追加
- [x] 3.2 `loom check` が PASS することを確認
- [x] 3.3 `loom validate` が PASS することを確認
