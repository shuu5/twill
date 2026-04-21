## ADDED Requirements

### Requirement: pitfalls-catalog §10 spawn prompt 最小化原則

`pitfalls-catalog.md` に §10「spawn prompt 最小化原則」を新設し、MUST NOT 表（7 項目以上）・MUST 5 項目・`--force-large` 例外・「observer own-read vs skill auto-fetch」境界補足を含まなければならない（SHALL）。

#### Scenario: §10 MUST NOT 表に必須 7 項目が存在する
- **WHEN** `pitfalls-catalog.md` を参照する
- **THEN** 以下 7 項目が MUST NOT 表に存在する: Issue body/labels/title、Issue comments、explore summary、architecture 文書、SKILL.md Phase 手順、past memory 生データ、bare repo/worktree 構造

#### Scenario: §10 MUST 5 項目が存在する
- **WHEN** `pitfalls-catalog.md` を参照する
- **THEN** 以下 5 項目が MUST 節に存在する: spawn 元識別、Issue 番号/成果物パス、proxy 対話期待、observer 独自 deep-dive 観点、Wave 文脈/並列タスク境界

#### Scenario: --force-large 例外が記述される
- **WHEN** `pitfalls-catalog.md` の §10 を参照する
- **THEN** `--force-large` option と prompt 冒頭 `REASON:` 行による例外が記述されている

#### Scenario: 境界補足が記述される
- **WHEN** `pitfalls-catalog.md` の §10 を参照する
- **THEN** 「observer が自分で取得した情報であっても spawn 先 skill が同じ操作で取得できる場合は転記禁止」という境界補足が記述されている

## MODIFIED Requirements

### Requirement: pitfalls-catalog §3.5 の改訂

`pitfalls-catalog.md` §3.5 の「元指示・背景・決定事項・判断基準・deep-dive ポイントを**全て** prompt に包含」が「**observer 固有文脈のみ**を包含（§10 参照、自律取得可能情報は MUST NOT）」に改訂されなければならない（MUST）。

#### Scenario: §3.5 に §10 への参照が含まれる
- **WHEN** `pitfalls-catalog.md` §3.5 を参照する
- **THEN** 「§10 参照」という記述が含まれ、「全て prompt に包含」という表現が削除されている
