# /twl:issue-review-aggregate - specialist レビュー結果の集約・ブロック判定

issue-spec-review の出力を Issue 単位で集約し、ブロック判定と findings テーブルを生成する。

## 入力

呼び出し元（co-issue controller）から以下を受け取る:

- `review_results`: issue-spec-review の出力リスト（Issue 別の specialist_results）

## フロー（MUST）

### Step 1: 出力なし完了の検知（上位ガード）

各 specialist の返却値を行単位に分解し、以下の正規表現でマッチを試みる:

- status 検出: `^status:\s*(PASS|WARN|FAIL)\b`（行頭、コロン後スペース任意、有効値のみ、単語境界で末尾を限定）
- findings 検出: `^findings:`（行頭）

いずれにもマッチしない場合を「出力なし完了」と判定し、findings テーブルに WARNING エントリを追加する。Phase 4 はブロックしない。

```
WARNING: <specialist名>: 構造化出力なしで完了（調査が maxTurns に到達した可能性）
```

**役割分担**: このガードは YAML 形式の行単位出力を想定した上位ガードとして機能する。JSON 形式（`{"status": "PASS", "findings": []}` 等）や行頭以外に `status:` が現れる出力は下位ガード（`ref-specialist-output-schema.md` のパース失敗フォールバック）に委ねる。

### Step 2: findings 統合

全 specialist の findings を Issue 別にマージする。

### Step 3: ブロック判定

`severity == CRITICAL && confidence >= 80 && finding_target == "issue_description"` が 1 件以上 → 当該 Issue は Phase 4 ブロック。

- `codebase_state` はブロック対象外
- `finding_target` 欠如または enum 外の値 → `issue_description` として扱う

### Step 4: ユーザー提示

Issue 別に findings テーブルを表示:

```markdown
## specialist レビュー結果

### Issue: <title>

| specialist | status | findings |
|-----------|--------|----------|
| issue-critic | WARN | 2 findings (0 CRITICAL, 1 WARNING, 1 INFO) |
| issue-feasibility | PASS | 0 findings |
| worker-codex-reviewer | PASS | 0 findings |

#### findings 詳細
| severity | confidence | category | message |
|----------|-----------|----------|---------|
| WARNING | 75 | ambiguity | 受け入れ基準の項目3が定量化されていない |
| INFO | 60 | scope | Phase 2 との境界が明確 |
```

### Step 5: CRITICAL ブロック処理

ブロック判定で 1 件以上 CRITICAL がある場合:

> 以下の Issue に CRITICAL findings があります。修正後に再実行してください

修正完了後、呼び出し元（co-issue）が issue-spec-review を再実行可能。

### Step 6: split 提案ハンドリング

`category: scope` の split 提案がある場合、ユーザーに提示し承認を求める。

- 承認後に分割するが、分割後の新 Issue に対して specialist 再レビューは行わない（最大 1 ラウンド）
- 承認後に生成された各 Issue candidate には `is_split_generated: true` をコンテキストフラグとして設定すること（MUST）
- このフラグは Phase 4 まで保持する
- `cross_repo_split = true` による子 Issue は specialist レビュー済み body から生成されるため、`is_split_generated` の対象外

## 出力

以下を呼び出し元に返却:

```
blocked_issues: [<CRITICAL ブロックされた Issue タイトルリスト>]
split_issues: [<split で新規生成された Issue candidate リスト>]
findings_summary: <上記テーブル形式の文字列>
```

## 禁止事項（MUST NOT）

- specialist を直接 spawn してはならない（issue-spec-review の責務）
- ブロック判定の閾値を変更してはならない（CRITICAL && confidence >= 80）
