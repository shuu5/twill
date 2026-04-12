"""Tests for Issue #465: workflow-issue-refine SKILL.md Step 3b 責務分離ノート.

Spec: deltaspec/changes/issue-465/specs/skill-md-responsibility-note/spec.md

Coverage:
  Requirement: workflow-issue-refine SKILL.md Step 3b 責務分離ノート
    - Scenario: 新規 reader が Step 3b を読む場合
        WHEN 新規 reader（人間 or LLM）が workflow-issue-refine/SKILL.md Step 3b を読む
        THEN 責務分離ノートにより「完了保証は hook により機械的に強制される」ことが理解できる

    - Scenario: LLM が spec-review-session-init.sh 呼出を省略した場合
        WHEN LLM が誤って spec-review-session-init.sh の呼出を省略し
             Skill(issue-review-aggregate) を実行しようとする
        THEN ノートの記述から「state ファイル不在時に hook が fallthrough する」ことが
             読み取れ、省略のリスクを認識できる

    - Scenario: 既存の Step 3b / 3c の動作
        WHEN ノートを追記した後、workflow-issue-refine ワークフローが実行される
        THEN Step 3b / 3c の動作ロジックは変更されず、既存の振る舞いが維持される（SHALL）

Note: これはドキュメント専用変更（SKILL.md へのテキスト追記のみ）のテスト。
コードロジックの変更がないため、テストはファイル内容の静的検証として実装する。
"""

from __future__ import annotations

from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parents[5]
_SKILL_MD = _REPO_ROOT / "plugins" / "twl" / "skills" / "workflow-issue-refine" / "SKILL.md"
_HOOK_SCRIPT = (
    _REPO_ROOT
    / "plugins"
    / "twl"
    / "scripts"
    / "hooks"
    / "pre-tool-use-spec-review-gate.sh"
)


def _read_skill_md() -> str:
    return _SKILL_MD.read_text(encoding="utf-8")


def _step_3b_section(content: str) -> str:
    """Return the text from the Step 3b heading through Step 3c (exclusive)."""
    lines = content.splitlines()
    in_section = False
    section_lines: list[str] = []
    for line in lines:
        if line.startswith("## Step 3b:"):
            in_section = True
        elif in_section and line.startswith("## "):
            # Next top-level section terminates Step 3b
            break
        if in_section:
            section_lines.append(line)
    return "\n".join(section_lines)


# ---------------------------------------------------------------------------
# Requirement: workflow-issue-refine SKILL.md Step 3b 責務分離ノート
# ---------------------------------------------------------------------------


class TestStep3bResponsibilityNote:
    """Requirement: workflow-issue-refine SKILL.md Step 3b 責務分離ノート"""

    # ------------------------------------------------------------------
    # Scenario: 新規 reader が Step 3b を読む場合
    # WHEN: 新規 reader（人間 or LLM）が workflow-issue-refine/SKILL.md Step 3b を読む
    # THEN: 責務分離ノートにより「完了保証は hook により機械的に強制される」ことが理解できる
    # ------------------------------------------------------------------

    def test_skill_md_exists(self) -> None:
        """SKILL.md ファイルが存在すること（前提条件）。"""
        assert _SKILL_MD.exists(), f"SKILL.md が見つかりません: {_SKILL_MD}"

    def test_step_3b_section_exists(self) -> None:
        """WHEN SKILL.md を読む THEN '## Step 3b:' セクションが存在する。"""
        content = _read_skill_md()
        assert "## Step 3b:" in content, (
            "SKILL.md に '## Step 3b:' セクションが存在しない"
        )

    def test_step_3b_contains_hook_enforcement_statement(self) -> None:
        """WHEN Step 3b を読む THEN hook による機械的強制に関する記述が存在する。

        責務分離ノートには「完了保証は hook により機械的に強制される」という趣旨が
        読み取れる記述が必要。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        # hook による強制・保証の記述が存在することを確認
        hook_enforcement_keywords = ["hook", "強制", "保証", "deny", "gate"]
        found = any(kw.lower() in step_3b.lower() for kw in hook_enforcement_keywords)
        assert found, (
            "Step 3b の責務分離ノートに hook による機械的強制の記述が見つからない。\n"
            f"期待キーワード: {hook_enforcement_keywords}\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3b_contains_llm_guidance_and_hook_layer_distinction(self) -> None:
        """WHEN Step 3b を読む THEN LLM ガイダンス層と hook 自動ゲート層の責務境界が説明されている。

        Spec に「LLM ガイダンス層と hook 自動ゲート層の責務境界」の記載が求められる。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        # 両層の存在を示すキーワード
        has_llm_layer = any(kw in step_3b for kw in ["LLM", "ガイダンス", "guidance"])
        has_hook_layer = any(kw in step_3b for kw in ["hook", "Hook", "ゲート", "gate"])
        assert has_llm_layer and has_hook_layer, (
            "Step 3b は LLM ガイダンス層と hook 自動ゲート層の両方に言及する必要がある。\n"
            f"LLM 層への言及: {has_llm_layer}, hook 層への言及: {has_hook_layer}\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3b_references_hook_script(self) -> None:
        """WHEN Step 3b を読む THEN pre-tool-use-spec-review-gate.sh への参照が存在する。

        Spec に「plugins/twl/scripts/hooks/pre-tool-use-spec-review-gate.sh への参照リンク」
        が要求されている。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        assert "pre-tool-use-spec-review-gate" in step_3b, (
            "Step 3b に 'pre-tool-use-spec-review-gate.sh' への参照リンクが存在しない。\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    # ------------------------------------------------------------------
    # Scenario: LLM が spec-review-session-init.sh 呼出を省略した場合
    # WHEN: LLM が誤って spec-review-session-init.sh の呼出を省略し
    #       Skill(issue-review-aggregate) を実行しようとする
    # THEN: ノートの記述から「state ファイル不在時に hook が fallthrough する」ことが
    #       読み取れ、省略のリスクを認識できる
    # ------------------------------------------------------------------

    def test_step_3b_contains_session_init_script_reference(self) -> None:
        """WHEN Step 3b を読む THEN spec-review-session-init.sh への言及が存在する。

        省略リスクを認識させるためには、当該スクリプトの重要性が記述されている必要がある。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        assert "spec-review-session-init" in step_3b, (
            "Step 3b に 'spec-review-session-init.sh' への言及が存在しない。\n"
            "省略リスクを認識させるためにはスクリプト名の明示が必要。\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3b_contains_fallthrough_risk_description(self) -> None:
        """WHEN Step 3b を読む THEN state ファイル不在時の fallthrough リスクが記述されている。

        Spec に「state ファイル不在時に hook が fallthrough する」記述が要求されている。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        fallthrough_keywords = ["fallthrough", "fall through", "不在", "state ファイル", "state file"]
        found = any(kw.lower() in step_3b.lower() for kw in fallthrough_keywords)
        assert found, (
            "Step 3b の責務分離ノートに state ファイル不在時の fallthrough リスク記述が見つからない。\n"
            f"期待キーワード: {fallthrough_keywords}\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3b_contains_hook_deny_condition(self) -> None:
        """WHEN Step 3b を読む THEN hook による deny 発動条件（completed < total）が記述されている。

        Spec に「hook による deny 発動条件（completed < total）」の記述が要求されている。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        # "completed < total" または同等の記述
        deny_condition_keywords = ["completed < total", "completed", "deny"]
        found = any(kw in step_3b for kw in deny_condition_keywords)
        assert found, (
            "Step 3b の責務分離ノートに hook の deny 発動条件（completed < total）が見つからない。\n"
            f"期待キーワード: {deny_condition_keywords}\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    # ------------------------------------------------------------------
    # Scenario: 既存の Step 3b / 3c の動作
    # WHEN: ノートを追記した後、workflow-issue-refine ワークフローが実行される
    # THEN: Step 3b / 3c の動作ロジックは変更されず、既存の振る舞いが維持される（SHALL）
    # ------------------------------------------------------------------

    def test_step_3b_retains_issue_json_write_instruction(self) -> None:
        """WHEN Step 3b を読む THEN Issue JSON 書き出し手順（MUST）が保持されている。

        既存の Step 3b の核心動作：Issue JSON 書き出しが削除されていないことを確認。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        assert "Issue JSON" in step_3b or "issue-" in step_3b.lower(), (
            "Step 3b から Issue JSON 書き出し手順が削除されている可能性がある。\n"
            "ノート追記によって既存の動作指示が除去されてはならない。\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3b_retains_orchestrator_call_instruction(self) -> None:
        """WHEN Step 3b を読む THEN オーケストレーター呼び出し手順（MUST）が保持されている。

        既存の Step 3b の核心動作：spec-review-orchestrator.sh 呼び出しが削除されていないことを確認。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        assert "spec-review-orchestrator" in step_3b, (
            "Step 3b から 'spec-review-orchestrator.sh' の呼び出し指示が削除されている。\n"
            "ノート追記によって既存の動作指示が除去されてはならない。\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3b_retains_synchronization_barrier_instruction(self) -> None:
        """WHEN Step 3b を読む THEN 同期バリア（MUST）の記述が保持されている。

        既存の Step 3b の核心動作：同期バリア（Step 3c への進行禁止）が削除されていないことを確認。
        """
        content = _read_skill_md()
        step_3b = _step_3b_section(content)

        assert "同期バリア" in step_3b or "Step 3c" in step_3b, (
            "Step 3b から同期バリアまたは Step 3c への進行条件の記述が削除されている。\n"
            "ノート追記によって既存の動作指示が除去されてはならない。\n"
            f"Step 3b の内容:\n{step_3b[:500]}"
        )

    def test_step_3c_section_exists_and_intact(self) -> None:
        """WHEN SKILL.md を読む THEN Step 3c セクションが存在し、集約ロジックが保持されている。

        ノート追記後も Step 3c（レビュー結果集約）の動作指示が維持されること。
        """
        content = _read_skill_md()
        assert "## Step 3c:" in content, (
            "SKILL.md から '## Step 3c:' セクションが削除されている。\n"
            "ノート追記は Step 3c の動作を変更してはならない。"
        )

        # Step 3c 内のコアコンテンツを確認
        assert "issue-review-aggregate" in content, (
            "SKILL.md から 'issue-review-aggregate' への言及が削除されている。\n"
            "Step 3c の動作ロジックが維持されている必要がある。"
        )

    def test_hook_script_file_exists(self) -> None:
        """WHEN SKILL.md が参照する hook スクリプトへの参照を確認する THEN スクリプトが存在する。

        責務分離ノートが参照する pre-tool-use-spec-review-gate.sh が
        実際にリポジトリに存在することを確認（リンク切れ防止）。
        """
        assert _HOOK_SCRIPT.exists(), (
            f"SKILL.md が参照する hook スクリプトが存在しない: {_HOOK_SCRIPT}\n"
            "参照リンクは実在するファイルを指している必要がある。"
        )
