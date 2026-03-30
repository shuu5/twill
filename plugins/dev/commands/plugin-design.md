# design: 型マッピング+deps.yaml設計

## 目的
interview で収集した要件を基に、6型マッピングと deps.yaml を設計する。

## 手順

### 1. 型マッピング表の作成
ref-types を参照し、ユーザー要件を6型にマッピング:

| ユーザー要件 | 型 | section | コンポーネント名 |
|-------------|-----|---------|----------------|
| (ワークフロー1) | team-controller | skills | controller-{purpose1} |
| (ワークフロー2) | team-controller | skills | controller-{purpose2} |
| (フェーズ遷移) | team-workflow | skills | workflow-{name} |
| ... | ... | ... | ... |

**エントリーポイント設計**: interview Q2 で列挙されたワークフローごとに独立した `controller-{purpose}` を作成。単一 `controller-entry` にルーティングテーブルを持たせない。

### 1.5. Controller 責務チェック（設計時予防）

型マッピングで controller/team-controller に分類された各コンポーネントについて:

1. **責務分離の確認**: controller の機能が「ルーティング + ユーザー対話 + サマリー表示」のみか
   - データ加工、バリデーション、フォーマット処理 → atomic に分離
   - ドキュメント的知識（ルール定義、フォーマット仕様） → reference に分離

2. **サイズ見積もり**: 各 controller の想定行数を概算し ~80行以内に収まるか確認
   - 収まらない場合: 実装ロジックを atomic に抽出する設計に変更

3. **Reference 配置計画**: reference を使うコンポーネントを特定し、calls を直接消費者に宣言
   - controller 経由のまとめ宣言ではなく、実際に参照する atomic/specialist に配置

4. **allowed-tools 計画**: 各コンポーネントが使用する MCP ツールを列挙し frontmatter に反映

### 2. パターン選択（自動推奨）
interview の Q9, Q10 回答を基に、以下の判断木で各ステップにパターンを割り当て:

1. 複数独立チェックが必要 → **AT** (team-phase, parallel: true)
2. Web取得・大量スキャン → **Subagent Delegation** (specialist + Task tool)
3. ステップ数 4+ → **Context Snapshot** (中間ファイル)
4. ユーザー対話・ファイル編集 → **Atomic** (直接実行)
5. 全ステップ共有の知識 → **Reference**
6. per_phase ライフサイクル → **Session Isolation** (session_id + snapshot_dir/team_name 分離)
7. per_phase + 5ステップ以上 or 長時間実行 → **Compaction Recovery** (team-state.json + Dual-Output)

ref-practices の「パターン選択ガイド」を参照し、パターン割当表を作成:

| ステップ | パターン | 理由 |
|---------|---------|------|
| (step1) | AT / Atomic / ... | (根拠) |
| ... | ... | ... |

→ パターン割当表をユーザーに提示して確認

### 3. deps.yaml の設計
ref-deps-format を参照し、以下を決定:
- team_config（lifecycle, max_size, default_model, external_context）
- entry_points: 各ワークフローを `controller-{purpose}` として列挙
- 各セクション（skills, commands, agents）のコンポーネント定義
- パターン選択に基づく型決定（team-controller / controller 混在可）

**entry_points 設計ガイダンス**:
- 各ワークフローに独立した `controller-{purpose}` を割り当て
- ATが必要なワークフロー → `team-controller` 型
- ATが不要なワークフロー → `controller` 型
- 各 controller の description にトリガーフレーズを含める

### 4. ユーザー確認
AskUserQuestion で以下を確認:
- 型マッピング表は正しいか
- パターン割当表は適切か
- deps.yaml の構造に問題はないか
- 追加・変更したいコンポーネントはあるか

## 出力
- 型マッピング表
- パターン割当表
- deps.yaml（完全版）
- ディレクトリ構造の概要
