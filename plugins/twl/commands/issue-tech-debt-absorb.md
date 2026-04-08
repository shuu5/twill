---
type: atomic
tools: [Bash, AskUserQuestion, Skill]
effort: low
maxTurns: 10
---
# /twl:issue-tech-debt-absorb - tech-debt 吸収提案

品質評価（issue-assess）で検出された tech-debt findings を受け取り、吸収候補の選択と解決済み候補の表示を行う。

## 入力

- `tech_debt_decision`: issue-assess の出力に含まれる tech-debt 関連情報
  - `absorb_candidates`: 吸収候補リスト（Issue番号、タイトル、ラベル、一致度）
  - `resolved_candidates`: 解決済み候補リスト（Issue番号、タイトル、対応spec）

## 出力

- `includes_issues`: 吸収対象の Issue 番号リスト（`#N` 形式）
- `related_issues`: Related として追加する Issue 番号リスト（`#N` 形式）

---

## 実行ロジック（MUST）

### Step 1: 吸収候補の表示と選択

吸収候補（`absorb_candidates`）が存在する場合のみ実行:

```
### tech-debt 吸収提案

以下の tech-debt Issue が新 Issue のスコープ内にあります:

| # | タイトル | ラベル | 一致度 |
|---|---------|--------|--------|
| #12 | XXX | tech-debt/warning | high |
| #15 | YYY | tech-debt/deferred-high | medium |

各 Issue について:
[A] 吸収 → 新 Issue に Includes #N として統合
[B] スキップ → 吸収しない
[C] Related のみ → Related に追加するが吸収はしない
```

AskUserQuestion で各候補の選択を取得:

- **[A] 選択時**: `includes_issues` リストに `#N` を追加
- **[B] 選択時**: どのリストにも追加しない
- **[C] 選択時**: `related_issues` リストに `#N` を追加

### Step 2: 解決済み候補の表示

解決済み候補（`resolved_candidates`）が存在する場合のみ表示:

```
### 解決済み候補

以下の tech-debt は既存 spec で対応済みの可能性があります:

| # | タイトル | 対応spec |
|---|---------|----------|
| #8 | ZZZ | user-auth |

spec で対応済みの場合、クローズを検討してください。
```

解決済み候補が存在しない場合、このセクションは表示しない。

### Step 3: 結果返却

`includes_issues` と `related_issues` を返す。
吸収候補も解決済み候補も存在しない場合、空のリストを返す。

---

## 禁止事項（MUST NOT）

- ユーザー確認なしで吸収を決定してはならない
- Issue 番号を `#[0-9]+` 形式以外で扱ってはならない
