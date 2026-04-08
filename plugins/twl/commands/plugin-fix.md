---
type: atomic
tools: [Bash, Read, Write]
effort: low
maxTurns: 10
---
# fix: コンポーネント修正適用

## 目的
diagnose で発見された問題を修正する。

## Context Snapshot 入力（controller-improve 経由の場合）
snapshot_dir が指定されている場合、以下を Read して修正コンテキストを取得:
- `{snapshot_dir}/01-diagnose-results.md` — 診断結果
- `{snapshot_dir}/02-user-feedback.md` — ユーザーフィードバック
- `{snapshot_dir}/03-research-results.md` — 調査結果（存在時のみ）

## 手順

### 1. 修正対象の確認
diagnose の結果（または Context Snapshot）から修正すべき項目を特定。

### 2. 修正適用
問題の種類に応じて修正:

#### 構造的問題
- ファイル不足 → 生成
- セクション配置ミス → deps.yaml 修正
- 型ルール違反 → can_spawn/spawnable_by 修正

#### frontmatter 問題
- フィールド不足 → 追加
- 値の不整合 → 修正

#### 5原則違反
- 完結性不足 → プロンプトに目的・制約・報告方法を追加
- 明示性不足 → 冒頭に型宣言を追加
- 外部化不足 → external_context 設定を追加
- 並列安全性違反 → ファイル所有権の分離を設計
- コスト意識不足 → model / max_turns を追加

#### Controller 責務違反
- **Controller bloat** → インライン実装を atomic に抽出し、controller は呼び出し指示のみに
  1. 肥大化した Step の実装ロジックを新 atomic command に抽出
  2. controller の Step を「`commands/{name}.md` を Read し実行」に置換
  3. deps.yaml に新 atomic を追加、controller の calls に追記

- **Dead weight** → ドキュメント部分を reference に抽出 or 削除

#### Reference 配置違反
- **Reference misplacement** → calls を中間者（controller）から直接消費者（atomic）に移動
  1. deps.yaml: controller の calls から reference を削除
  2. deps.yaml: 実際に参照する atomic/specialist の calls に reference を追加
  3. reference の spawnable_by に必要な型を追加（例: `[controller, atomic]`）

#### ツール宣言違反
- **Tools mismatch** → frontmatter を body 実使用に合わせて更新
  1. body 内の `mcp__*` パターンを全て抽出
  2. frontmatter に不足ツールを追加
  3. 未使用の宣言を削除（汎用ツール Read/Write/Bash は残す）

#### パターン欠落（アーキテクチャ）
- Context Snapshot 未導入（4ステップ以上） → controller に snapshot_dir 初期化 + 各ステップに Read/Write 追加
- Session Isolation 未導入（per_phase） → snapshot_dir/team_name に session_id 付加 + session-info.json 管理追加
- Compaction Recovery 未導入（per_phase + 5ステップ以上） → team-state.json 管理 + worker Dual-Output + 復帰判定ロジック追加
  - worker の tools に Write 追加（deps.yaml）
  - worker の報告セクションを Dual-Output パターンに変更
  - phase コマンドに team-state.json 初期化/更新指示を追加

### 3. deps.yaml 更新
構造変更がある場合は deps.yaml を更新。

### 4. 変更内容の要約
修正したファイルと変更内容を一覧表示。

## Context Snapshot 出力（controller-improve 経由の場合）
snapshot_dir が指定されている場合、修正内容を `{snapshot_dir}/04-fix-manifest.md` に Write:
```markdown
# 修正マニフェスト
## 修正ファイル
- {file}: {変更内容}
## deps.yaml 変更
- {変更内容}（該当時のみ）
```

## 出力
- 修正ファイル一覧
- 変更差分の要約
- 次のステップ（verify）への案内
