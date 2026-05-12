# dual-stack-routing — placeholder

**status**: placeholder (本 session 未実装、次 session で着手予定)

> 本 file は `twill-plugin-rebuild` spec の placeholder。次 session で Phase 2 dual-stack 期間中の Issue routing ルールを実装する。

## 目的

新 phase-* architecture と旧 chain-runner.sh が併存する Phase 2 期間中、各 Issue がどちらの flow で処理されるかの判定基準と routing 機構を仕様化する。移行完了 (Phase 3 cutover) 判定基準も明示。

## 想定 outline (次 session で実装)

1. **routing 判定の SSoT**
   - Issue label (`stack:new` or `stack:legacy`) を SSoT として運用
   - default: 新規 Issue は `stack:new`、in-flight Issue は `stack:legacy` 維持

2. **routing flow**
   - administrator polling が Issue を検知 → label を確認 → 新 stack なら phase-* spawn、旧 stack なら旧 co-autopilot 経由
   - 共存中は両 stack の administrator (su-observer 旧 / administrator 新) が並列稼働
   - tmux window で stack 別 prefix (`phase-*` / `co-*`)、cross-stack mail 禁止

3. **migration 経路 (旧 → 新)**
   - in-flight Issue を新 stack に移行する手順 (status SSoT は GitHub 側で同じ、mail / state は新 stack 用に再初期化)
   - 移行 cost (1 Issue あたり手動作業 ~10 min) と自動化可否

4. **Phase 2 期間中の制約**
   - 新規 Issue は新 stack 必須 (label `stack:new` を default 化)
   - 旧 stack は freeze (新規修正禁止、bug fix 以外の改修 PR を block)
   - 両 stack の bats test を CI で並列実行

5. **Phase 3 cutover 判定基準**
   - 旧 stack の in-flight Issue が全て Merged or 新 stack 移行完了
   - 新 stack で 10+ Issue が安定完遂
   - bats regression 全 PASS (新 + 旧)
   - user 承認 (Phase 3 cutover は user 明示承認必須)

6. **cutover 後の cleanup**
   - 旧 stack file 削除 (deletion-inventory.md に従う)
   - `stack:` label を全 Issue から削除
   - administrator (旧 su-observer rebrand) のみ稼働、co-* は archive

## 参照

- `rebuild-plan.md` Phase 2-3
- `deletion-inventory.md` Phase 3 削除対象
- 既存 ADR-024 (refined を label から Status field へ移行) の dual-stack 経験
