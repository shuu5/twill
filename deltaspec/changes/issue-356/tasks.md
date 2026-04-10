## 1. ディレクトリ移行

- [ ] 1.1 `plugins/twl/skills/co-observer/` ディレクトリを削除する
- [ ] 1.2 `plugins/twl/skills/su-observer/` ディレクトリを作成する

## 2. su-observer SKILL.md 作成

- [ ] 2.1 frontmatter を `type: supervisor`、`name: twl:su-observer`、`spawnable_by: [user]` で作成する
- [ ] 2.2 既存 co-observer の description と tools 設定を移行・更新する
- [ ] 2.3 Step 0 モード判定（supervise / delegate-test / retrospect）を定義する
- [ ] 2.4 Step 1 セッション起動・監視開始の基本構造を定義する
- [ ] 2.5 Step 2 controller spawn と観察の基本構造を定義する
- [ ] 2.6 Step 3 問題検出・3層介入プロトコル（intervention-catalog 継承）を定義する
- [ ] 2.7 Step 4〜7 をプレースホルダー（後続 Issue で詳細化）として定義する

## 3. deps.yaml 更新

- [ ] 3.1 `co-observer` キーを `su-observer` にリネームする
- [ ] 3.2 `path: skills/co-observer/SKILL.md` を `path: skills/su-observer/SKILL.md` に更新する
- [ ] 3.3 `type: supervisor` を設定する
- [ ] 3.4 `co-observer` を参照している他のエントリ（controller 定義等）を `su-observer` に更新する

## 4. 検証

- [ ] 4.1 `twl validate` を実行して PASS を確認する
- [ ] 4.2 `loom --check` で deps.yaml の整合性を確認する
