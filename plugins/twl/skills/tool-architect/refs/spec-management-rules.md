# spec-management-rules.md

tool-architect が `architecture/spec/` を管理する規律 ref doc。R-1〜R-9 + checklist + HTML template + CI gate 一覧。

[tool-architect SKILL.md](../SKILL.md) からの参照 doc。

## 重要 note (transient)

本 doc は新 dir 構造 (`architecture/spec/` を spec SSoT として flat 化) を前提として記述している。本 doc 作成時点では旧 sub-dir 構造 (`architecture/spec/twill-plugin-rebuild/`) が active であり、後続作業で flat 化される。

flat 化完了まで、本 doc の `architecture/spec/<file>.html` という path 記述は実体的に `architecture/spec/twill-plugin-rebuild/<file>.html` を指す。本 note は flat 化完了時点で削除される。

## R-1: index 追加 MUST

新 file 追加時に `architecture/spec/README.html` の index table に entry を追加すること。

### rationale
- README は spec の entry point。新 file は必ず README から到達可能であること
- 浮いたページ (orphan) を作らない (R-3 と連携)
- 読み手 (人間 + 将来 tool-architect 自身) が新 file の存在を発見できる

### 違反例
- 新 file `spec/foo.html` を作成、README に何も追記せず PR → R-1 違反
- 補助 file (例: changelog.html、本来 section F) を「新 architecture」section (C) の table に置く → 不適切 placement

### 適用方法
1. 新 file の category 判断 (A 全体把握 / B 既存資産継承 / C 新 architecture / D 既存接続 / E 削除移行 / F 補助 / G 拡張 等)
2. 該当 section の table に `<tr><td><a href="foo.html"><code>foo.html</code></a></td><td><span class="badge ...">status</span></td><td>説明</td></tr>` を追加
3. badge 選択: done / outline / archive / proposed / superseded のいずれか

## R-2: architecture-graph 追加 MUST

新 file 追加時に `architecture/spec/architecture-graph.html` に node + edge を追加すること。

### rationale
- architecture-graph は spec の link 関係を可視化する hub
- 新 file が他 file との関係性を持つことを明示
- リファクタリング時に影響範囲を把握しやすくする
- **graph 内 `<a xlink:href>` は inbound link としてカウントされるため、R-2 適用は R-3 (orphan 禁止) の機械的保証の一翼を担う**

### 違反例
- 新 file を作成、README には追加したが graph に node なし → R-2 違反
- node label が file 名と不一致 → click navigation 後に混乱

### 適用方法

実 graph 構造 (`architecture/spec/architecture-graph.html`) は以下 pattern を使用する。実例は graph file 内 node section + edge section を参照のこと。

```html
<!-- 該当 category 列に node 追加 -->
<a xlink:href="foo.html">
  <title>foo.html — short desc</title>
  <g class="node">
    <circle class="cat-{a|b|c|d|e|f|g}" cx="{col-x}" cy="{次の row-y}" r="22" />
    <text x="{col-x}" y="{cy+3}">label (短縮形)</text>
  </g>
</a>

<!-- 関連 file への edge -->
<line class="edge" x1="..." y1="..." x2="..." y2="..." />
<!-- hub 強調が必要なら class="edge hub" -->
```

## R-3: orphan 禁止 (inbound link ≥1)

新 file は少なくとも 1 つの inbound link を持つこと。entry point (README.html) は除外。

### rationale
- 浮いたページは存在を発見できない、リファクタリング時に取り残される
- spec の連結性を機械的に保証

### 違反例
- 新 file 作成、どこからも link されていない → R-3 違反

### 機械検証

`python3 scripts/spec-anchor-link-check.py --check-orphan --output text`

orphan 検出時は exit 1。

### 機械検証の limitation
- 検証 scope: spec_dir 内 (現 `architecture/spec/twill-plugin-rebuild/`) の file 間 link のみ
- 外部 dir (`research/`, `archive/` 等) からの inbound link は spec_dir 内 file としては自動カウントされない
- `external_relative` (`../research/foo.html`) は spec_dir 外を指すため inbound カウント対象外
- `./foo.html` (same-dir relative) は cross_file_html として inbound カウント対象 (Phase 1B fix)
- spec_dir 外 file の orphan は本 check の scope 外

### entry point の扱い
- `README.html` は spec entry point として inbound 0 で OK (`--entry-points README.html` で default 除外)
- 他 entry を追加する場合 `--entry-points README.html,other.html` で comma-separated

## R-4: 削除/rename 時の link 全更新 MUST

file を削除または rename する際、その file への inbound link をすべて更新すること。

### rationale
- broken link 0 の維持 (CI gate R-8 と連携)
- リファクタリング時に取り残し防止

### 違反例
- `foo.html` を削除、他 file からの `<a href="foo.html">` が残存 → broken link 検出 (CI fail)

### 適用方法
1. `grep -r "foo.html" architecture/spec/` で inbound 全特定
2. 削除の場合: 各 inbound link を削除 (他 file から `<a>` タグ削除) または後継 file への redirect 化
3. rename の場合: 各 inbound href を新 path に更新
4. README + graph entry も同期更新 (R-1 + R-2)
5. 機械検証 (R-8) で broken 0 確認

## R-5: badge=outline merge 禁止

`<span class="badge todo">outline</span>` 状態の file を merge してはならない。content 化完了 (`<span class="badge done">done</span>`) 後に merge。

### rationale
- spec の品質保証
- outline 状態 (骨格のみ、決定事項を欠く) の file は読み手に誤解を与える

### 違反例
- `<span class="badge todo">outline</span>` のまま PR merge → R-5 違反

### badge 識別基準 (merge 可否の根拠)
- `<span class="badge done">done</span>`: content 完成、決定済、merge 可
- `<span class="badge todo">outline</span>`: 骨格のみ、決定事項を欠く (merge 不可、R-5)
- `<span class="badge archive">archive</span>`: 過去仕様、rollback 用に保持 (廃止予定 not yet) — merge 可 (内容は完成、現役でないだけ)
- `<span class="badge proposed">proposed</span>`: 将来仕様、内容は完成しているが採用未確定 — merge 可 (内容は決定済、status のみ pending)
- `<span class="badge superseded">superseded</span>`: 廃止済、後継あり、参照のみ可 — merge 可

「outline」は「内容未完成」、「proposed / archive / superseded」は「内容完成 + status 区別」。merge 可否は内容完成度で決まる。

## R-6: HTML 以外は research/archive 限定

`architecture/spec/` 配下には HTML のみ。MD / 画像 / その他 file は `architecture/research/` または `architecture/archive/` に置く。

### rationale
- spec/ 配下 = 新 twill の純粋 HTML 仕様
- 調査レポート (MD) は research/、過去資産は archive/

### 違反例
- `architecture/spec/dig-report-2026-05-15.md` 作成 → R-6 違反、`architecture/research/` に置くべき

### 例外
- `architecture/spec/common.css` (spec 用 stylesheet) は OK
- 画像 file は spec/ 配下に置かない、必要なら research/ 等の別 dir に
- 既存 dig-report MD (`dig-report-*.md`) は現 spec_dir 内に共存しているが、後続作業で `architecture/research/` に move 予定 (transient state)

## R-7: caller marker MUST

`architecture/spec/` 配下 (sub-dir 全 nest 含む) を Edit/Write/NotebookEdit する前に `export TWL_TOOL_CONTEXT=tool-architect`。編集後 `unset`。

### rationale
- spec edit author を機械的に limit (tool-architect 専任)
- 他 caller (phaser / admin / tool-project 等) からの誤編集を hook で deny
- env unset = user manual edit として allow (人間が直接編集する場合)
- **unset し忘れによる leak risk**:
  - 同 shell で後続 spawn される他 caller が `tool-architect` 扱いで spec を誤編集
  - sub-process は env を継承するため、unset しないと sub-shell 経由でも leak

### 機械検証
`plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` が PreToolUse で発火、env unset (user manual) or `TWL_TOOL_CONTEXT=tool-architect` のみ allow、その他 (phaser-* / admin / 等) なら JSON `permissionDecision: deny` を返す。**hook の path match は `*architecture/spec/*` で sub-dir 全 nest を包含**。

### 適用方法
```bash
export TWL_TOOL_CONTEXT=tool-architect
# (Edit/Write spec file 群)
unset TWL_TOOL_CONTEXT
```

## R-8: PR broken link 0 + orphan 0 MUST

PR merge gate として CI で broken link 0 + orphan 0 を強制。

### rationale
- spec の整合性 invariant を maintain
- ローカル開発で見逃しても CI で確実に block

### 機械検証
`.github/workflows/spec-link-check.yml` が PR trigger で `python3 scripts/spec-anchor-link-check.py --check-orphan --output json` を実行 (JSON parse で堅牢化)、broken または orphan > 0 で exit 1 → PR block。

CI trigger paths: `architecture/spec/**` / `scripts/spec-anchor-link-check.py` / `.github/workflows/spec-link-check.yml` 自身 (script 改修も CI 自検対象)。

## R-9: architecture-graph 手動 maintenance

architecture-graph.html の node + edge は手動 maintenance。

### rationale
- 手動 maintenance は drift risk あり (R-2 強制で軽減)
- 典型的な drift パターン:
  - 新 file 追加時に graph node 追加忘れ → graph で表示されない
  - file rename 後 graph label 更新忘れ → click navigation で 404
  - file 削除後 edge 削除忘れ → broken link 表示

### 現状の制約
- 編集者は R-2 適用時に SVG 構造 (上記 R-2 適用方法参照) を手動更新
- 漏れは PR review or CI gate (broken link 0 / orphan 0) で検出

## file 操作 checklist

### 新規追加
- [ ] R-7: caller marker set (`export TWL_TOOL_CONTEXT=tool-architect`)
- [ ] R-6: 拡張子確認 (HTML のみ spec/ 配下、common.css 例外)
- [ ] HTML template から起こす (本 doc 末尾参照)
- [ ] R-1: README.html index table に entry 追加
- [ ] R-2: architecture-graph.html に node + edge 追加 (R-3 にも貢献)
- [ ] R-5: badge 適切 (done / proposed / etc.)
- [ ] 機械検証 (`spec-anchor-link-check --check-orphan`): broken 0 + orphan 0
- [ ] caller marker unset (`unset TWL_TOOL_CONTEXT`)
- [ ] commit + push

### 編集
- [ ] R-7: caller marker set
- [ ] 内容変更
- [ ] (badge 変更時) R-5 確認
- [ ] (link 変更時) R-4 確認
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

### 削除
- [ ] R-7: caller marker set
- [ ] R-4: inbound link 全特定 (`grep -r "file.html" architecture/spec/`)
- [ ] R-4: inbound link 全更新 (link の削除 or 後継 file への redirect)
- [ ] R-1: README から entry 削除
- [ ] R-2: graph から node + edge 削除
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

### rename
- [ ] R-7: caller marker set
- [ ] `git mv old.html new.html`
- [ ] R-4: inbound href 全更新
- [ ] R-1: README entry の path 更新
- [ ] R-2: graph node + edge 更新
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

### move (dir 間、例: spec/ → research/)
- [ ] R-7: caller marker set (spec/ 外の dir なら不要、ただし spec/ 関連 link 更新があるなら必要)
- [ ] R-6: 移動先 dir の妥当性確認 (HTML/MD の区別)
- [ ] `git mv`
- [ ] R-4: inbound href 全更新 (相対 path `../research/file.html` 等)
- [ ] R-1: README で section を移動 entry
- [ ] R-2: graph で node の category 色を変更 (or 別 cluster へ移動)
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

## HTML template

新 spec file の standard template (実 spec file 構造に合わせて簡潔化):

```html
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>twill plugin spec — {file-name}</title>
<link rel="stylesheet" href="common.css">
<style>
  /* file-specific accent (optional) */
  header.doc-header { border-bottom: 3px solid var(--brand); }
</style>
</head>
<body>

<header class="doc-header">
  <h1>{file-title}</h1>
  <div class="meta">draft-vN ({YYYY-MM-DD}) &middot; {short-description}</div>
</header>

<div class="info">
  <strong>目的</strong>: {file purpose} <br>
  <strong>status</strong>: <span class="badge done">done</span> (または outline / proposed / archive / superseded) <br>
  <strong>関連</strong>: <a href="{related1}.html">{related1}</a> / <a href="{related2}.html">{related2}</a>
</div>

<h2 id="s1">セクション 1</h2>
<p>...</p>

<h2 id="s2">セクション 2</h2>
<p>...</p>

</body>
</html>
```

### badge convention
R-5 の「badge 識別基準」section 参照。

## CI gate 一覧

### 実装済み CI gate (機械的強制)

| CI gate | tool | 強制 R |
|---|---|---|
| broken link 0 | `scripts/spec-anchor-link-check.py` (default mode) | R-8 (broken 部分), R-4 |
| orphan 0 | `scripts/spec-anchor-link-check.py --check-orphan` | R-3, R-8 (orphan 部分) |
| caller marker enforce | `pre-tool-use-spec-write-boundary.sh` (PreToolUse hook) | R-7 |

### PR review 依存 (機械化されていない、reviewer 目視)

| Gate | 強制 R | 検出方法 |
|---|---|---|
| README entry 追加確認 | R-1 | reviewer 目視 |
| graph node 追加確認 | R-2 | reviewer 目視 |
| badge=outline merge 禁止 | R-5 | reviewer 目視 |
| HTML/MD 配置 boundary | R-6 | reviewer 目視 |

## 関連

- [tool-architect SKILL.md](../SKILL.md) (本 doc の親 SKILL)
- `architecture/spec/README.html` (spec index、R-1 強制 target)
- `architecture/spec/architecture-graph.html` (link graph、R-2 強制 target)
- `scripts/spec-anchor-link-check.py` (link integrity tool、R-3 / R-8 機械検証)
- `.github/workflows/spec-link-check.yml` (CI gate、R-8 強制)
- `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` (caller marker hook、R-7 強制)
