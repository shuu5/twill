# スイッチオーバーガイド

claude-plugin-dev から plugin-dev への切替手順。

## 前提条件

- C-1〜C-5 の全 Issue が完了・マージ済み
- twl validate / twl check / twl audit が全 pass
- 全 autopilot セッションが完了（in-flight セッション中の切替は禁止）

## Phase 1: 並行検証

### Step 1: --plugin-dir による非破壊テスト

symlink を変更せずに新プラグインをテストする:

```bash
claude --plugin-dir ~/projects/local-projects/plugin-dev/main
```

### Step 2: 動作比較

旧プラグインと同一 Issue で動作を比較する:

1. 旧プラグイン（現在の symlink）で Issue を処理
2. `--plugin-dir` で同じ Issue を新プラグインで処理
3. 結果を比較（出力品質、エラー有無、ワークフロー完遂）

### Step 3: twl 検証ツール実行

```bash
cd ~/projects/local-projects/plugin-dev/main
twl validate    # deps.yaml 構文・型検証
twl check       # 構造整合性チェック
twl audit       # 全体監査
```

全て pass であることを確認。

### Step 4: 事前チェック（自動）

```bash
bash scripts/switchover.sh check
```

twl validate/check、autopilot セッション未稼働、symlink 状態を自動確認。

## Phase 2: symlink 切替

### Step 5: 切替実行

```bash
bash scripts/switchover.sh switch --new ~/projects/local-projects/plugin-dev/main
```

自動で以下を実行:
1. `switchover.sh check` による事前チェック
2. 旧 symlink を `~/.claude/plugins/dev.bak` にバックアップ
3. 新 symlink `~/.claude/plugins/dev → plugin-dev/main` を作成

## Phase 3: 試運転

実際の開発作業で新プラグインを使用。問題発生時は即座にロールバック。

## ロールバック手順

問題発生時の即時復帰（目標: 5分以内）:

```bash
bash scripts/switchover.sh rollback
```

1. 全 Claude Code セッションを終了
2. `switchover.sh rollback` で旧 symlink を復元
3. セッション再開

## Phase 4: 退役

試運転期間（1-2週間目安）で問題なければ:

```bash
bash scripts/switchover.sh retire
```

バックアップ削除と claude-plugin-dev リポジトリのアーカイブ案内を表示。

## 注意事項

- 切替は全 Claude Code セッション終了後に行うこと
- autopilot セッション稼働中の切替は `switchover.sh check` が自動検出・拒否する
- ロールバック後は新プラグインの状態ファイルが残る場合があるため、手動 cleanup を推奨
