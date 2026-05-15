# spec-management-rules.md

tool-architect が `architecture/spec/` を管理する規律 ref doc。R-1〜R-9 + checklist + HTML template + CI gate 一覧。

[tool-architect SKILL.md](../SKILL.md) からの参照 doc。

## R-1: index 追加 MUST

新 file 追加時に `architecture/spec/README.html` の index table に entry を追加すること。

### rationale

- README は spec の entry point。新 file は必ず README から到達可能であること
- 浮いたページ (orphan) を作らない (R-3 と連携)
- 読み手 (人間 + 将来 tool-architect 自身) が新 file の存在を発見できる

### 違反例

- 新 file `spec/foo.html` を作成、README に何も追記せず PR → R-1 違反
- README の正しい section table に entry がない場合 (例: 補助 file を「実装」section に misplaced)

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

### 違反例

- 新 file を作成、README には追加したが graph に node なし → R-2 違反 (R-3 (orphan) チェックでは検出されないが、視覚 graph で見えない)

### 適用方法

1. graph の SVG 内 `<circle>` + `<text>` で新 node 追加 (適切な category 色)
2. 関連 file への edge `<line>` 追加
3. (R-9 関連) 将来 auto-gen 化されるまで手動 maintenance

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
2. 各 inbound link を更新 (削除 or 新 path への変更)
3. README + graph entry も同期更新 (R-1 + R-2)
4. 機械検証 (R-8) で broken 0 確認

## R-5: badge=outline merge 禁止

`<span class="badge todo">outline</span>` 状態の file を merge してはならない。content 化完了 (`<span class="badge done">done</span>`) 後に merge。

### rationale

- spec の品質保証
- outline 状態の file は読み手に誤解を与える

### 違反例

- `<span class="badge todo">outline</span>` のまま PR merge → R-5 違反

### 例外

- `<span class="badge archive">archive</span>` (rollback 用に保持) は OK
- `<span class="badge proposed">proposed</span>` (将来仕様) は OK
- `<span class="badge superseded">superseded</span>` (廃止予定) は OK

## R-6: HTML 以外は research/archive 限定

`architecture/spec/` 直下には HTML のみ。MD / 画像 / その他 file は `architecture/research/` または `architecture/archive/` に置く。

### rationale

- spec/ 直下 = 新 twill の純粋 HTML 仕様
- 調査レポート (MD) は research/、過去資産は archive/

### 違反例

- `architecture/spec/dig-report-2026-05-15.md` 作成 → R-6 違反、`architecture/research/` に置くべき

### 例外

- `architecture/spec/common.css` (spec 用 stylesheet) は OK
- 画像 (`*.png` 等) は spec/ 直下に置かない、必要なら `architecture/spec/images/` (将来) or research/

## R-7: caller marker MUST

`architecture/spec/` を Edit/Write/NotebookEdit する前に `export TWL_TOOL_CONTEXT=tool-architect`。編集後 `unset`。

### rationale

- spec edit author を機械的に limit (tool-architect 専任)
- 他 caller (phaser / admin / tool-project 等) からの誤編集を hook で deny
- env unset = user manual edit として allow (人間が直接編集する場合)

### 機械検証

`plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` が PreToolUse で発火、env unset (user manual) or `TWL_TOOL_CONTEXT=tool-architect` のみ allow、その他 (phaser-* / admin / 等) なら JSON `permissionDecision: deny` を返す。

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

`.github/workflows/spec-link-check.yml` が PR trigger で `python3 scripts/spec-anchor-link-check.py --check-orphan --output text` を実行、broken または orphan > 0 で exit 1 → PR block。

## R-9: architecture-graph 手動 maintenance (中期 auto-gen)

architecture-graph.html の node + edge は現状手動 maintenance。中期で auto-gen script 化を検討。

### rationale

- 手動 maintenance は drift risk あり (R-2 強制で軽減)
- 中期で `scripts/spec-graph-gen.py` (or 類) を整備して機械生成、PR で diff 検出

### 現状の制約

- 編集者は R-2 適用時に SVG 構造 (circle / text / line) を手動更新
- 漏れは Phase 6 review or PR review で検出

## file 操作 checklist

### 新規追加

- [ ] R-7: caller marker set (`export TWL_TOOL_CONTEXT=tool-architect`)
- [ ] R-6: 拡張子確認 (HTML のみ spec/ 直下)
- [ ] HTML template から起こす (本 doc 末尾参照)
- [ ] R-1: README.html index table に entry 追加
- [ ] R-2: architecture-graph.html に node + edge 追加
- [ ] R-3: ≥1 inbound link 確認 (`spec-anchor-link-check --check-orphan`)
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
- [ ] R-4: inbound link 全更新 (削除 or 新 link)
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
- [ ] R-4: inbound href 全更新 (相対 path で `../research/file.html` 等)
- [ ] R-1: README で section を移動 entry (例: 「F 補助」から削除して「research/ への参照」section に追加)
- [ ] R-2: graph で node の category 色を変更 (or 別 cluster へ移動)
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

## HTML template

新 spec file の standard template:

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

<nav class="breadcrumb">
  <a href="README.html">spec</a> &raquo; <a href="architecture-graph.html">graph</a> &raquo; <strong>{file-title}</strong>
</nav>

<header class="doc-header">
  <h1>{file-title}</h1>
  <div class="meta">draft-vN ({YYYY-MM-DD}) &middot; {short-description}</div>
</header>

<div class="info">
  <strong>目的</strong>: {file purpose} <br>
  <strong>status</strong>: {done / outline / proposed / archive / superseded} <br>
  <strong>関連</strong>: <a href="{related1}.html">{related1}</a> / <a href="{related2}.html">{related2}</a>
</div>

<h2 id="s1">セクション 1</h2>
<p>...</p>

<h2 id="s2">セクション 2</h2>
<p>...</p>

<footer>
  <p><a href="README.html">spec index に戻る</a></p>
</footer>

</body>
</html>
```

### badge convention

- `<span class="badge done">done</span>` — content 完成、merge 可
- `<span class="badge todo">outline</span>` — 骨格のみ、content 化要 (merge 不可、R-5)
- `<span class="badge archive">archive</span>` — rollback 用、廃止予定 not yet
- `<span class="badge proposed">proposed</span>` — 将来仕様、未確定
- `<span class="badge superseded">superseded</span>` — 廃止済、後継あり

## CI gate 一覧

| CI gate | tool | 強制 R |
|---|---|---|
| broken link 0 | `scripts/spec-anchor-link-check.py` (default mode) | R-8 (broken 部分) |
| orphan 0 | `scripts/spec-anchor-link-check.py --check-orphan` | R-3, R-8 (orphan 部分) |
| spec/ 配下 HTML のみ (R-6) | (future CI check) | R-6 |
| README entry 追加確認 (R-1) | PR review (現状)、(future grep check) | R-1 |
| graph node 追加確認 (R-2) | PR review (現状)、(future grep check) | R-2 |
| badge=outline 禁止 (R-5) | PR review、(future grep check) | R-5 |
| caller marker (R-7) | `pre-tool-use-spec-write-boundary.sh` (PreToolUse hook) | R-7 |

## 関連

- [tool-architect SKILL.md](../SKILL.md) (本 doc の親 SKILL)
- `architecture/spec/README.html` (spec index)
- `architecture/spec/architecture-graph.html` (link graph)
- `scripts/spec-anchor-link-check.py` (link integrity tool)
- `.github/workflows/spec-link-check.yml` (CI gate)
- `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` (caller marker hook)
