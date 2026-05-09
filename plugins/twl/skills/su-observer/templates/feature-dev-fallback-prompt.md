# feature-dev Fallback Prompt Template

このテンプレートは co-autopilot 失敗時の feature-dev fallback spawn で使用する。
`feature-dev-fallback-detect.sh` がトリガーを検知し、ユーザーが Layer 2 Escalate を承認した後に使用する。

---

## (a) Refined Issue Body

```
<!-- ここに refined Issue body を貼り付ける -->
<!-- gh issue view <N> でコピーし、最新の refinement 内容を含めること -->
Issue #<N>: <title>

## 概要
<issue body>

## AC
<acceptance criteria>
```

## (b) co-autopilot 失敗経緯

```
<!-- ここに co-autopilot の失敗経緯を記載する -->
トリガー: <red-only-merge | needs-work-x3 | chain-failure-x3 | p0-emergency>
失敗した PR: #<PR番号>（<失敗の内容: RED-only / NEEDS_WORK / chain failure>）
Pilot 判断: <なぜ feature-dev fallback を選択したか>
```

## (c) Acceptance Criteria (AC)

```
<!-- ここに Issue の AC を列挙する -->
- AC-1: ...
- AC-2: ...
...
```

## (d) DeltaSpec Link

```
<!-- ここに DeltaSpec へのリンクを記載する -->
DeltaSpec: plugins/twl/deltaspec/changes/<deltaspec-slug>.md
（不在の場合は「DeltaSpec なし」と記載）
```

---

## 使用方法

1. このテンプレートを worktree にコピーする:
   ```bash
   cp plugins/twl/skills/su-observer/templates/feature-dev-fallback-prompt.md \
      /tmp/feature-dev-prompt-<N>.md
   ```

2. (a)-(d) の各セクションを埋める

3. cld セッションで `/feature-dev` を実行し、プロンプト内容を貼り付ける

4. feature-dev の Phase 3 (Clarifying Questions) と Phase 5 (Implementation) でユーザーが承認判断を行う

---

## 制約事項

- observer は このプロンプトを自律的に使用して feature-dev を spawn してはならない（SU-10）
- ユーザーが手動で feature-dev セッションを起動し、このプロンプトを渡すこと
- TDD ルール（RED → GREEN）は feature-dev では強制されないため、実装者が意識して守ること
