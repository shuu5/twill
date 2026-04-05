# migrate-analyze: 既存プラグインのAT移行分析

## 目的
既存の guide-patterns 準拠プラグインを分析し、AT移行の型マッピングを自動生成する。

## 入力
- 既存プラグインのパス（例: `~/ubuntu-note-system/claude/plugins/dev`）

## 手順

### 1. 既存 deps.yaml の読み込み
```bash
Read: {plugin-path}/deps.yaml
```

### 2. 自動型マッピング
ref-types の変換表を参照して自動マッピング:

| 既存型 | 新型 | 変換ルール |
|--------|------|-----------|
| controller | team-controller | TeamCreate/Delete 追加 |
| workflow | team-workflow | フェーズ遷移+チーム管理追加 |
| composite | team-phase | Task tool→チームメイトspawn |
| orchestrator | team-controller | 吸収（機能を統合） |
| specialist | team-worker | Task tool禁止、SendMessage追加 |
| atomic | atomic | 変更なし |
| reference | reference | 変更なし |

### 3. 移行分析レポート
以下を出力:
- コンポーネント数の変化
- 型変換のマッピング表
- 注意点・手動対応が必要な箇所
  - orchestrator の機能を team-controller に統合する方法
  - composite の specialist 呼び出しを team-phase の worker 起動に変換
  - specialist のツール制約を team-worker の tools に変換

### 4. ユーザー確認
マッピング結果を提示し、調整を受け付ける。

## 出力
移行分析レポート:
- 型マッピング表
- team_config の推奨値
- 手動対応必要箇所のリスト
