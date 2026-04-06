## Context

`workflow-test-ready/SKILL.md` は、OpenSpec テスト生成と準備確認を行うワークフロー。quick Issue（実装が自明で OpenSpec 不要な Issue）では呼ばれるべきでないが、LLM の不確定性によって誤って起動されることがある。

`chain-runner.sh` はすでに `detect_quick_label()` と `is_quick` の state 永続化機能を持ち、`next-step` コマンドは `QUICK_SKIP_STEPS` によりテスト関連ステップをスキップする。本変更は defense in depth として、`workflow-test-ready` 自身に quick 判定ガードを追加する。

## Goals / Non-Goals

**Goals:**
- `chain-runner.sh quick-guard` コマンドを追加（state 優先 → gh API fallback で quick 判定）
- `workflow-test-ready/SKILL.md` の冒頭に quick ガードセクションを追加
- `deps.yaml` に chain-runner.sh の新コマンド依存を反映

**Non-Goals:**
- `chain-runner.sh next-step` の修正（別 Issue #145 で対応）
- autopilot orchestrator の修正
- 既存の quick ラベル検出ロジックの変更

## Decisions

### 1. quick-guard コマンドの実装場所: chain-runner.sh

既存の `detect_quick_label()` が chain-runner.sh に実装済みであり、同ファイルに追加するのが自然。新規スクリプトは作成しない。

### 2. 判定優先順位: state → gh API fallback

- `state-read.sh --field is_quick` が "true"/"false" を返す場合はそれを使用
- state が未設定（空文字 or エラー）の場合のみ `detect_quick_label()` で gh API を呼出
- init ステップ実行済みなら state が存在するため、通常は gh API は呼ばれない

### 3. SKILL.md の quick ガード位置: Step 1 の前

すべてのステップをスキップするため、change-id 解決（Step 1）より前に配置。`chain-runner.sh quick-guard` を実行し、exit 1 なら終了メッセージを出力してスキップ。exit 0 なら通常フロー継続。

### 4. deps.yaml の更新: chain-runner.sh エントリに quick-guard を追記

deps.yaml の chain-runner.sh コンポーネントの `commands` フィールドに `quick-guard` を追加。

## Risks / Trade-offs

- **ブランチから Issue 番号抽出できない場合**: quick-guard は false を返してスキップ（保守的な設計 — 誤って全スキップするリスクより、誤って通常フロー継続するリスクのほうが許容できる）
- **gh API 呼出のレート制限**: state が存在する通常ケースでは gh API は呼ばれないため影響なし
- **非 quick Issue への影響**: quick-guard が exit 0 を返すため通常フローに影響なし
