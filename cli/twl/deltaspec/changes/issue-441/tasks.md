## 1. supervision.md 修正

- [ ] 1.1 常駐ループ mermaid 図に co-self-improve / co-utility / co-project への spawn パスを追加
- [ ] 1.2 L226 の委譲記述に「session:spawn 経由」を追加
- [ ] 1.3 co-autopilot のみ能動 observe、他は spawn 後即指示待ちであることを追記

## 2. observation.md 修正

- [ ] 2.1 Observe ループ mermaid の最初のノードを「su-observer: session:spawn で co-self-improve を起動」に変更

## 3. context-map.md 修正

- [ ] 3.1 mermaid 図の SOBS → OBS エッジラベルを「session:spawn → observe」に変更
- [ ] 3.2 「関係の詳細」テーブルの Supervision → Live Observation 行を更新

## 4. model.md 修正

- [ ] 4.1 Supervisor クラスの `type: observer` を `type: supervisor` に修正

## 5. 検証

- [ ] 5.1 変更した mermaid 記法の構文確認（必要なら `mmdc` で確認）
- [ ] 5.2 受け入れ基準 6 件の全充足を確認
