---
type: atomic
tools: [AskUserQuestion, Bash, Read, Skill, Task]
effort: low
maxTurns: 10
---
# DeltaSpec 実装（change-apply）

DeltaSpec change の tasks.md に沿ってタスクを実装する。完了後に PR サイクルへの誘導を出力する。

## 引数

- `change-id`: DeltaSpec change ID（省略時は自動検出）

## フロー制御（MUST）

### Step 1: change-id 解決

名前が指定されていれば使用する。そうでなければ:
- 会話のコンテキストでユーザーが change に言及していれば推定する
- アクティブな change が 1 つだけなら自動選択する
- 曖昧な場合、`twl spec list` で利用可能な change を取得し **AskUserQuestion tool** で選択させる

必ず通知: 「change: <name> を使用します」。

### Step 2: ステータス確認
```bash
twl spec status --change "<name>" --json
```
JSON をパースして以下を把握:
- `schemaName`: 使用中のワークフロー（例: "spec-driven"）
- タスクを含む artifact（spec-driven の場合は通常 "tasks"）

### Step 3: apply 指示取得

```bash
twl spec instructions apply --change "<name>" --json
```

以下が返される:
- コンテキストファイルのパス（スキーマにより異なる）
- 進捗（合計、完了、残り）
- ステータス付きタスクリスト
- 現在の状態に基づく動的指示

**状態ごとの処理:**
- `state: "blocked"`（artifact 不足）: メッセージを表示し、先に artifact 作成を提案
- `state: "all_done"`: 完了を伝え、アーカイブを提案
- それ以外: 実装に進む

### Step 4: コンテキストファイル読み込み

apply 指示出力の `contextFiles` に記載されたファイルを読み込む。
ファイルは使用中のスキーマにより異なる:
- **spec-driven**: proposal, specs, design, tasks
- その他のスキーマ: CLI 出力の contextFiles に従う

### Step 5: タスク実装（完了またはブロックまでループ）

各 pending タスクについて:
- 作業中のタスクを表示する
- 必要なコード変更を行う
- 変更は最小限かつ焦点を絞る
- タスクファイルで完了をマーク: `- [ ]` → `- [x]`
- 次のタスクに進む

**一時停止する場合:**
- タスクが不明確 → 明確化を質問する
- 実装中に設計上の問題が発覚 → artifact の更新を提案する
- エラーまたはブロッカーが発生 → 報告してガイダンスを待つ
- ユーザーが中断した場合

### Step 6: チェックポイント出力（MUST）

全タスク完了後、以下を表示して停止:

```
>>> 実装完了: <change-id>

次のステップ:
  /twl:workflow-pr-verify --spec <change-id> で PR サイクル開始
```

完了または一時停止時にステータスを表示:
- このセッションで完了したタスク
- 全体の進捗: 「N/M タスク完了」
- 全完了の場合: アーカイブを提案
- 一時停止の場合: 理由を説明してガイダンスを待つ

## 禁止事項（MUST NOT）

- tasks.md にないタスクを勝手に追加してはならない
- コード変更は各タスクにスコープを絞り最小限にする
- 各タスク完了後すぐにチェックボックスを更新する
- エラー、ブロッカー、不明確な要件では一時停止する — 推測しない
- CLI 出力の contextFiles を使用し、特定のファイル名を仮定しない

## Fluid Workflow 統合

このコマンドは「change に対するアクション」モデルをサポートする:

- **いつでも呼び出し可能**: 全 artifact 完了前（タスクが存在すれば）、部分実装後、他のアクションとインターリーブで
- **artifact 更新を許容**: 実装中に設計上の問題が発覚したら artifact の更新を提案する — フェーズに固定されず、流動的に作業する
