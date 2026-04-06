## 1. .autopilot ディレクトリ構造と初期化

- [x] 1.1 `.gitignore` に `.autopilot/` を追加
- [x] 1.2 autopilot-init スクリプト作成: `.autopilot/` と `.autopilot/issues/` ディレクトリの初期化、session.json の存在チェック（排他制御）

## 2. state-read.sh 実装

- [x] 2.1 `scripts/state-read.sh` を作成: `--type issue|session`, `--issue N`, `--field <name>` の引数パース
- [x] 2.2 issue-{N}.json の読み取りロジック: 全フィールド出力（JSON）と単一フィールド出力の切り替え
- [x] 2.3 session.json の読み取りロジック
- [x] 2.4 存在しないファイルへのアクセス時に空文字列 + exit 0 を返す処理
- [x] 2.5 jq 存在チェック（未インストール時のエラーメッセージ）

## 3. state-write.sh 実装

- [x] 3.1 `scripts/state-write.sh` を作成: `--type issue|session`, `--issue N`, `--set key=value`, `--role pilot|worker`, `--init` の引数パース
- [x] 3.2 issue-{N}.json の新規作成（`--init`）: status=running のデフォルト値設定
- [x] 3.3 状態遷移バリデーション: 許可遷移テーブル（running→merge-ready, running→failed, merge-ready→done, merge-ready→failed, failed→running）の実装
- [x] 3.4 retry_count 検証: failed→running 遷移時の retry_count < 1 チェック
- [x] 3.5 done 終端状態の保護: done からの任意遷移を拒否
- [x] 3.6 Pilot/Worker ロールベースアクセス制御: Worker は issue-{N}.json のみ書き込み可、Pilot は session.json と issue status/merged_at のみ書き込み可

## 4. session.json 管理

- [x] 4.1 session.json の新規作成ロジック: session_id 生成、plan_path, current_phase, phase_count の設定
- [x] 4.2 stale セッション検出: started_at が 24 時間以上経過時の警告
- [x] 4.3 cross-issue 警告の追記: session.json の cross_issue_warnings 配列への追加
- [x] 4.4 セッション完了時のアーカイブ: `.autopilot/archive/<session_id>/` への移動

## 5. worktree ライフサイクル安全ルール

- [x] 5.1 worktree-delete.sh にCWDガードを追加: CWD が worktrees/ 配下の場合は exit 1
- [x] 5.2 crash 検知ロジック: tmux ペイン存在チェック + status=running 時の failed 遷移

## 6. deps.yaml 更新とプラグイン統合

- [x] 6.1 deps.yaml に state-read, state-write を script 型コンポーネントとして追加
- [x] 6.2 `loom check` で構造検証パス
- [x] 6.3 `loom update-readme` で README 更新

## 7. 不変条件テスト仕様の明文化

- [x] 7.1 不変条件 A~I のテスト仕様を test-mapping.yaml に定義（テスト実装は C-5）
