---
name: twl:baseline-input-validation
description: |
  入力検証パターン。バリデーション設計原則とZod/Pydanticの推奨パターン。
type: reference
disable-model-invocation: true
---

# Input Validation Baseline

レビュアーが参照する入力検証パターン。バリデーション設計原則とZod/Pydanticの推奨パターンを提供する。

## バリデーション設計原則

### 1. 外部境界でバリデーション必須

システム境界（APIエンドポイント、フォーム入力、外部APIレスポンス、ファイル読み込み）では必ずバリデーションを行う。

### 2. 内部コードでの再バリデーション不要

型システムで保証された値を内部関数で再検証しない。外部境界でバリデーション済みの型付きデータを信頼する。

### 3. エラーメッセージの情報漏洩防止

- ユーザー向け: フィールド名と期待される形式のみ（例: "メールアドレスの形式が正しくありません"）
- ログ向け: 詳細な検証失敗情報（実際の入力値は機密データの場合マスキング）

### 4. Parse, Don't Validate

入力を「検証してから使う」ではなく「パースして型付きデータに変換する」。変換後は型が保証する。

## Zod パターン

### 基本スキーマ定義

```typescript
// GOOD: スキーマ定義と型推論を統合
const UserSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
});

type User = z.infer<typeof UserSchema>;
```

### transform: 入力の正規化

```typescript
// GOOD: バリデーションと変換を一体化
const EmailSchema = z.string()
  .email()
  .transform(email => email.toLowerCase().trim());

const DateSchema = z.string()
  .datetime()
  .transform(str => new Date(str));
```

### refine: カスタムバリデーション

```typescript
// GOOD: ビジネスロジックのバリデーション
const DateRangeSchema = z.object({
  startDate: z.date(),
  endDate: z.date(),
}).refine(
  data => data.endDate > data.startDate,
  { message: "終了日は開始日より後である必要があります", path: ["endDate"] }
);
```

### エラーハンドリング

```typescript
// GOOD: safeParse でエラーを制御
const result = UserSchema.safeParse(input);
if (!result.success) {
  const errors = result.error.flatten().fieldErrors;
  return { errors };
}
const user: User = result.data;  // 型安全
```

### BAD パターン

```typescript
// BAD: any型にキャストして手動バリデーション
const data = req.body as any;
if (!data.name || typeof data.name !== 'string') {
  throw new Error('invalid name');
}

// BAD: parse を try-catch なしで使用（エラーが ZodError として throw）
const user = UserSchema.parse(untrustedInput);  // API境界ではsafeParseを推奨
```

## Pydantic v2 パターン

### BaseModel 定義

```python
# GOOD: Pydantic v2 の BaseModel
from pydantic import BaseModel, Field, ConfigDict

class User(BaseModel):
    model_config = ConfigDict(strict=True)

    name: str = Field(min_length=1, max_length=100)
    email: str = Field(pattern=r'^[\w.+-]+@[\w-]+\.[\w.]+$')
    age: int = Field(ge=0, le=150)
```

### field_validator: フィールド単位の検証

```python
# GOOD: フィールドバリデーター
from pydantic import field_validator

class User(BaseModel):
    email: str

    @field_validator('email')
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.lower().strip()
```

### model_validator: モデル全体の検証

```python
# GOOD: モデルレベルの相関バリデーション
from pydantic import model_validator

class DateRange(BaseModel):
    start_date: date
    end_date: date

    @model_validator(mode='after')
    def check_date_order(self) -> 'DateRange':
        if self.end_date <= self.start_date:
            raise ValueError('終了日は開始日より後である必要があります')
        return self
```

### ConfigDict: モデル設定

```python
# GOOD: strict モードで暗黙の型変換を防止
class StrictUser(BaseModel):
    model_config = ConfigDict(
        strict=True,           # 暗黙の型変換を禁止
        frozen=True,           # イミュータブル
        extra='forbid',        # 未知フィールドを禁止
    )
    name: str
    age: int
```

### BAD パターン

```python
# BAD: 手動バリデーション
def create_user(data: dict):
    if 'name' not in data:
        raise ValueError('name required')
    if not isinstance(data['name'], str):
        raise ValueError('name must be str')
    # ... 延々とバリデーション

# BAD: Pydantic v1 スタイル（v2では非推奨）
class User(BaseModel):
    class Config:  # v2 では ConfigDict を使用
        orm_mode = True  # v2 では from_attributes = True
```
