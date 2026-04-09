---
type: reference
spawnable_by: [controller, atomic, workflow]
disable-model-invocation: true
---

# Load Test Baselines

co-self-improve framework の負荷テスト level (smoke / regression / load) の **定量基準**。

子 8 e2e test がこの基準を threshold として使用する。

## level 定義

| level | 並列 Issue 数 | chain 実行時間 | 想定 conflict | 想定 PR | observer polling |
|---|---|---|---|---|---|
| smoke | 1 | 2-5 分 | 0 | 1 | 30 秒 |
| regression | 3-5 | 10-30 分 | 1-2 | 3-5 | 15 秒 |
| load | 8-12 | 60+ 分 | 5+ | 10+ | 5 秒 |

## smoke level pass 条件

- 1 Issue が 5 分以内に done になる
- observer が **少なくとも 1 件の detection を生成** する (空 detection は test 失敗)
  - smoke シナリオは意図的に「検出されるべきパターン」を埋め込む (例: dummy "MergeGateError" を log に出力)
- observer の集約結果が JSON 形式で `.observation/<session_id>/aggregated.json` に保存される

## regression level pass 条件

- 3-5 Issue が 30 分以内に **過半数 done** (failed/skipped 含む)
- conflict 1 件以上発生 (想定通り)
- observer が **3 件以上の検出** を生成
- observer-evaluator specialist が **少なくとも 1 件呼び出される** (severity>=medium 検出があるため)

## load level pass 条件

**本 reference では定義のみ、実装は将来の別 Issue**。

- 8-12 Issue が 180 分以内に **過半数 done**
- conflict 5 件以上発生
- observer が **10 件以上の検出** を生成
- 詳細な pass 条件は load level シナリオ実装時に確定する

## ベンチマーク

| level | 期待 cost (token) | 期待 duration (分) | 期待 LLM 呼び出し回数 |
|---|---|---|---|
| smoke | 5K-15K | 2-5 | 5-10 |
| regression | 50K-150K | 10-30 | 30-80 |
| load | 200K-600K | 60-180 | 100-300 |

## 失敗時の対応

- pass 条件未達 → e2e test fail
- 実行時間超過 → e2e test timeout (CI で 60 分上限)
- LLM 呼び出し失敗 → e2e test fail + retry なし (本 reference では retry 機構を含めない)

## 観察対象シナリオの選択

| 状況 | 推奨 level |
|---|---|
| controller 改修後の smoke verify | smoke |
| atomic 群追加後の regression verify | regression |
| 大規模 framework 変更後 (Epic 完了時) | regression + load |
