---
name: dev:ref-investigation-budget
description: |
  Issue 品質レビュー specialist（issue-critic, issue-feasibility）が使用する調査バジェット制御ルール。
  maxTurns 制限下での調査深度制御と出力優先ルールを定義。
type: reference
---

## 調査バジェット制御（MUST）

maxTurns が限られているため、調査の深さを制御すること。

- scope_files（`<target_files>` タグ）が **3 ファイル以上**の場合:
  - 各ファイルの調査は **最大 2-3 tool calls** に制限する（ファイル存在確認 + 直接の呼び出し元 1 段のみ）
  - 再帰追跡禁止（呼び出し元の呼び出し元を辿らない）
- 参照ファイルを全件確認した後、または残り turns が少なくなった場合（turns 3 以下が目安）は調査を打ち切り、出力生成を優先する
