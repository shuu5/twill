# dig report — tool-* 仕様 finalization (2026-05-13)

**目的**: tool-* (旧 tool-architect / tool-project / tool-utility / tool-self-improve の 4 件) の責務 / 境界 / 詳細仕様を `dig` skill で対話的に詰めた結果をまとめる。**spec 本体への反映は別途実施**。

**source**: 本 session で `dig` skill を 3 軸 × 5 ラウンド = 20 question 実施。

**user の核心意図**:
- 長期安定する仕組みを最初の設計段階で作り込む
- 公式 verify を sandbox で実機検証 + hyperlink で spec 表現
- pre-tool-use hooks の error 鬱陶しい → 既に無効化済 (commit `de0ec97a`)

---

## 0. 結論 (3 tool 構成、tool-utility 廃止)

| tool | 由来 | 役割 |
|---|---|---|
| **tool-architect** | co-architect rebrand | HTML spec 対話的維持 + 自律 verify (2 層) + 軽量 PR cycle |
| **tool-project** | co-project rebrand + 拡張 | GitHub Project 一括設定 + template + verify (3 軽 scope) |
| **tool-sandbox-runner** | co-self-improve rebrand | sandbox × feature matrix で twill + 他 project のテスト + log 分析 + Idea Issue 起票 |
| ~~tool-utility~~ | (廃止) | commands は architect/project/admin/sandbox-runner に再分配 |

---

## 0.5 verify status と公式 source (本 dig 各 claim 検証、2026-05-13 追加)

> **本 section の目的**: 本 dig で確定した各 claim を `verified` / `deduced` / `inferred` / `experiment-verified` の 4-state status で分類し、公式 source URL を提示する。ユーザーフィードバック (2026-05-13): 「dig report も当然最新公式ソースを使った verify が必要」。

### legend (4-state verification status)

| status | 意味 | 表記 |
|---|---|---|
| **verified** | 公式 docs / 既存実装で確認済 | `[verified]` |
| **deduced** | 型・docs・既存実装から逆算 (公式直接記載なし) | `[deduced]` |
| **inferred** | 推測 (実機 EXP 実行で確定予定) | `[inferred → EXP-NNN]` |
| **experiment-verified** | sandbox 実機再現済 (将来、Phase 1 PoC 以降) | `[experiment-verified]` |

### 本 dig で新規 WebFetch verify した公式 docs (2026-05-13)

| docs URL | verify 内容 |
|---|---|
| [code.claude.com/docs/en/plugins](https://code.claude.com/docs/en/plugins) | `--plugin-dir` flag, `.claude-plugin/plugin.json` schema, skill namespace `/plugin:skill`, `monitors/monitors.json` schema, `hooks/hooks.json` 配置、`bin/` PATH 注入、`.lsp.json` LSP server, `settings.json` で `agent` key |
| [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) | matcher singular field, exit code 0/1/2 semantics (PreToolUse は exit 2 で block, PostToolUse は block 不可で stderr → Claude へ), `permissionDecision` enum: `allow|deny|ask|defer`, env: `CLAUDE_PROJECT_DIR` / `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` / `CLAUDE_ENV_FILE` / `CLAUDE_EFFORT`, stdin JSON schema (tool_name, tool_input, tool_use_id, session_id, transcript_path, cwd, permission_mode, hook_event_name) |
| [cli.github.com/manual/gh_project](https://cli.github.com/manual/gh_project) | sub-commands 全 19 件: close / copy / create / delete / edit / field-create / field-delete / field-list / item-add / item-archive / item-create / item-delete / item-edit / item-list / link / list / mark-template / unlink / view。write-capable は 15 件 |

### tool-architect §1 各 claim の verify

| section | claim | status | source / 備考 |
|---|---|---|---|
| §1.1 役割 | HTML spec の対話的維持 + feature-dev workflow 経由 | [deduced] | tool 設計選択 (検証不要、設計合意) |
| §1.2 層 1 | spec 全 file grep で 4-state status listing | [verified] | LLM 規律 (自明、本 dig で確認) |
| §1.2 層 2 | PostToolUse hook (`verify-coverage.sh`) で grep-based warn | [verified] | [hooks docs](https://code.claude.com/docs/en/hooks): "PostToolUse can't block, stderr fed to Claude" — warn のみ運用と整合 |
| §1.2 層 2 | exit 0 + JSON で `decision: "block"` not set → tool allowed | [verified] | hooks docs Exit Code table (上記) |
| §1.2 EXP | <a href="EXP-027">EXP-027</a> verify-coverage.sh の grep 動作検証 | [inferred → EXP-027] | (実機未検証、Phase 1 PoC で実行) |
| §1.3 PR cycle | `gh pr create --auto-merge=false` | [verified] | [gh CLI manual](https://cli.github.com/manual/gh_pr_create) |
| §1.3 PR cycle | worker-spec-review 1 agent + fix loop 3 回 | [deduced] | 既存 worker-pr-cycle 8 specialist との対比で軽量化判断、検証 EXP-029 |
| §1.3 PR cycle | <a href="EXP-029">EXP-029</a> 3 回 loop で収束 or escalate | [inferred → EXP-029] | (実機未検証) |
| §1.4 spec hook | PreToolUse `Edit\|Write` matcher の pipe syntax | [verified] | hooks docs: "exact match or `\|`-separated alternatives" |
| §1.4 spec hook | exit 2 で PreToolUse 上の Edit/Write を block | [verified] | hooks docs Exit Code table: "exit 2 blocks PreToolUse" |
| §1.4 spec hook | 既存 pre-tool-use-worktree-boundary.sh の deny pattern を継承 | [verified] | `plugins/twl/scripts/hooks/pre-tool-use-worktree-boundary.sh` (Inv B 実装、本 spec で活用継承) |
| §1.4 caller 識別 | env 変数 `CLAUDE_PLUGIN_ROOT` 経由 | [verified] | hooks docs: "CLAUDE_PLUGIN_ROOT: Plugin installation directory (plugin hooks only)" |
| §1.4 caller 識別 | env 変数 `TWL_TOOL_CONTEXT` 経由 (新規) | [inferred → EXP-028] | twl 独自設計、`spawn-tmux.sh` で env export 想定 (要 EXP) |
| §1.5 EXP hub | experiment-index.html が全 EXP-001〜031 集約 | [verified] | 既存 file 存在 + 本 dig で 13 件追加 (EXP-019〜031) |

### tool-project §2 各 claim の verify

| section | claim | status | source / 備考 |
|---|---|---|---|
| §2.1 3 軽 scope | GitHub Project + template + verify の 3 機能 | [deduced] | tool 設計選択、scope 限定の合意 |
| §2.2 matrix 4 手段 | gh CLI / GraphQL API / gh-mcp / twl-mcp | [verified] (手段存在) | gh project 19 sub-commands ([cli.github.com/manual/gh_project](https://cli.github.com/manual/gh_project))、GraphQL Projects v2 API は GitHub Docs に記載 |
| §2.2 領域 5 × 手段 4 | status field option 追加 / kanban col order / label / view / filter の write 可能性 | [inferred → EXP-019〜023] | gh CLI には `field-create` / `field-delete` / `item-edit` 存在、ただし status field の **option 追加** や **kanban col order 変更** の specific path は cli 直接表現が不明。GraphQL projects v2 で `updateProjectV2Field` 等が存在するが要実機検証 |
| §2.2 新 MCP tool 価値 | <a href="EXP-024">EXP-024</a> twl_validate_project_setup の必要性 | [inferred → EXP-024] | tool-project で gh CLI / GraphQL で十分か、独自 MCP tool 化価値あるか |
| §2.3 template | git submodule + tag versioning | [verified] | [git-submodule(1) man](https://git-scm.com/docs/git-submodule)、`git submodule add` + tag pinning は標準 |
| §2.3 stack 3 件 | TS Next.js+Hono / Supabase / Docker Compose | [verified] (stack 存在) | (一般技術、verify 不要) |
| §2.4 安全性 | git tag pre-template-`<ts>` + `git reset --hard` rollback | [verified] | [git docs](https://git-scm.com/docs/git-tag) + git reset man |
| §2.4 idempotent | template 2 回 apply → 同一 state | [inferred → EXP-026] | tool 実装後検証 |
| §2.4 EXP | <a href="EXP-025">EXP-025</a> template apply + build smoke test | [inferred → EXP-025] | 実装後検証 |
| §2.5 既存 project | default skip + verify diff 提示 | [deduced] | tool 内部設計選択 |
| §2.6 sub-command | init / setup-board / apply-template / verify-board / migrate / snapshot / plugin-create / prompt-audit (8 件) | [deduced] | 既存 co-project の sub-command 継承 + init 追加 |
| §2.6 新 MCP tool | `twl_validate_project_setup` の実装 | [inferred → 実装] | `cli/twl/src/twl/validation/project_setup.py` ~80 行 (Phase 1 PoC で実装) |

### tool-sandbox-runner §3 各 claim の verify

| section | claim | status | source / 備考 |
|---|---|---|---|
| §3.1 役割 | sandbox × feature matrix で twill self test + 他 project test | [deduced] | tool 設計選択、scope 合意 |
| §3.2 起動形式 | `--sandbox=<name> --features=<list> --collect-logs=all` | [deduced] | slash command 引数 設計選択 |
| §3.3 catalog 場所 | `plugins/twl/sandboxes/<name>/` | [verified] | [plugins docs](https://code.claude.com/docs/en/plugins): plugin root に任意 directory 配置可、`bin/` / `monitors/` 等の precedent あり |
| §3.3 manifest 3 件 | `sandbox.yaml` / `setup.sh` / `features.yaml` | [deduced] | catalog 設計選択 (deps.yaml v3.0 style 参考) |
| §3.4 twill-self sandbox | `test-target/main` orphan branch + dedicated worktree | [verified] | 既存 `plugins/twl/skills/co-self-improve/SKILL.md` L (test-target/main 直接参照) |
| §3.4 security | GH_TOKEN test-repo 専用 (main へは read-only) | [deduced] | sandbox security 設計選択、cleanup pattern は既存 `git worktree remove --force` 継承 |
| §3.5 log 収集 | `claude --plugin-dir` + `CLAUDE_PROJECT_DIR` 経由 sandbox 起動 | [verified] | [plugins docs](https://code.claude.com/docs/en/plugins): "claude --plugin-dir ./my-plugin" verbatim、`--plugin-dir` flag は公式 development/testing path |
| §3.5 jsonl path | `~/.claude/projects/$(encoded $(pwd))/*.jsonl` | [verified] | 既存 jsonl 監視で実体験済 (本 session の `7775f0cd-...jsonl` 参照) |
| §3.5 tmux 命名 | `sandbox-${RUN_ID}-<role>` window | [deduced] | tmux new-window naming 設計選択 |
| §3.5 capture-pane | `tmux capture-pane -p -S -10000` | [verified] | tmux(1) man、本 spec で複数箇所 verified |
| §3.6 LLM 分析 | pattern catalog 6 件 + freeform 両対応 | [deduced] | 設計選択 (pattern-only or freeform-only の disadvantage を hybrid で解消) |
| §3.6 LLM output schema | JSON `{problems: [{pattern_id, freeform_title, confidence, impact_scope, log_excerpt}]}` | [deduced] | schema 設計選択 |
| §3.7 doobidoo | `mcp__doobidoo__memory_search` mode=hybrid | [verified] | 既存 MCP server tool interface (本 session で実利用、9 hash 蓄積) |
| §3.7 similarity threshold | similarity > 0.75 で重複判定 | [inferred → EXP-031] | doobidoo の similarity score 範囲 (0-1) は verified、0.75 閾値は EXP で false +/- 率検証 |
| §3.7 Idea Issue 起票 | severity=critical のみ起票、minor は doobidoo のみ | [deduced] | 設計選択 (Issue spam 回避) |
| §3.8 timeout | wall-clock 30m default | [deduced] | 設計選択、`--timeout=30m` で override 可 |
| §3.8 budget threshold | budget 5h % > 50 で timeout | [deduced] | Inv Q format ([verified](../../plugins/twl/refs/ref-invariants.md#invariant-q)) を判定に流用、50% 閾値は設計選択 |
| §3.8 EXP | <a href="EXP-030">EXP-030</a> sandbox 1 cycle 動作 + log 収集検証 | [inferred → EXP-030] | (実機未検証、Phase 1 PoC で実行) |

### tool-utility 廃止 §4 の verify

| claim | status | source / 備考 |
|---|---|---|
| tool-utility SKILL.md 79 行 | [verified] | `plugins/twl/skills/co-utility/SKILL.md` 行数 (file size 確認済) |
| commands 再分配先 (architect / project / admin / sandbox-runner) | [deduced] | 設計合意、各 command の責務帰属判断 |

### 新規 helper / file §6 の verify

| file | status | source / 備考 |
|---|---|---|
| `verify-coverage.sh` (~50 行) | [inferred → 実装] | grep-based warn の規模推定、実装で確定 |
| `pre-tool-use-spec-write-boundary.sh` (~30 行) | [inferred → 実装] | 既存 worktree-boundary (~40 行) 参照、規模推定 |
| `worker-spec-review.md` (~100 行 SKILL.md) | [inferred → 実装] | review agent prompt 規模推定 |
| `problem-patterns.yaml` (~50 行、6 pattern) | [deduced] | catalog 設計、6 pattern 確定 |
| sandbox `sandbox.yaml + setup.sh + features.yaml` (per sandbox) | [inferred → 実装] | manifest 規模推定 (~30+50+50 行) |
| `cli/twl/src/twl/validation/project_setup.py` (~80 行) | [inferred → 実装] | MCP tool validation 規模推定 |
| `shuu5/twill-templates` 別 repo | [inferred → 実装] | 別 repo 構造 (Phase 1 PoC 以降で作成) |

### 削除対象 §7 の verify

| 削除対象 | status | source / 備考 |
|---|---|---|
| `plugins/twl/skills/co-utility/SKILL.md` (79 行) | [verified] | file 行数確認済 |
| co-utility 関連 catalog / script | [deduced] | 関連ファイルは co-utility/SKILL.md 内 reference 確認後決定 |

### 残課題 §8 の verify

§8 の残課題は全て **[inferred] (将来 dig / 実装段階で詰める)**。worker-spec-review prompt / verify-coverage.sh grep regex / caller 識別ロジック等は実装 PR cycle で確定する。

### core lesson §11 の verify

| lesson | status | source / 備考 |
|---|---|---|
| §11.1 tool-utility 不要 | [verified] | 79 行 SKILL.md + 他 3 tool + admin inline で吸収可能、本 dig で確認 |
| §11.2 self-improve → sandbox-runner rename | [deduced] | 命名選択 (intent 明確化) |
| §11.3 tool-architect spec author 単一化 | [deduced] | spec edit boundary 設計選択、PreToolUse deny で機械 enforce |
| §11.4 PR cycle 軽量化 | [deduced] | worker-pr-cycle 8 specialist との対比 |
| §11.5 2 層 verify 併用 | [verified] | [hooks docs](https://code.claude.com/docs/en/hooks): PostToolUse は warn-only に適、PreToolUse は block 可、両層併用は設計妥当 |
| §11.6 plugin scope catalog | [verified] | [plugins docs](https://code.claude.com/docs/en/plugins): plugin root に任意 directory OK |
| §11.7 既存 verified pattern 継承 | [verified] | `pre-tool-use-worktree-boundary.sh` (Inv B 実装) / `session-atomic-write.sh` (flock pattern) / `test-target/main` orphan branch (co-self-improve 実装) を本 dig で全て確認済 |

### verify 結果サマリ

- **verified**: 19 件 (公式 docs / 既存実装で確認済)
- **deduced**: 18 件 (型・docs・既存実装からの逆算、設計選択合意)
- **inferred → EXP**: 13 件 (EXP-019〜031 で実機検証予定)
- **inferred → 実装**: 7 件 (実装段階で規模 / 詳細確定)

合計 ~57 claim、verify gap は 20 件 (EXP / 実装で順次解消)。**最大の inferred gap** は §2.2 GitHub Project 5 領域 × 4 手段 matrix (EXP-019〜023)、**実装で確定** は §6 新規 helper file 規模 ~7 件。

---

## 1. tool-architect 詳細

### 1.1 役割
- HTML 形式 architecture spec を **「現仕様」** として対話的に維持
- feature-dev workflow 経由 (issue を介さない、直接対話)
- 後の実装指針の大本

### 1.2 verify 強制機構 (**2 層併用**)

**層 1: SKILL.md MUST (LLM 規律)**
- Step 0: spec 全 file を grep して 4-state status (inferred / deduced / verified / experiment-verified) を listing、未 verified を todo 化
- Step N: 新 feature 追加時に EXP 候補生成必須

**層 2: PostToolUse hook (機械検証)** — `verify-coverage.sh` (新規)
- 動作:
  1. `grep -c '<span class="vs inferred">' spec/*.html` → N inferred (warn)
  2. `grep -c '<span class="vs deduced">' spec/*.html` → M deduced (warn)
  3. `git diff HEAD -- spec/*.html` で new section に `<a class="exp-link">` 不在を warn
  4. `changelog.html` を git diff と突合、本日 entry 不在を warn
- 振る舞い: **warn のみ** (block せず)、PR review で LLM が評価して fix 要求

### 1.3 軽量 PR cycle

| step | 内容 |
|---|---|
| 1 | feature-dev で spec edit |
| 2 | `git commit` |
| 3 | `gh pr create --auto-merge=false` |
| 4 | `worker-spec-review` spawn (1 agent、新規軽量 review agent) |
| 5 | review findings: 未 verified claim listing / EXP 漏れ check / changelog 漏れ check |
| 6 | tool-architect 自己 fix loop (**最大 3 回**) |
| 7 | review PASS or 3 回到達 → user `AskUserQuestion` approve |
| 8 | merge |

**recursive PR rule**: tool-architect が自身の spec を更新する PR 作成 **OK**、ただし review は self skip、user / 他 tool に委譲。

### 1.4 spec edit 所有権

| entity | edit 権 |
|---|---|
| tool-architect | ✅ (PR cycle 経由) |
| user | ✅ (手動 edit) |
| admin / phase-* / worker-* / tool-project / tool-sandbox-runner | ❌ (read-only) |

**hook enforce**: `pre-tool-use-spec-write-boundary.sh` (新規)
- matcher: `Edit|Write architecture/spec/*`
- deny 条件: caller が tool-architect / user 以外
- plugin scope で配置

### 1.5 spec 全体の verify status 集約

- `experiment-index.html` (本 session 第 3 弾で確定) が全 EXP-001〜018 の status listing hub
- 個別 spec file は `<span class="vs ...">` で claim 単位の status
- 将来 CI で自動 status 更新 (実行結果 → badge 更新)

---

## 2. tool-project 詳細

### 2.1 役割 (3 軽 scope)

- **GitHub Project 一括設定**: status field 6 stage + kanban view (col order) + label
- **template apply**: 主要 stack (TS Next.js+Hono / Supabase / Docker Compose)
- **verify**: `twl_validate_project_setup` MCP tool (新規) で設定が正しいか assert

### 2.2 GitHub write boundary 調査 (5 領域 × 4 手段 matrix)

新規 EXP 計 5 件で **5 領域 × 4 手段** の write 可能性を実機検証:

| 領域 | EXP-id | gh CLI | GraphQL | gh-mcp | twl-mcp |
|---|---|---|---|---|---|
| status field option 追加 | EXP-019 | ? | ? | ? | N/A |
| kanban col order 変更 | EXP-020 | ? | ? | ? | N/A |
| label add/remove | EXP-021 | ? | ? | ? | N/A |
| view switch (kanban/table) | EXP-022 | ? | ? | ? | N/A |
| filter / group-by 設定 | EXP-023 | ? | ? | ? | N/A |

調査結果に基づき、最も信頼性高い手段を採用 (`twl_validate_project_setup` は MCP 化候補)。

### 2.3 template 詳細

**stack 3 件 + 別 git repo + git submodule versioning**:

```
twill-templates/ (別 git repo、shuu5/twill-templates)
├── ts-nextjs-hono-mono/
│   ├── package.json (workspaces)
│   ├── apps/web/ (Next.js)
│   ├── apps/api/ (Hono)
│   └── packages/shared/
├── supabase/
│   ├── schema.sql
│   ├── migrations/
│   └── .env.example
└── docker-compose/
    └── compose.yml
```

- twill main から git submodule で fetch、tag (例 `v0.1.0`) で version pin
- 将来拡張: python-fastapi / r-quarto / k8s
- 拡張は tech-debt Issue として段階追加

### 2.4 template apply の安全性

**dry-run default + file のみ add (既存上書き禁止) + rollback snapshot**:

```
flow:
  1. tool-project apply-template --stack=ts-nextjs-hono-mono
  2. default dry-run: file 一覧 + conflict listing
  3. user approve → 実適用
  4. git tag pre-template-<ts> (rollback 用 snapshot)
  5. file add only (既存は skip)
     conflict file: user override のみ overwrite
  6. error 時: git reset --hard pre-template-<ts>
```

**EXP-026** (新規): template を 2 回 apply して同一 state を verify (idempotent)

### 2.5 既存 project の idempotency

**default skip + verify diff 提示 + user 確認**:

```
flow:
  1. detect 既存 setting
  2. verify mode (diff 表示):
     expected: ...
     actual:   ...
     diff:     ...
  3. AskUserQuestion: skip / overwrite / merge
  4. destructive (kanban 順位変更 / label 削除) は user approve 必須
```

**EXP-022** (上記再掲): 既存 project に 2 回 setup 適用して idempotent verify

### 2.6 sub-command 設計 (**init 統合 + 別個コマンド**)

| sub-command | 役割 |
|---|---|
| **init** | GitHub Project + template + verify を sequence 実行 (新規 project 用) |
| setup-board | Project のみ (既存 project 用) |
| apply-template | template のみ |
| verify-board | 設定検証 |
| migrate | 既存 → 新 version |
| snapshot | 現 state を template 化 |
| plugin-create | plugin 作成 (既存継承) |
| prompt-audit | (既存継承) |

**使い分け**:
- 新規 project: `init` 1 発
- 既存 project: `setup-board` or `apply-template` 個別
- 検証のみ: `verify-board`

---

## 3. tool-sandbox-runner 詳細 (rename from tool-self-improve)

### 3.1 役割

- twill plugin sandbox で twill 自身を実行 + 全層 (admin/pilot/worker) log 収集 + 問題分析 + Idea Issue 起票
- twill 以外の sandbox (TS Next.js Hono モノレポ等) で tool-project から一気通貫テスト

### 3.2 起動形式 (**sandbox × feature matrix**)

```bash
/twl:tool-sandbox-runner \
  --sandbox=twill-self \
  --features=admin,pilot,worker \
  --collect-logs=all
```

### 3.3 sandbox catalog (場所)

**`plugins/twl/sandboxes/<name>/`** に manifest 配置:

```
plugins/twl/sandboxes/
├── twill-self/
│   ├── sandbox.yaml      # manifest (description, features サポート一覧)
│   ├── setup.sh          # orphan branch + worktree 作成
│   └── features.yaml     # feature 一覧と test 方法
├── ts-nextjs-hono-mono/
│   ├── sandbox.yaml
│   ├── setup.sh          # template apply + tool-project init
│   └── features.yaml
└── _shared/
    └── problem-patterns.yaml  # LLM 分析 pattern catalog
```

- feature catalog: deps.yaml v3.0 + skill discovery と **integrity check** で同期

### 3.4 twill-self sandbox の具体構造 (verified pattern 継承)

既存 `co-self-improve` の `test-target/main` orphan branch 方式を継承:

```bash
# setup-sandbox.sh
export TWL_SANDBOX_RUN_ID=$(date +%s)
export TWL_SANDBOX_DIR=worktrees/sandbox-${TWL_SANDBOX_RUN_ID}

git checkout --orphan test-target/main
cp -r test-fixtures/minimal-plugin .
git worktree add $TWL_SANDBOX_DIR test-target/main
```

**security**:
- `GH_TOKEN` = test-repo 専用 (main API へは read-only)
- PR 作成は test-repo のみ
- cleanup: `git worktree remove --force` + `git branch -D test-target/main`

### 3.5 log 収集 (env + run-id タグ)

**sandbox 内 Claude Code 起動**:
```bash
cd $TWL_SANDBOX_DIR
CLAUDE_PROJECT_DIR=$(pwd) claude --plugin-dir ./plugins/twl
# jsonl: ~/.claude/projects/$(encoded $(pwd))/*.jsonl
```

**tmux window 命名**: `sandbox-${RUN_ID}-admin` / `sandbox-${RUN_ID}-phase-impl-1660` etc

**収集 script** (`.sandbox-logs/<run-id>/` に集約):
```
~/.claude/projects/$(encoded $TWL_SANDBOX_DIR)/*.jsonl
tmux capture-pane -p -S -10000 -t sandbox-${RUN_ID}-*
$TWL_SANDBOX_DIR/.mailbox/*/inbox.jsonl
$TWL_SANDBOX_DIR/.audit/<run-id>/
```

### 3.6 LLM 分析 (**pattern catalog + freeform 両方**)

**`plugins/twl/sandboxes/_shared/problem-patterns.yaml`** (catalog):

```yaml
patterns:
  - id: stuck-loop
    description: 同一 step を N 回以上 retry
    severity: critical
  - id: mailbox-loss
    description: pilot が worker mail を N min 未受信
    severity: high
  - id: context-bloat
    description: token 使用率 > 80% で仕事未完了
    severity: medium
  - id: phase-gate-mistake
    severity: high
  - id: step-abort-cascade
    severity: critical
  - id: subagent-misuse
    severity: medium
```

**LLM output schema**:
```json
{
  "problems": [
    {
      "pattern_id": "stuck-loop",          // catalog match or null (freeform)
      "freeform_title": "...",
      "confidence": "high|medium|low",
      "impact_scope": "single-step|phase|system",
      "log_excerpt": "..."
    }
  ]
}
```

### 3.7 doobidoo 重複 check + Idea Issue 起票

**flow** (semantic search + similarity > 0.75 で link):

```
for each problem in LLM output:
  query = problem.title + problem.detail (first 200 chars)
  results = mcp__doobidoo__memory_search(query, mode=hybrid)
  if results[0].similarity > 0.75:
    # 重複 → Issue 起票しない、doobidoo hash を log
    log "重複: doobidoo $hash"
    continue
  else:
    # 新規 → Idea Issue 起票
    gh issue create \
      --title "[sandbox/$sandbox_name] $summary" \
      --label "discovered-by-sandbox-runner,bug|improvement,severity-$sev" \
      --body "$detail + log excerpt + sandbox run-id + doobidoo hash"
    mcp__doobidoo__memory_store new problem
```

**Issue 起票条件**: severity = **critical** のみ Idea Issue 起票、minor は doobidoo のみ。

### 3.8 failure recovery (wall-clock + budget 両方で timeout)

**timeout 条件**:
- wall-clock > 30 min (default、`--timeout=30m`)
- budget 5h % > 50

**timeout flow**:
```
1. log 収集 (kill 前に必ず実行)
2. tmux send-keys C-c (graceful stop 試行)
3. 5 min wait
4. 未終了 → tmux kill-window
5. cleanup (worktree remove + branch delete)
6. mailbox -> admin "sandbox-timeout" mail
7. AskUserQuestion: continue / abort
```

**implementation**: admin polling で sandbox window 存在 + duration check、budget は Inv Q format で解釈

---

## 4. tool-utility 廃止 (commands 再分配)

| 旧 command | 新配置 |
|---|---|
| size-check | tool-architect (spec 品質) / tool-project (プロジェクト品質) |
| lint | tool-architect / tool-project |
| worktree-list | administrator/SKILL.md inline |
| worktree-cleanup | administrator/SKILL.md inline |
| archive | **廃止** (git で十分) |
| spec-diagnose | tool-architect 統合 |
| (sandbox 関連) | tool-sandbox-runner |

---

## 5. 新規 EXP 追加 (本 dig 由来)

| EXP-id | 検証対象 | 担当 tool |
|---|---|---|
| EXP-019 | GitHub Project status field option 追加 (4 手段) | tool-project |
| EXP-020 | kanban col order 変更 (4 手段) | tool-project |
| EXP-021 | label add/remove (4 手段) | tool-project |
| EXP-022 | view switch (kanban/table) | tool-project |
| EXP-023 | filter / group-by 設定 | tool-project |
| EXP-024 | (将来) twl MCP custom tool 価値調査 | tool-project |
| EXP-025 | template apply + build smoke test | tool-project |
| EXP-026 | template idempotent (2 回 apply で同一 state) | tool-project |

加えて tool-architect verify 系の EXP も新規 (現 spec で言及済の EXP-001〜018 と並列):

| EXP-id | 検証対象 | 担当 |
|---|---|---|
| EXP-027 (新規候補) | verify-coverage.sh の 4-state grep が正しく未 verified を catch | tool-architect verify |
| EXP-028 (新規候補) | pre-tool-use-spec-write-boundary.sh が tool-architect / user 以外を deny | tool-architect verify |
| EXP-029 (新規候補) | worker-spec-review agent が 3 回 fix loop で収束 or escalate | tool-architect PR cycle |
| EXP-030 (新規候補) | sandbox-runner で twill-self sandbox の 1 cycle 動作 + log 収集 | tool-sandbox-runner |
| EXP-031 (新規候補) | doobidoo 重複 check (similarity > 0.75) の false positive/negative 率 | tool-sandbox-runner |

---

## 6. 新規 helper / file 追加 (本 dig 由来)

| file | 用途 | 規模 |
|---|---|---|
| `plugins/twl/scripts/lib/verify-coverage.sh` | tool-architect verify hook (層 2) | ~50 行 |
| `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` | spec edit 所有権 enforce | ~30 行 |
| `plugins/twl/agents/worker-spec-review.md` | tool-architect PR cycle review agent | ~100 行 (SKILL.md) |
| `plugins/twl/sandboxes/_shared/problem-patterns.yaml` | LLM 分析 pattern catalog | ~50 行 |
| `plugins/twl/sandboxes/<name>/sandbox.yaml` | sandbox manifest (per sandbox) | ~30 行 |
| `plugins/twl/sandboxes/<name>/setup.sh` | sandbox setup (per sandbox) | ~50 行 |
| `plugins/twl/sandboxes/<name>/features.yaml` | feature 一覧 (per sandbox) | ~50 行 |
| `cli/twl/src/twl/validation/project_setup.py` | `twl_validate_project_setup` MCP tool | ~80 行 |
| `shuu5/twill-templates` (別 git repo) | template repository | repo-level |

---

## 7. 削除対象 (本 dig 由来の追加)

| file / concept | 削除理由 |
|---|---|
| `plugins/twl/skills/co-utility/SKILL.md` (79 行) | tool-utility 廃止 |
| co-utility 関連 catalog / script | 同上 |
| (現 co-architect の architect-fixtures があれば) | tool-architect 統合 |

合計削減: tool-utility 79 行 + 関連 files

---

## 8. 残課題 (本 dig で扱わず、将来詰める)

### 詳細実装レベル
- `worker-spec-review` agent の正確な prompt (findings 出力形式)
- `verify-coverage.sh` の正確な grep regex + warn message format
- `pre-tool-use-spec-write-boundary.sh` の caller 識別ロジック (env 変数経由?)
- problem-patterns.yaml の各 pattern severity threshold 値
- template version migration の semver / breaking change handling

### 運用設計
- twill-templates 別 repo の管理者 / PR review policy
- sandbox 並列実行 (複数 sandbox 同時) の可否 + resource conflict
- sandbox-runner timeout の budget threshold 値 (50% 妥当か)

### tool-architect 追加検討
- recursive PR の review 委譲先 (user only? 他 tool? user/admin/他 tool の優先順位)
- spec file 削除 / file rename の handling (worker-spec-review で catch?)

### tool-project 追加検討
- cross-repo support (twill 外の repo に apply 可?)
- `migrate` sub-command の動作 (旧 version → 新 version の diff 反映)
- `snapshot` sub-command の動作 (現 state を新 template として抽出?)

### tool-sandbox-runner 追加検討
- sandbox 内 twill が更に sandbox-runner を呼ぶ recursive 制限
- features.yaml の sync method (実 SKILL.md 一覧との integrity check 自動化)

---

## 9. 関連 spec ファイル (未反映)

本 dig 結果を将来反映する spec file:

| spec file | 反映内容 |
|---|---|
| `tool-architecture.html` | 全面書き直し (4 tool → 3 tool、各 tool の 1.x〜3.x 詳細を埋め込み) |
| `experiment-index.html` | EXP-019〜031 追加 |
| `sandbox-experiment.html` | sandbox catalog の plugins/twl/sandboxes/ 確定、problem-patterns catalog 追加 |
| `deletion-inventory.html` | tool-utility 廃止 + 79 行削除 reference |
| `rebuild-plan.html` | Phase 1 PoC の ★ STEP 群に EXP-019〜031 を組込み |
| `boundary-matrix.html` | 4 entity (admin/pilot/worker/tool-*) を確定 (5 entity → 4 entity 整理) |
| `glossary.html` | tool-sandbox-runner / tool-utility 廃止 反映 |
| `README.html` | tool 一覧更新 (3 件構成) |
| `changelog.html` | 第 4 弾履歴 (本 dig 結果) |
| `ADR-043` (md) | tool 構成変更を Decision section に追記 |

---

## 10. dig 履歴 (transparency)

### Round 1 (A 軸: tool-* 存在意義 + 境界、4 question)
1. verify 強制レイヤー構造 → **機械 hook + SKILL.md MUST 2 層併用**
2. PR cycle 採否 → **採用、ただし軽量サイクル**
3. tool-self-improve rename + scope → **rename 「tool-sandbox-runner」 + sandbox×feature matrix**
4. tool-utility 存続 → **廃止 (3 tool 構成)**

### Round 2 (A 軸続き、4 question)
5. verify hook 実装 → **4-state class grep + EXP マークアップ、warn のみ**
6. PR cycle safety → **fix loop 3 回上限 + user approve は review PASS 後**
7. tool-project scope → **GitHub Project + template + verify の 3 軽**
8. sandbox-runner log + 起票 → **全層 log + LLM 分析 + doobidoo 重複 check + Idea 起票**

### Round 3 (A 軸完結、4 question)
9. spec edit 所有権 → **tool-architect + user 手動のみ**
10. tool-project idempotency → **default skip + verify diff 提示 + user 確認**
11. sandbox catalog 場所 → **plugins/twl/sandboxes/ directory + sandbox.yaml**
12. twill-self sandbox 構造 → **test-target/main orphan branch + dedicated worktree + read-only API**

### Round 4 (B 軸: tool-project 詳細、4 question)
13. GitHub write boundary 調査 → **5 領域全取調査 (EXP-019〜023)**
14. template stack + versioning → **stack 3 件 + git submodule versioning + apply test EXP**
15. template apply 安全性 → **dry-run default + file のみ add + rollback snapshot**
16. sub-command 設計 → **init 統合 sub-command + 他是別個コマンド**

### Round 5 (C 軸: tool-sandbox-runner 詳細、4 question)
17. LLM 分析 prompt 設計 → **pattern catalog + freeform 両方**
18. log 収集 path 解決 → **env 変数で sandbox dir 明示 + run-id タグ**
19. doobidoo 重複 check + Idea 起票 → **semantic search + similarity > 0.75 で link**
20. sandbox failure recovery → **wall-clock timeout + budget % 両方で timeout**

**全 20 question で「Recommended」選択肢が user 採用**。dig インタビュー完了。

---

## 11. 本 dig の core lesson

1. **tool-utility は不要だった**: 他 3 tool + admin inline で吸収可能、責務未分化が drift 原因
2. **tool-self-improve → tool-sandbox-runner rename**: "self-improve" は scope 不明確、"sandbox-runner" で意図明確化
3. **tool-architect は spec の唯一 author (recursive OK)**: spec edit 所有権を機械 enforce することで drift 防止
4. **PR cycle は spec にも適用価値あり**: worker-pr-cycle (8 specialist) は重すぎ、worker-spec-review 1 agent の軽量 cycle で十分
5. **2 層 verify (hook + SKILL.md MUST)**: LLM だけでも hook だけでも漏れる、両方必須
6. **sandbox catalog は plugin scope に置く**: plugin 化方針と整合、test-fixtures/experiments/ とは別配置
7. **既存 verified pattern を最大限継承**: `test-target/main` orphan branch + `session-atomic-write.sh` flock + `pre-tool-use-worktree-boundary.sh` の deny pattern を新 architecture に流用

---

## 12. 次のアクション選択肢

(A) 本 dig 結果を spec 本体に反映 (`tool-architecture.html` 全面書き直し + 他 9 file 更新 + ADR-043 追記、~1-2 session)

(B) tool-architect 先行実装 (本 dig の決定事項を実コードに落とす、Phase 1 PoC の前段)

(C) 残課題 (§8) を更に dig (詳細実装レベル、運用設計)

(D) 別軸を dig (例: administrator / phase-* / worker-* の詳細、step.sh framework 内部、boundary-matrix の admin 列詳細)

(E) Phase 1 PoC 着手 (★ STEP -1 hook 無効化済 → STEP 0 sandbox EXP → STEP 1 twl plugin 化 → 本 dig 結果を実装)
