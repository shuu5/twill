# explore-summary: su-observer モード分離廃止 — セッションマネージャーへの再設計

## 問題の要約

su-observer SKILL.md と設計ドキュメントが「モード分離」パターンを採用しており、LLM が文脈から自然に判断すべき行動を、明示的なモード判定テーブルで強制ルーティングしている。su-observer は本来「ユーザーと controller の間に入るセッションマネージャー」であるべき。

## 探索結果

### 1. 現行 SKILL.md の問題（plugins/twl/skills/su-observer/SKILL.md）

Step 0 に「モード判定」テーブルが存在:

| モード | 判定条件 |
|---|---|
| supervise | supervise / 監視 / watch / autopilot 起動 |
| delegate-test | test / テスト / scenario |
| retrospect | retrospect / 振り返り / 集約 |

- Steps 1-3 がモード専用の処理（supervise, delegate-test, retrospect）
- Steps 4-7 が追加機能（Wave管理, Long-term Memory, Compaction, セッション終了）
- 「引数なし or 曖昧な場合は AskUserQuestion で 3 モードから選択させる」— これが最も問題。LLM が判断すべき

### 2. 設計ドキュメントの問題（architecture/designs/su-observer-skill-design.md）

Step 1 に 6 モードのルーティングテーブル:
- autopilot, issue, architect, observe, compact, delegate
- 各モードが Steps 2-7 に対応

SKILL.md は設計ドキュメントを「正典」として参照しているが、設計ドキュメント自体がモード分離前提。

### 3. supervision.md（architecture/domain/contexts/supervision.md）の状態

mermaid ワークフロー図は実は **ほぼ正しい**:
```
ユーザー指示待ち → autopilot指示 / issue指示 / architect指示 / compact指示 / observe指示
```
「モード」という単語は使っていない。分岐の表現として自然。supervision.md の修正は軽微。

### 4. 既存 Issue #440 との関係

#440「su-observer SKILL.md 常駐 observer パターン全面書き換え」（state: OPEN, refined ラベル付き）:
- **正しく指摘していること**: 常駐ループ構造の導入、session:spawn 統一
- **問題が残っていること**: 
  - 「Step 1: 指示待ちループ — ユーザー入力解析 → モード振り分け → 処理後 Step 1 に戻る永続ループ」— "モード振り分け" が残存
  - 「含まない: su-observer-skill-design.md の変更（正典として使用）」— 正典自体がモード前提なので、正典も修正が必要
- **推奨**: #440 を更新してモード廃止 + 設計ドキュメント修正を含める（同じ SKILL.md の rewrite なので分離すると conflict）

### 5. ユーザーが求めるあるべき姿

su-observer は「セッションマネージャー」:
- モードテーブルなし
- ユーザーの指示を LLM が文脈から解釈し、適切なアクションを取る
- spawn / observe / intervene / report / compact を状況判断で実行
- 例: 「Issue 実装して」→ co-autopilot spawn + observe、「状況は？」→ observe + 報告

### 6. Memory から得た関連知見

- ADR-014 設計（hash: 64674b02...）: ライフサイクル設計は正しい（常駐、spawn 型）がモード分離は言及なし
- 設計ファイル一覧（hash: c934ac78...）: su-observer-skill-design.md が「設計骨格」として記載
- Observer→Pilot inject パターン（hash: 50ddf0cf...）: 介入メカニズムのプロトタイプが確認済み

## 推奨アプローチ

**#440 を更新**（新規 Issue ではなく）:
1. AC に「モード判定テーブルの廃止、LLM 文脈判断への移行」を追加
2. スコープを拡大: su-observer-skill-design.md も修正対象に含める
3. 技術的アプローチにモードレス設計の指針を追加

## scope

- scope/plugins-twl
- ctx/supervision

## 影響コンポーネント

- `plugins/twl/skills/su-observer/SKILL.md` — モード分離の完全廃止、セッションマネージャー型に再設計
- `plugins/twl/architecture/designs/su-observer-skill-design.md` — モード分離の廃止（正典自体の修正）
- `plugins/twl/architecture/domain/contexts/supervision.md` — ワークフロー図の軽微修正（「モード」言及があれば削除）
- Issue #440 body — AC・スコープの更新
