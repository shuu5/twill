## Context

su-observer は ADR-014 で定義された「プロジェクト常駐のメタ認知レイヤー」であり、supervision.md の設計に従う。現行 SKILL.md はモード分離パターン（supervise / delegate-test / retrospect の 3 モード）を採用しており、LLM が文脈から自然に判断する機会を奪っている。su-observer-skill-design.md も 6 モードのルーティングテーブルを持ち、SKILL.md の「正典」として機能しているため、設計ドキュメント自体のモード前提も廃止が必要。

session plugin スクリプト群（cld-spawn, cld-observe, cld-observe-loop, session-state.sh, session-comm.sh）は既存実装を活用する。

## Goals / Non-Goals

**Goals:**

- su-observer SKILL.md をモードテーブルなしの常駐セッションマネージャー型に再設計
- 全 controller の起動を `session:spawn`（`cld-spawn`）経由に統一
- su-observer-skill-design.md のモードルーティングテーブルを行動判断ガイドラインに置換
- co-self-improve SKILL.md に spawn 受取手順を追加
- deps.yaml の su-observer.supervises に co-self-improve を追加
- SU-1〜SU-7 制約を全て維持

**Non-Goals:**

- ADR-014 自体の変更
- session plugin スクリプト群（cld-spawn 等）の変更
- compaction / 知識外部化ロジックの変更
- SU-* 制約の変更
- co-self-improve の内部モード判定（scenario-run/retrospect/test-project-manage）の変更

## Decisions

### D1: SKILL.md の構造を 3 ステップに簡素化

Step 0（セッション初期化）→ Step 1（常駐ループ）→ Step 2（セッション終了）の 3 段構造に再設計する。Step 1 では「モード」という概念を使わず、LLM がユーザー入力を文脈から解釈して適切なアクション（spawn / observe / intervene / report / compact）を選択する。

**理由**: モードテーブルは LLM の状況判断力を制限し、予期しない入力に対して AskUserQuestion を強制するパターンを生み出す。

### D2: controller spawn を session plugin スクリプト経由に統一

全 controller（co-autopilot, co-issue, co-architect, co-project, co-utility, co-self-improve）の起動を `cld-spawn` 経由で統一する。co-autopilot のみ `cld-observe-loop` による能動 observe を行い、他 controller は `cld-observe`（単発）または指示待ちに戻る。

**理由**: 既存 SKILL.md では `Skill(twl:co-self-improve)` 直接呼出しが混在しており、観察ループなしの起動になっている。spawn 統一により SupervisedController の状態管理が一貫する。

### D3: su-observer-skill-design.md の役割を変更

「SKILL.md の正典」から「行動判断ガイドライン（参照ドキュメント）」に役割を変更する。6 モードのルーティングテーブルを削除し、「どのような文脈でどの行動が適切か」を記述する判断ガイドラインに置換する。

### D4: co-self-improve に spawn 受取手順を追加

co-self-improve SKILL.md の冒頭に「su-observer から spawn される場合の情報受取手順」を追加する。spawn 時プロンプトから対象 session、タスク内容、観察モードを受け取り、以降の動作に反映する。co-self-improve 自身の内部モード判定はスコープ外。

## Risks / Trade-offs

- **後方互換**: su-observer 未起動時は controller が独立動作するため、本変更による後方互換性への影響は最小（supervision.md のフォールバックパス仕様維持）
- **モード廃止の副作用**: 明示的なモード選択がなくなることで LLM が不適切なアクションを選ぶリスクがあるが、行動判断ガイドラインで十分なコンテキストを提供することで緩和
- **設計ドキュメントの乖離**: SKILL.md と設計ドキュメントを同時に変更することで一時的に乖離が生じる可能性があるが、同一 PR でのアトミック変更により防止
