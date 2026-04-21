## Context

co-autopilot は複数 Wave を順に実行する。各 Wave は autopilot-init.sh → wakeup-loop.md → orchestrator.sh の順で起動する。現行実装では：

1. autopilot-init.sh は既存 session.json を検出するとエラー停止（L104-107）。完了済みの場合の自動削除は `--force` + stale(24h) 条件が揃った場合のみ（L82-87）。Wave 遷移では `--force` なしで呼ばれるため前 Wave の session.json がブロッカーになる
2. `_ORCH_LOG` のファイル名（`orchestrator-phase-${PHASE_NUM}.log`）に session_id が含まれないため、Wave をまたいで同一ファイルに追記され Monitor が前 Wave の PHASE_COMPLETE を誤検知する
3. AC 2 (commit bf5add9) はすでに hotfix 適用済み（wakeup-loop.md L26 絶対パス化）

## Goals / Non-Goals

**Goals:**
- AC 1: 完了済み session.json を --force なしで自動削除（issues 空ガード込み）
- AC 3: ログファイル名に session_id を付与し Wave 間分離（wakeup-loop.md + orchestrator.sh + テスト + アーキテクチャドキュメント同期）
- AC 4: AC 2 hotfix の再修正防止コメントを wakeup-loop.md に追加

**Non-Goals:**
- `started_at` フィールド不在の session.json 処理（別 Issue で対応）
- orchestrator.sh の全面リファクタリング
- session.json スキーマの変更

## Decisions

### AC 1: is_session_completed() 改修 + 自動削除分岐

`is_session_completed()` に `issues` フィールド空ガードを追加する。issues が空配列（`length == 0`）の場合は「未完了」と判定し false を返す（新 Wave 開始直後の race condition 防止）。

L82 の前に新分岐を挿入。実行順序:
1. `is_session_completed()=true` → 自動削除して続行
2. `--force && hours >= 24` → stale 強制削除（既存）
3. `hours >= 24` → stale 警告 exit 2（既存）
4. その他 → 実行中エラー exit 1（既存）

削除対象: `$SESSION_FILE` + `$ISSUES_DIR/issue-*.json`

### AC 3: session_id 付きログ命名

wakeup-loop.md L22-24 に SESSION_ID 取得処理を追加。`jq -r '.session_id // "unknown"'` で取得し、`unknown` フォールバック時は stderr に WARN を出力する。`_ORCH_LOG` を `orchestrator-phase-${PHASE_NUM}-${SESSION_ID}.log` に変更する。

orchestrator.sh L1311 の直接書き込み先も同一命名規則に統一する（書き込み・読み取りの path 不整合は PHASE_COMPLETE 永遠未検知を招く critical regression のため必須）。

bats テストはワイルドカード `orchestrator-phase-${N}-*.log` で照合するよう更新。

Monitor（wakeup-loop.md L48 の grep）も `orchestrator-phase-${PHASE_NUM}-*.log` ワイルドカードに更新する。

### AC 4: 再修正防止マーカー

wakeup-loop.md の `## Step A` ヘッダとコードブロック開始の間に HTML コメント（LLM コンテキスト向け）と blockquote（視認向け）を挿入する。`grep -c "HOTFIX #732"` = 2 が受け入れ条件。

## Risks / Trade-offs

- **session_id フォールバック**: session.json 不在の場合 `_ORCH_LOG` が `orchestrator-phase-${N}-unknown.log` になり、複数 Wave が unknown ファイルに追記される可能性がある。WARN 出力で検知を支援するが根本的解決は AC 1（session.json 自動削除）との組み合わせで実現
- **bats テスト更新漏れ**: ワイルドカード照合への変更でテストの厳密性が若干低下する。ただし固定名との不整合による全テスト失敗を避けるためのトレードオフとして許容する
- **orchestrator.sh L1311 特定**: 行番号はコメントに記載されているが、コード編集により変動している可能性がある。`grep -n` で現在位置を確認してから編集する
