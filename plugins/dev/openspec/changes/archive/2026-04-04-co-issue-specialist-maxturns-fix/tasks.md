## 1. issue-critic.md 調査バジェット制御追加

- [ ] 1.1 `agents/issue-critic.md` を読み込み、現在の構造を確認する
- [ ] 1.2 scope_files >= 3 の場合の調査制限ルール（各ファイル最大 2-3 tool calls、再帰追跡禁止）を追加する
- [ ] 1.3 残り turns <= 3 になったら調査打ち切り・出力生成優先の指示を追加する

## 2. issue-feasibility.md 調査バジェット制御追加

- [ ] 2.1 `agents/issue-feasibility.md` を読み込み、現在の構造を確認する
- [ ] 2.2 scope_files >= 3 の場合の調査制限ルール（各ファイル最大 2-3 tool calls、再帰追跡禁止）を追加する
- [ ] 2.3 残り turns <= 3 になったら調査打ち切り・出力生成優先の指示を追加する

## 3. co-issue SKILL.md Phase 3b 調査深度指示注入

- [ ] 3.1 `skills/co-issue/SKILL.md` を読み込み、Phase 3b の specialist spawn 箇所を特定する
- [ ] 3.2 scope_files 数に応じた depth_instruction 擬似コード（<= 2: 追跡可 / >= 3: 存在確認+直接参照のみ）をプロンプトに追加する

## 4. co-issue SKILL.md Step 3c 出力なし完了の検知

- [ ] 4.1 Step 3c の specialist 出力集約箇所を特定する
- [ ] 4.2 `status:` または `findings:` キーワードがない場合を「出力なし完了」と判定するロジックを追加する
- [ ] 4.3 WARNING として findings テーブルに表示する記述を追加する（Phase 4 非ブロック）
- [ ] 4.4 出力なし検知（上位ガード）と `ref-specialist-output-schema.md` パース失敗フォールバック（下位ガード）の役割分担を Step 3c に明記する
