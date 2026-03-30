# 並列 specialist レビュー（chain-driven）

pr-cycle chain のオーケストレーター。動的レビュアー構築と並列 specialist 実行を管理する。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 2 | phase-review（本コンポーネント） | composite |

## ドメインルール

### 動的レビュアー構築

PR diff のファイルリストから specialist を動的に決定する。

#### 基本ルール

| 条件 | 追加される specialist |
|------|----------------------|
| deps.yaml 変更あり | worker-structure + worker-principles |
| コード変更あり（.ts, .py, .sh, .md 等） | worker-code-reviewer + worker-security-reviewer |

#### conditional specialist（tech-stack-detect 連携）

```bash
CONDITIONAL=$(bash scripts/tech-stack-detect.sh < <(git diff --name-only origin/main))
```

tech-stack-detect が返した specialist をリストに追加する。

#### specialist リストが空の場合

変更ファイルがレビュー対象外（.gitignore 等のみ）の場合、specialist リストは空となり自動 PASS。

### 並列 specialist 実行

全 specialist を Task spawn で並列実行する。逐次実行は行わない。

```
各 specialist について:
  Task(subagent_type="dev:<specialist-name>", prompt="...")
```

### 結果集約

全 specialist の出力を specialist-output-parse スクリプトでパースし、findings を統合する。

```bash
PARSED=$(echo "$SPECIALIST_OUTPUT" | bash scripts/specialist-output-parse.sh)
```

AI による自由形式の変換は禁止。パーサーの構造化データのみを使用する。

## チェックポイント（MUST）

`/dev:scope-judge` を Skill tool で自動実行。

