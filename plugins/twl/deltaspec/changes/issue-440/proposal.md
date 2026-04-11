## Why

su-observer は「ユーザーと controller の間に入るセッションマネージャー」であるべきだが、現行の SKILL.md と設計ドキュメントが「モード分離」パターンを採用しており、LLM の状況判断力を制限している。モード前提の設計を廃止し、常駐セッションマネージャー型に再設計することで、自然な対話と文脈判断を実現する。

## What Changes

- su-observer SKILL.md の全面書き換え（モード分離廃止 → 常駐セッションマネージャー型、全 controller を session:spawn 経由で起動）
- su-observer-skill-design.md のモード分離廃止（6 モードのルーティングテーブル → 行動判断ガイドライン）
- supervision.md のワークフロー図から「モード」という単語を削除（分岐ラベルは文脈判断の例示として維持）
- co-self-improve SKILL.md の spawn 前提修正（Skill() 直接呼出し → spawn される側の設計追加）
- deps.yaml: su-observer.supervises に co-self-improve を追加

## Capabilities

### New Capabilities

- su-observer がモードテーブルなしでユーザー入力を LLM が文脈から解釈し適切なアクションを選択（controller spawn / observe / intervene / report / compact）
- 全 controller（co-autopilot, co-issue, co-architect, co-project, co-utility, co-self-improve）が `session:spawn`（`cld-spawn`）経由で統一起動
- co-autopilot のみ `cld-observe-loop` による能動 observe、他 controller は `cld-observe`（単発）または指示待ち
- co-self-improve が spawn される側として spawn 時プロンプトからの情報受取手順を持つ

### Modified Capabilities

- su-observer SKILL.md: Step 0 初期化 → Step 1 常駐ループ → Step 2 終了 の構造に簡素化
- su-observer-skill-design.md: Step 構造を SKILL.md に合わせて簡素化（6 モード → 3 ステップ + 行動判断ガイドライン）
- AskUserQuestion でのモード強制選択を廃止（LLM が文脈から判断）

## Impact

- **plugins/twl/skills/su-observer/SKILL.md**: 全面書き換え
- **plugins/twl/architecture/designs/su-observer-skill-design.md**: モードルーティングテーブル削除 + 行動判断ガイドライン追加
- **plugins/twl/architecture/domain/contexts/supervision.md**: ワークフロー図の「モード」言及削除（軽微）
- **plugins/twl/skills/co-self-improve/SKILL.md**: Skill() 直接呼出し削除 + spawn 受取手順追加
- **plugins/twl/deps.yaml**: su-observer.supervises に co-self-improve 追加
