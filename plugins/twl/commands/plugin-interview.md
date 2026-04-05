# interview: ユーザー要件インタビュー

## 目的
ATプラグインの設計に必要な情報をユーザーから収集する。

## 質問一覧

AskUserQuestion を使って以下の11問を段階的に質問する。
1問ずつ、前の回答を踏まえて次の質問を調整する。

### Q1. 名前+目的
「作成するプラグインの名前と主な目的を教えてください」
- プラグイン名 → `t-{name}` 形式に変換
- 目的 → description に反映

### Q2. ワークフロー分割
「このプラグインが提供する独立したワークフロー・ユースケースを列挙してください（例: 作成/改善/移行）」
- 各ワークフロー → `controller-{purpose}` として独立エントリーポイント化
- 単一ワークフローの場合も具体名を使用（例: `controller-search`）
- 各ワークフローについてAT（Agent Teams並列処理）が必要か確認

### Q3. 並列タスク
「並列に実行したいタスクはありますか？どのようなタスクを同時に走らせたいですか？」
- 並列タスク → team-phase + team-worker の設計に反映

### Q4. フェーズ構成
「ワークフロー全体をどのようなフェーズに分けますか？（例: 調査→設計→実装→検証）」
- フェーズ数 → team-workflow / team-phase の設計に反映

### Q5. 情報引継ぎ
「フェーズ間でどのような情報を引き継ぐ必要がありますか？手段は？」
- 選択肢: GitHub Issue, GitHub PR, ファイル, Memory
- → team_config.external_context に反映

### Q6. lifecycle
「チームのライフサイクルはどちらが適切ですか？」
- persistent: 小規模、フェーズ間でworkerが生存
- per_phase: 大規模、フェーズごとに再作成（推奨）
- → team_config.lifecycle に反映

### Q7. ツール要件
「workerが使用する主なツールは何ですか？」
- Read, Write, Edit, Bash, Grep, Glob, WebFetch, WebSearch など
- → team-worker の tools に反映

### Q8. チェックポイント
「workerの中間報告（チェックポイント）は必要ですか？」
- あり → checkpoint reference を作成
- なし → checkpoint: false

### Q9. チームサイズ
「1フェーズで同時に動くworkerの最大数は？」
- → team_config.max_size に反映

### Q10. ステップチェーン保護
「ワークフローのステップ数が多い（4+）場合、
ステップ間の中間結果をファイルに保存する
Context Snapshot を導入しますか？」
- 選択肢:
  - 自動推奨（4ステップ以上で導入）(Recommended)
  - 手動選択（各ステップごとに判断）
  - 不要（会話コンテキストで十分）
- → 生成するプラグインに Context Snapshot インフラを組み込むか判断
- → ref-practices パターン4 参照

### Q11. サブエージェント委任
「Web取得・大量データ処理など、コンテキストを圧迫する
ステップはありますか？それらをサブエージェントに
委任しますか？」
- 選択肢:
  - あり（specialist agent を生成）
  - なし
- → 「あり」の場合、どのステップで何を委任するか詳細を確認
- → 生成するプラグインに Subagent Delegation パターンを組み込むか判断
- → ref-practices パターン5 参照

## 出力
収集した要件を構造化して表示し、次のステップ（design）に渡す。
