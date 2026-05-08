# su-observer 制約 Reference（運用 mirror）

> **SSoT 注記**: 正典は `architecture/domain/contexts/supervision.md`。本 ref は su-observer 運用観点での運用 mirror。
> 定義変更時は supervision.md と本 ref を同期更新すること。新規制約追加時は supervision.md のテーブルを先に更新すること。
> Security gate 定義は `refs/su-observer-security-gate.md` 参照。Layer A-D のゲート定義・bypass 禁止手法はそちらで管理。

## SU-* 制約（MUST）

| 制約 ID | 内容 | 備考 |
|---------|------|------|
| SU-1 | 介入は 3 層プロトコル（Auto/Confirm/Escalate）に従わなければならない（SHALL） | OBS-1 継承 |
| SU-2 | Layer 2（Escalate）の介入はユーザー確認が MUST | OBS-2 継承 |
| SU-3 | Supervisor 自身が Issue の直接実装を行ってはならない（SHALL） | OBS-3 継承 |
| SU-4 | 同時に supervise できる controller session は 10 を超えてはならない（observer 自身は計数しない、SHALL） | OBS-4 拡張（3→5→10、#1560） |
| SU-5 | context 消費量 80% 到達時に知識外部化を開始しなければならない（SHALL）。検知手段の詳細は `refs/monitor-channel-catalog.md` の `[BUDGET-LOW]` セクション参照 | 新規 |
| SU-6a | Wave 完了時に結果収集と externalize-state を実行しなければならない（SHALL） | SU-6 分割（#498） |
| SU-6b | context 逼迫時またはユーザー指示時に /compact をユーザーへ提案しなければならない（SHOULD） | built-in CLI のためユーザー手動実行 |
| SU-7 | observed session への inject/send-keys は介入プロトコルに従う場合に許可（MAY） | OB-3 廃止に対応 |
| SU-8 | supervisor hook は bare repo 構造（main/ がディレクトリとして存在すること）を前提とし、non-bare 検出時は no-op で exit 0 する（SHALL） | #728 |
| SU-9 | supervisor hook は filename に埋め込む前に SESSION_ID を allow-list サニタイズ（[A-Za-z0-9_-]）しなければならず、サニタイズ前後で差分があれば stderr に警告を出力しなければならない（SHALL） | #729 |

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（SU-3）
- AskUserQuestion でモード選択を強制してはならない（LLM が文脈から判断すること）
- Skill tool による controller の直接呼出しをしてはならない（cld-spawn 経由で起動すること）
- Layer 2 介入をユーザー確認なしで実行してはならない（SU-2）
- 同時に 10 を超える controller session を supervise してはならない（SU-4）
- context 80% 到達を無視してはならない（SU-5）
- Wave 完了後の externalize-state を省略してはならない（SU-6a）
- /compact の自動実行を試みてはならない（built-in CLI のためユーザー手動実行が必須）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない
- **Issue 起票関連（不変条件 P / ADR-037）**: `gh issue create` を直接実行してはならない。新規 Issue の起票は必ず co-explore による explore-summary 作成後に co-issue 経由で行う。explore-summary なしの直接起票は `pre-bash-issue-create-gate.sh` で block される（bypass は `SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='<reason>'` 明記時のみ）
- `--with-chain --issue N` で co-autopilot を直接起動してはならない（ADR-026、SU-3 連鎖）

## Security gate (Layer A-D) 回避は MUST NOT

**`refs/su-observer-security-gate.md` を Read** して Layer A-D ゲート定義・bypass 禁止手法・permission 拒否対応を確認すること。

2 回以上 deny が連続した場合: 即時 STOP → **`plugins/twl/refs/intervention-catalog.md` パターン 13**（Layer 2 Escalate）→ AskUserQuestion。`refs/pitfalls-catalog.md §12` 参照。
