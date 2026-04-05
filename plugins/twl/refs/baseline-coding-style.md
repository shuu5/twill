---
name: twl:baseline-coding-style
description: |
  コーディング基準。BAD/GOODコード対比パターン、ファイルサイズ制限、品質チェックリスト。
type: reference
disable-model-invocation: true
---

# Coding Style Baseline

レビュアーが参照するコーディング基準。BAD/GOODコード対比形式で具体的な判定基準を提供する。

## イミュータビリティ原則

- 変数は可能な限り `const` / `final` / immutable で宣言する
- 配列・オブジェクトの変更は新しいインスタンスを生成する（spread, map, filter）
- 関数は副作用を最小化し、引数を変更しない

### BAD: ミュータブルな状態操作

```typescript
// BAD: 配列を直接変更
function addItem(items: Item[], newItem: Item) {
  items.push(newItem);  // 引数を直接変更
  return items;
}

// BAD: let で宣言し再代入
let result = [];
for (const item of items) {
  if (item.active) {
    result.push(item);
  }
}
```

### GOOD: イミュータブルなパターン

```typescript
// GOOD: 新しい配列を返す
function addItem(items: Item[], newItem: Item): Item[] {
  return [...items, newItem];
}

// GOOD: 宣言的な変換
const result = items.filter(item => item.active);
```

## ファイルサイズ制限

| 指標 | 閾値 | アクション |
|------|------|-----------|
| ファイル行数 | > 300行 | Warning: 分割を検討 |
| ファイル行数 | > 500行 | Critical: 分割必須 |
| 関数行数 | > 50行 | Warning: 責務分割を検討 |
| 関数行数 | > 100行 | Critical: 分割必須 |
| 関数パラメータ数 | > 5 | Warning: オブジェクト引数に変更を検討 |
| ネストの深さ | > 3段 | Warning: 早期リターンで平坦化 |

## BAD/GOOD コード対比パターン

### 過大な関数

```typescript
// BAD: 1関数で複数の責務
async function processOrder(order: Order) {
  // バリデーション（20行）
  // 在庫チェック（15行）
  // 価格計算（25行）
  // DB保存（10行）
  // メール送信（15行）
  // ログ出力（5行）
}
```

```typescript
// GOOD: 責務ごとに分割
async function processOrder(order: Order) {
  validateOrder(order);
  await checkInventory(order.items);
  const total = calculateTotal(order);
  await saveOrder({ ...order, total });
  await sendConfirmation(order);
}
```

### 不適切な抽象化（早すぎる抽象化）

```typescript
// BAD: 1回しか使わないのにヘルパー化
function formatUserName(user: User): string {
  return `${user.firstName} ${user.lastName}`;
}
// 呼び出し箇所が1つだけ
const name = formatUserName(user);
```

```typescript
// GOOD: インラインで十分
const name = `${user.firstName} ${user.lastName}`;
```

### 深いネスト

```typescript
// BAD: ネストが深い
function process(data: Data) {
  if (data) {
    if (data.items) {
      for (const item of data.items) {
        if (item.active) {
          if (item.price > 0) {
            // 処理...
          }
        }
      }
    }
  }
}
```

```typescript
// GOOD: 早期リターンで平坦化
function process(data: Data) {
  if (!data?.items) return;

  const activeItems = data.items.filter(
    item => item.active && item.price > 0
  );

  for (const item of activeItems) {
    // 処理...
  }
}
```

### エラーハンドリングの過剰・不足

```typescript
// BAD: 内部コードに対する過剰なバリデーション
function calculateTotal(items: CartItem[]): number {
  if (!items) throw new Error("items is required");
  if (!Array.isArray(items)) throw new Error("items must be array");
  // 内部関数なのに外部入力レベルのバリデーション
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}
```

```typescript
// GOOD: 型システムを信頼、外部境界のみバリデーション
function calculateTotal(items: CartItem[]): number {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}
```

## Bash: 環境変数パース

`env | grep` でキー=値を読み込む全ての Bash スクリプトに適用。

### BAD: IFS='=' による分割（値内の = が切り捨てられる）

```bash
# BAD: 値に = を含む場合に切り捨て（DEV_URL=https://host?a=b → val="https://host?a" で b が消失）
while IFS='=' read -r key val; do
    ENV_ARGS+=(--setenv="${key}=${val}")
done < <(env | grep '^DEV_')
```

### GOOD: パラメータ展開で正確にパース

```bash
# GOOD: IFS= で行全体を読み、パラメータ展開で最初の = を基準に分割
while IFS= read -r line; do
    key="${line%%=*}"   # 最初の = より前
    val="${line#*=}"    # 最初の = より後ろ全部
    ENV_ARGS+=(--setenv="${key}=${val}")
done < <(env | grep '^DEV_')
```

## 品質チェックリスト

レビュー時に確認する項目:

- [ ] 命名が意図を表現しているか（略語・曖昧な名前を避ける）
- [ ] 同じロジックが3箇所以上重複していないか（DRY原則）
- [ ] 関数は単一の責務を持つか
- [ ] マジックナンバー/マジックストリングが定数化されているか
- [ ] エラーパスが適切に処理されているか
- [ ] リソース（ファイル、接続、ストリーム）が確実にクローズされるか
- [ ] 非同期処理で適切に await されているか（fire-and-forget の意図を確認）
