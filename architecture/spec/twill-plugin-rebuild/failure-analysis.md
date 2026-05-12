# 失敗 analysis — 既存 twill plugin の 9 件 P0 bug 深掘り

> **目的**: 既存 twill plugin で本セッション (2026-05-12) に発見された 9 件 P0 bug の root cause を 1 件ずつ verified に深掘りし、新 spec の MUST / SHOULD として体系化する。横断要因 3 種を抽出し、新 architecture で構造的不能化を実現する。
>
> **source**: 全件 verified (commit hash / file:line / 該当 PR 確認済) または deduced (現コードからの逆算)。各 bug の confidence を明示。

---

## 横断要因 (新 spec の根幹となる lesson)

新 spec の 3 つの構造的欠陥不能化は、以下 3 つの横断要因への defense として設計される。

### F-1: 並列 Wave の設計が後付け (#1673 / #1674 / #1703 共通)

**症状**: cleanup script (#1673) / orchestrator early-exit (#1674) / checkpoint cross-pollution (#1703) は全て、「単一 Wave 想定で設計された機構に並列 Wave を後付けした」ことが共通因。shared state (`phase-review.json`, `active_branches` 配列) のスコープ問題が顕在化。

**lesson (MUST)**:
- 並列実行を前提とした state / cleanup / checkpoint は、**Worker ID (issue_number 等) を含むパスでデフォルト書き込み**する。共通パスへの書き込みは `--shared` 明示フラグ必須。
- cleanup の「何を守るか」(active_branches) のスコープは全 Wave にまたがるべき。

**新 spec での不能化**: per-Worker file mailbox (`.mailbox/<session-name>/inbox.jsonl`) で構造的に shared path を廃止。

### F-2: env var による機械的 enforcement の限界 (#1660 / #1662 / #1663 / #1684 共通)

**症状**: SKIP_*_REASON sanitize (#1660) / OBSERVER_PARALLEL_CHECK_STATES `:-` 構文 (#1662) / 同 env override 競合 (#1663) / IS_AUTOPILOT cwd-guard (#1684) は全て、bash env var で状態・権限・モードを表現することの限界 (型なし、スコープなし、継承デフォルト on)。

**lesson (MUST)**:
- security-critical な env override は **PreToolUse hook で gate 化**して session scope に閉じ込める。bash env 継承に依存しない設計。
- 同一 invariant を複数 env var で表現しない (例: 「autopilot mode」と「正しい worktree」は別 invariant)。

**新 spec での不能化**: PreToolUse hook + GitHub Project Board status SSoT で gate を機械化、env var 経由の caller authz は全廃。

### F-3: deploy / verify の分離欠如 (#1687、5 ヶ月 5 回再発の根本)

**症状**: mcp-watchdog.sh は実装あるが deploy 経路 (session-start hook) が不在。「実装した = deploy された」という暗黙の前提。5 回再発しているのに毎回「watchdog を改善する」修正で、「watchdog が起動しているか確認する」CI/verification が存在しなかった。

**lesson (MUST)**:
- 新規 daemon / watchdog 実装は「**起動 hook**」と「**起動確認テスト**」をセットで実装・merge しなければ Done と見なさない。
- N 回再発するバグは「同じ修正を繰り返している」というメタシグナル。**root (deploy 経路欠如) を追わない構造的問題**。

**新 spec での不能化**: Migration Phase 4 で MCP server を Claude Code 標準管理に委譲、自作 watchdog 廃止。

---

## 9 件 P0 bug 詳細 (1 件ずつ)

### Bug 1: #1660 SKIP_*_REASON sanitize

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1676, merge commit `23f3b421` |
| **root cause** | `chain-runner.sh` L522-527 (修正前): `SKIP_REFINED_CALLER_VERIFY=1 SKIP_REFINED_REASON='<理由>'` の REASON 値が `printf` の format string に渡され、env から leak した値が sanitize なしで log 書き込みされた。observer の並列 spawn が SKIP_REASON を汚染したまま chain-runner を呼ぶと意図しない bypass。 |
| **confidence** | deduced (修正後コードとコメントから逆算) |
| **構造的要因** | bypass mechanism の env 変数自体に有効期限・スコープ制限がない。bash env は子プロセスへ自動継承される。「bypass は log に記録する」ポリシーはあるが「bypass を後続プロセスに伝搬させない」制約が構造に存在しなかった。 |
| **lesson (MUST)** | bypass env var は使用後に `unset` する。bypass ロジックは「1 回だけ有効な token」として設計。env marker security gate は PreToolUse hook で gate 化して session scope に閉じ込める (SHOULD)。 |
| **新 spec で不能化** | bypass 機構ごと廃止し、Agent call の `allowedTools` または tool `permissions` で明示的に制御。bash env 継承に依存しない設計。 |

### Bug 2: #1662 OBSERVER_PARALLEL_CHECK_STATES `:-` syntax

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1685, merge commit `5d90ce48` |
| **root cause** | `plugins/twl/scripts/lib/observer-parallel-check.sh` 修正前: `local controller_states="${OBSERVER_PARALLEL_CHECK_STATES:-$(get_controller_states "$snapshot_ts")}"`。`:-` は「unset または空文字」のとき default 使用、`OBSERVER_PARALLEL_CHECK_STATES=""` (空) で test 時に default にフォールバックして env override が無効化されていた。 |
| **confidence** | verified (現コード L320-321 で `${VAR-default}` に修正済、コメントに #1662 言及) |
| **構造的要因** | bash `:-` と `-` の意味差は docs 化されているが実践で混同。env override は「テスト用」設計だが、テストケース自体が `""` を有効値として渡すパターンを想定できていなかった。 |
| **lesson (MUST)** | env override を受け取る bash 変数は `${VAR-default}` (unset のみ) と `${VAR:-default}` (空含む) の使い分けを明確にコメント。security-critical な env override は BATS で「空文字 set」ケースを必ずテストする。 |
| **新 spec で不能化** | 並列 spawn 判定を Python 関数 (型付き引数) に移行することで bash expansion の曖昧さを排除。 |

### Bug 3: #1663 OBSERVER_PARALLEL_CHECK_STATES override

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1686, merge commit `da957682` |
| **root cause** | `observer-parallel-check.sh` (修正前) の `_check_parallel_spawn_eligibility()` 内、controller_count=0 短絡 path で `controller_states=''` を強制 reassign、env override が set されていても無条件に上書き。現コード L317-340 で `${OBSERVER_PARALLEL_CHECK_STATES+x}` を事前 capture して reset skip するよう修正済。 |
| **confidence** | verified (現コード L317-340 のコメントに #1663 記載) |
| **構造的要因** | 「chicken-and-egg 回避」というビジネスロジック (controller=0 なら heartbeat skip) が env override テスト用変数を破壊する副作用。変数の reassign が関数途中で複数回 (L311, L337)、どちらが「正」か不明確。テスト isolation と本番ロジックが同じ env 名前空間を共有。 |
| **lesson (MUST)** | env override は関数の冒頭で `${VAR+x}` で set 状態を capture してから本番ロジックの reassign より前に評価。テスト用 env override と本番ロジックの変数スコープを分離 (SHOULD)。 |
| **新 spec で不能化** | Agent tool への移行で env 注入を排除し、Python 関数引数として override を渡す設計。 |

### Bug 4: #1673 autopilot-cleanup cross-wave 破壊

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1675, merge commit `aefcb618` |
| **root cause** | `autopilot-cleanup.sh` 修正前の orphan worktree 削除ロジック: `--project-dir` 未指定時、他 `.autopilot*` ディレクトリの issues を参照せず、他 Wave の active branches が orphan と誤判定。「archive 済みのみ削除」condition が反転、真の孤立も archive 済みも削除する可能性。 |
| **confidence** | deduced (現コード L239-253 に degrade mode 追加、L265-278 で cross-Wave active_branches 収集) |
| **構造的要因** | cleanup は「単一 Wave 想定」で設計、並列 Wave 機能追加時に cleanup スコープ未更新。`--project-dir` 引数 optional のため silent bug。孤立判定が「自分の Wave の state file」のみ参照し、他 Wave を知らなかった。 |
| **lesson (MUST)** | 並列実行を前提とした cleanup ロジックは、他の並列インスタンスが管理するリソースを認識する設計。`--project-dir` 未指定かつ並列 Wave 検出時は degrade (orphan cleanup skip) をデフォルト (SHOULD)。 |
| **新 spec で不能化** | worktree ライフサイクルを Pilot 専任 (Invariant B) として Agent 内で直接管理、独立 cleanup script を排除。「Wave 完了時に Pilot が自分の worktree のみを削除」設計で cross-Wave 参照が不要。 |

### Bug 5: #1674 orchestrator early-exit

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1690, merge commit `96f081e0` |
| **root cause** | `autopilot-orchestrator.sh` の poll_single() L604-614: 並列 Wave で orchestrator が `status=done/merge-ready` 検出すると即 `return 0` して cleanup、inject_next_workflow cycle から抜ける。`chain-step-completed: <step>` terminal phrase emit 後に orchestrator が exit していると次 workflow 送れず Pilot stuck。並列 Wave B でも同じ phase-review.json 参照で phase 完了判定誤り。 |
| **confidence** | deduced (現コード L33-44 に AC2 audit log handler 追加、`inject-next-workflow.sh` L634-658 に LAST_INJECTED_STEP bypass) |
| **構造的要因** | Worker が `chain-step-completed` emit〜orchestrator inject 完了の間に race window。並列 Wave 間 shared phase-review.json が「他 Wave の PASS」を自分の完了と誤判断 (Bug 3 と複合)。「orchestrator が exit したら誰が next inject するのか」が設計上不明確。 |
| **lesson (MUST)** | orchestrator は Worker が terminal state になるまで exit しない。early exit は audit log に記録。orchestrator の phase 完了判定は自 Wave の state file のみ参照 (shared checkpoint 参照禁止)。 |
| **新 spec で不能化** | Phase 2 (orchestrator を Skill 内 Bash + Agent で置換) で「orchestrator が exit する」概念がなくなる。Agent は tool call の完了まで implicit に待機。 |

### Bug 6: #1684 IS_AUTOPILOT cwd-guard

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1689, merge commit `cecf0a06` |
| **root cause** | `chain-runner.sh` の `step_autopilot_detect()` L276-295: `IS_AUTOPILOT=true` を `eval` で環境変数に展開するだけで、後続 chain step が main worktree 直下で実行されていても guard がなかった。Bug #1674 と組合せると Worker が worktree 作成前に main で起動して chain 進行、test-scaffold が main の source を汚染する risk。 |
| **confidence** | verified (現コード L367-386 `step_cwd_guard()` 追加、コメントに「IS_AUTOPILOT=true + orchestrator early-exit」言及) |
| **構造的要因** | IS_AUTOPILOT flag は「autopilot から呼ばれているか」を表すが「正しい worktree で動いているか」は別 invariant (Invariant B)。2 つの独立 invariant を 1 つの env var で表現したガード漏れ。chain step が source-touching かどうかを事前確認する仕組みなし。 |
| **lesson (MUST)** | 「autopilot モード」と「正しい worktree」は独立 invariant として別々に enforce。source-touching step (test-scaffold, green-impl など) の直前に fail-closed な cwd-guard を必須。 |
| **新 spec で不能化** | Worker を Pilot が作成した worktree 内で Agent(run_in_background) として spawn することで、Worker の cwd は Pilot が保証する構造。chain-runner の self-check ではなく spawn 経路での構造的保証。 |

### Bug 7: #1687 twl mcp disconnect (5 回目再発)

| 項目 | 内容 |
|---|---|
| **PR / commit** | 未マージ (migration Phase 4 対応予定)。過去 4 件 fix: #1506/#1568/#1588/#1612 |
| **root cause** | `plugins/twl/scripts/mcp-watchdog.sh` 実装は存在するが **deploy 経路が存在しない**。`plugins/twl/hooks/hooks.json` に mcp-watchdog.sh を起動する hooks エントリが不在。`deps.yaml` には参照あるが、session-start 時の自動起動 hook が存在しない。加えて Claude Code は stdio MCP server を自動 reconnect しない (upstream bug)。 |
| **confidence** | verified (hooks.json 全行確認、mcp-watchdog.sh に `--daemon` flag あるが呼ぶ hook 不在) |
| **構造的要因** | 「実装した = deploy された」という暗黙の前提。deploy 経路 (session-start hook 登録) の検証プロセスがなかった。5 回再発するが毎回 watchdog を改善する修正で、「watchdog が起動しているか確認する」CI/verification が不在。upstream limitation への対応が watchdog 一本に集中 (単一障害点)。 |
| **lesson (MUST)** | 新規 daemon/watchdog 実装は「起動 hook」と「起動確認テスト」をセットで実装・merge しなければ Done と見なさない。N 回再発するバグは「同じ修正を繰り返している」というメタシグナル、根本を追わなかった構造的問題。外部依存 (upstream bug) への workaround は docs に明記し upstream fix 待ち ticket を作成 (SHOULD)。 |
| **新 spec で不能化** | Migration Phase 4: hooks を Claude Code 標準 hook で置換。MCP server は Claude Code が標準管理し、session-start hook に watchdog を仕込む代わりに Claude Code の native session management に委譲。 |

### Bug 8: #1703 phase-review.json cross-pollution

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1704, merge commit `0a212a42`。ADR-025 Known Gap 4 に文書化済 (L69)、追跡 Issue #1399。 |
| **root cause** | `phase-review.md` L78: `python3 -m twl.autopilot.checkpoint write --step phase-review --status "$STATUS"` で `--issue-number` 引数を渡していない。`checkpoint.py` L121: `filename = f"{step}-{issue_number}.json" if issue_number else f"{step}.json"` — issue_number なしの場合 `phase-review.json` (共通ファイル) に書き込む。並列 Worker が last-writer-wins で他 Worker の merge gate に影響。`merge-gate-check-phase-review.sh` L37 も `phase-review.json` のみ参照。**checkpoint.py の read 関数 (L160) は per-issue 対応していない** (write は対応、read は未対応のギャップ)。 |
| **confidence** | verified (checkpoint.py L121/L160, phase-review.md L78, merge-gate-check-phase-review.sh L37 全件確認済) |
| **構造的要因** | ADR-025 で Known Gap として認識されていたが (#1399 追跡中) 実装が先行した。checkpoint ファイルパスの「何が共有されてはいけないか」が checkpoint.py の設計に埋め込まれず、呼び出し側 (phase-review.md) に委譲。5 PR 100% reject incident まで顕在化しなかった (通常並列 Wave を使わない運用)。 |
| **lesson (MUST)** | 並列 Worker が書き込む checkpoint は Worker ID (issue_number 等) を含むパスにデフォルトで書き込む。共通パスへの書き込みは明示的な `--shared` フラグを必要とする設計。Known Gap は「追跡中 Issue あり」だけでは不十分、実装 block を PR に含めるか明確な Ship 条件を定義 (SHOULD)。 |
| **新 spec で不能化** | Migration Phase 2/3: specialist review を subagent で置換、review 結果は per-Worker mailbox (TaskCreate + per-issue notification) で管理。共通 checkpoint ファイルという概念を廃止。 |

### Bug 9: #973 RED merge silent rot (5 ヶ月放置)

| 項目 | 内容 |
|---|---|
| **PR / commit** | PR #1700, merge commit `b0e275a4` |
| **root cause** | `plugins/twl/tests/bats/ac-scaffold-tests-973.bats` — 全テストに `# RED: 全テストは実装前に fail する` コメントあるが、実装ファイル群が不在: `cli/twl/src/twl/intervention/soft_deny_match.py` 不在、`plugins/twl/skills/su-observer/refs/soft-deny-rules.md` 不在、`intervene-auto.md` の `permission-ui-response` パターン未追記。`permission-request-auto-approve.sh` (hooks.json L113) は実装済で `AUTOPILOT_DIR` set 時に自動 allow するが、observer が「allow すべきでない permission」(soft-deny 対象) にも allow を返していた。 |
| **confidence** | verified (ac-scaffold-tests-973.bats 全行確認、soft_deny_match.py の不在確認) |
| **構造的要因** | RED test scaffold の「全テストが fail する」状態が CI で許容されていた (merge blocked されない)。test scaffold merge は「実装が来たときの準備」として良い慣習だが、scaffold だけの PR が merge された後に「実装 Issue」が別途起票されないか、起票されても deprioritize された。permission UI が `AUTOPILOT_DIR` set のみで全 allow する設計は security hole、手動運用で問題が表面化しなかった。 |
| **lesson (MUST)** | RED test scaffold は「実装 Issue が Board に存在し、Done 前に scaffold を merge しない」か「scaffold merge と同時に TODO Issue を P0 で起票」のどちらかを必須。security gate (permission auto-approve) は fail-safe (deny-by-default) を基本とし、allow 条件を明示的に narrow。 |
| **新 spec で不能化** | Migration Phase 4: Claude Code 標準 hook (PermissionRequest hook) で permission 判定。soft-deny ルールを hook スクリプトに直接実装し、AUTOPILOT_DIR という外部状態に依存しない設計。**加えて新 spec の step verification framework で「RED test 増加 + RED 確認」「green-impl での src/ diff 確認」を post-verify 必須化** → RED-only merge が構造的に block される (本 bug の核心解消)。 |

---

## 統計まとめ

| 横断要因 | 該当 bug | 解消経路 (新 spec) |
|---|---|---|
| F-1 並列 Wave 後付け | #1673, #1674, #1703 | per-Worker file mailbox + Agent isolation |
| F-2 env var 限界 | #1660, #1662, #1663, #1684 | PreToolUse hook + GitHub Project Board status SSoT |
| F-3 deploy/verify 分離 | #1687 | Claude Code 標準 hook + MCP native management |
| **横断要因外** | #973 (silent rot) | step verification framework (post-verify 機械化) |

---

## 新 spec MUST / SHOULD 抽出 (本 audit の最終 output)

### MUST (構造的不能化を要する原則)

1. **state / cleanup / checkpoint は per-Worker パスにデフォルト書き込み**、共通パスは `--shared` 明示フラグ必須 (Bug #1703, #1673)
2. **cleanup の active_branches スコープは全 Wave にまたがる** (Bug #1673)
3. **bypass env var は使用後 `unset`、1 回だけ有効な token として設計** (Bug #1660)
4. **env override は `${VAR+x}` で set 状態を capture してから本番ロジックを評価** (Bug #1663)
5. **bash env override は BATS で「空文字 set」ケースを必ずテスト** (Bug #1662)
6. **`${VAR-default}` と `${VAR:-default}` の使い分けは明確にコメント** (Bug #1662)
7. **「autopilot mode」と「正しい worktree」は独立 invariant、別 enforce** (Bug #1684)
8. **source-touching step の直前に fail-closed cwd-guard 必須** (Bug #1684)
9. **orchestrator は Worker terminal state まで exit しない、early exit は audit log** (Bug #1674)
10. **orchestrator の phase 完了判定は自 Wave の state file のみ参照** (Bug #1674)
11. **新規 daemon/watchdog は「起動 hook」+「起動確認テスト」セット必須** (Bug #1687)
12. **N 回再発バグは root を追う、同じ修正を繰り返さない** (Bug #1687、メタ原則)
13. **RED test scaffold は実装 Issue Board 上存在 or 同時 P0 起票必須** (Bug #973)
14. **security gate (permission auto-approve) は fail-safe (deny-by-default)** (Bug #973)
15. **step verification framework で post-verify (RED test 増加 / GREEN PASS / src diff 等) を機械化** (Bug #973、横断的)

### SHOULD (推奨運用)

1. env marker security gate は PreToolUse hook で session scope に閉じ込める
2. テスト用 env override と本番ロジックの変数スコープを分離
3. `--project-dir` 未指定かつ並列 Wave 検出時は degrade をデフォルト
4. 外部依存 (upstream bug) への workaround は docs 明記 + upstream fix ticket
5. Known Gap は実装 block を PR に含めるか、明確な Ship 条件を定義
6. AC 完備性は co-issue refine 段階で worker-spec-review 通過必須

---

## 関連 spec ファイル

- 各 lesson の構造的不能化の詳細実装: `step-verification.html` / `spawn-protocol.html` (placeholder) / `gate-hook.html` (placeholder)
- 失敗から導かれる crash failure mode 全体: `crash-failure-mode.html`
- ADR 全件継承戦略: `adr-fate-table.md` (ADR-025 Known Gap 4 解消含む)
- 不変条件継承戦略: `invariant-fate-table.md` (不変条件 K/L/R/S 強化)

---

## audit source

- 本セッション (2026-05-12) feature-dev workflow Phase 2 で 3 code-explorer agent 並列調査
- 各 bug の verified 根拠: commit hash + file:line + 関連 PR / ADR 引用
- doobidoo Memory MCP hash 6ef844e9 / 74b7cdf7 / 7727b59f に lesson 集約済 (本 audit はそれらの拡張版)
