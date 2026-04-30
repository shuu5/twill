"""Tests for Issue #1084: human-gate-marker RFC.

TDD RED phase — すべてのテストは実装前に FAIL する。
★HUMAN GATE (U+2605 HUMAN GATE) マーカーの ADR 起票・試験導入を検証する。
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# パス定数
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parents[3]
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"
ADR_DIR = PLUGINS_TWL / "architecture" / "decisions"
GLOSSARY_PATH = PLUGINS_TWL / "architecture" / "domain" / "glossary.md"
INTERVENTION_CATALOG = PLUGINS_TWL / "refs" / "intervention-catalog.md"
PITFALLS_CATALOG = PLUGINS_TWL / "skills" / "su-observer" / "refs" / "pitfalls-catalog.md"
SU_OBSERVER_SKILL = PLUGINS_TWL / "skills" / "su-observer" / "SKILL.md"
PR_MERGE_SKILL = PLUGINS_TWL / "skills" / "workflow-pr-merge" / "SKILL.md"
CO_AUTOPILOT_SKILL = PLUGINS_TWL / "skills" / "co-autopilot" / "SKILL.md"
CO_ARCHITECT_SKILL = PLUGINS_TWL / "skills" / "co-architect" / "SKILL.md"

MARKER = "★HUMAN GATE"  # ★HUMAN GATE


def _make_section_regex(section_num: int) -> re.Pattern[str]:
    """§N 抽出用 regex を生成する。

    終端: 次の番号付き H2 (## M. 形式、M != N)、非番号 H2 (## 文字列)、H3 (### )、または EOF。
    限界: codeblock fence 内の `### ` / `## ` も終端として誤判定する（AC5 参照、将来課題）。
    """
    return re.compile(
        rf"## {section_num}\.(.*?)"
        rf"(?=\n## (?!{section_num}\.)\d+\.|\n## (?!\d)|\n### |\Z)",
        re.DOTALL,
    )


# ---------------------------------------------------------------------------
# ADR ファイル特定ヘルパー
# ---------------------------------------------------------------------------

def find_human_gate_adr() -> Path | None:
    """human-gate-marker を含む ADR ファイルを返す。存在しなければ None。"""
    if not ADR_DIR.exists():
        return None
    candidates = sorted(ADR_DIR.glob("ADR-*human-gate*.md"))
    return candidates[0] if candidates else None


def _get_decision_text(adr_path: Path) -> str:
    """ADR の Decision セクションテキストを返す。セクションがなければ空文字列。"""
    text = adr_path.read_text(encoding="utf-8")
    m = re.search(r"## Decision\n(.*?)(?=\n## |\Z)", text, re.DOTALL)
    return m.group(1) if m else ""


# ---------------------------------------------------------------------------
# AC1: ADR 起票
# ---------------------------------------------------------------------------

class TestAC1ADRDocument:
    """AC1: ADR ファイルの存在とセクション・必須記述を検証する。"""

    def test_ac1_adr_file_exists(self):
        # AC: plugins/twl/architecture/decisions/ADR-<NNNN>-human-gate-marker.md が存在する
        adr_path = find_human_gate_adr()
        assert adr_path is not None, (
            "AC1: ADR-<NNNN>-human-gate-marker.md が存在しない。"
            f"検索対象: {ADR_DIR}/ADR-*human-gate*.md"
        )

    def test_ac1_required_sections_present(self):
        # AC: Status / Context / Decision / Consequences / Alternatives セクションを含む
        adr_path = find_human_gate_adr()
        if adr_path is None:
            pytest.fail("AC1: ADR ファイルが存在しないためセクション検証不可")
        text = adr_path.read_text(encoding="utf-8")
        for section in ("Status", "Context", "Decision", "Consequences", "Alternatives"):
            assert f"## {section}" in text or f"**{section}**" in text, (
                f"AC1: ADR に '{section}' セクションが見当たらない"
            )

    def _decision_text(self) -> str:
        adr_path = find_human_gate_adr()
        if adr_path is None:
            pytest.fail("AC1: ADR ファイルが存在しない")
        dt = _get_decision_text(adr_path)
        if not dt:
            pytest.fail("AC1: Decision セクションが見当たらない")
        return dt

    def test_ac1_decision_contains_marker_symbol(self):
        # AC: Decision に記号 ★HUMAN GATE（U+2605）が明記されている
        assert MARKER in self._decision_text(), (
            f"AC1: Decision セクションに '{MARKER}' が見当たらない"
        )

    def test_ac1_decision_contains_primary_purpose(self):
        # AC: Decision に主目的が明記されている
        dt = self._decision_text()
        assert "主目的" in dt or "primary" in dt.lower(), (
            "AC1: Decision に主目的の記述が見当たらない"
        )

    def test_ac1_decision_contains_secondary_purpose(self):
        # AC: Decision に副目的が明記されている
        dt = self._decision_text()
        assert "副目的" in dt or "secondary" in dt.lower(), (
            "AC1: Decision に副目的の記述が見当たらない"
        )

    def test_ac1_decision_contains_application_conditions(self):
        # AC: Decision に適用条件が明記されている
        dt = self._decision_text()
        assert "適用条件" in dt or "condition" in dt.lower(), (
            "AC1: Decision に適用条件の記述が見当たらない"
        )

    def test_ac1_decision_contains_phased_rollout(self):
        # AC: Decision に段階導入方針が明記されている
        dt = self._decision_text()
        assert "段階" in dt or "phase" in dt.lower() or "rollout" in dt.lower(), (
            "AC1: Decision に段階導入方針の記述が見当たらない"
        )


# ---------------------------------------------------------------------------
# AC2: observer 主体 3 箇所への試験導入
# ---------------------------------------------------------------------------

class TestAC2ObserverMarkers:
    """AC2: observer 関連ファイル 3 箇所に ★HUMAN GATE が導入されていることを検証する。"""

    def test_ac2a_intervention_catalog_layer1_heading(self):
        # AC: intervention-catalog.md の Layer 1 セクション見出し直後に ★HUMAN GATE
        text = INTERVENTION_CATALOG.read_text(encoding="utf-8")
        # "## Layer 1: Confirm" 見出し直後の行に ★HUMAN GATE が含まれること
        match = re.search(r"## Layer 1:.*?\n(.*)", text)
        assert match is not None, "AC2(a): '## Layer 1:' 見出しが見当たらない"
        next_line = match.group(1).split("\n")[0]
        assert MARKER in next_line, (
            f"AC2(a): '## Layer 1:' 見出し直後の行に '{MARKER}' が見当たらない。"
            f"実際: {next_line!r}"
        )

    def test_ac2a_intervention_catalog_layer2_heading(self):
        # AC: intervention-catalog.md の Layer 2 セクション見出し直後に ★HUMAN GATE
        text = INTERVENTION_CATALOG.read_text(encoding="utf-8")
        match = re.search(r"## Layer 2:.*?\n(.*)", text)
        assert match is not None, "AC2(a): '## Layer 2:' 見出しが見当たらない"
        next_line = match.group(1).split("\n")[0]
        assert MARKER in next_line, (
            f"AC2(a): '## Layer 2:' 見出し直後の行に '{MARKER}' が見当たらない。"
            f"実際: {next_line!r}"
        )

    def test_ac2b_pitfalls_catalog_section11_escalation_trigger(self):
        # AC: pitfalls-catalog.md §11 のユーザー escalation 判断 trigger 行に ★HUMAN GATE
        text = PITFALLS_CATALOG.read_text(encoding="utf-8")
        # §11 セクションを抽出
        sec11_match = _make_section_regex(11).search(text)
        assert sec11_match is not None, "AC2(b): pitfalls-catalog.md に §11 セクションが見当たらない"
        sec11_text = sec11_match.group(0)
        assert MARKER in sec11_text, (
            f"AC2(b): pitfalls-catalog.md §11 に '{MARKER}' が見当たらない"
        )

    def test_ac2b_pitfalls_catalog_section12_escalation_trigger(self):
        # AC: pitfalls-catalog.md §12 のユーザー escalation 判断 trigger 行に ★HUMAN GATE
        text = PITFALLS_CATALOG.read_text(encoding="utf-8")
        # §12 セクションを抽出
        sec12_match = _make_section_regex(12).search(text)
        assert sec12_match is not None, "AC2(b): pitfalls-catalog.md に §12 セクションが見当たらない"
        sec12_text = sec12_match.group(0)
        assert MARKER in sec12_text, (
            f"AC2(b): pitfalls-catalog.md §12 に '{MARKER}' が見当たらない"
        )

    def test_ac2c_su_observer_skill_step1_user_gate(self):
        # AC: su-observer/SKILL.md の常駐ループ Step 1 の user 指示待ち or AskUserQuestion 起動条件に ★HUMAN GATE
        text = SU_OBSERVER_SKILL.read_text(encoding="utf-8")
        # Step 1 セクションを抽出
        step1_match = re.search(r"## Step 1:.*?\n(.*?)(?=\n## Step 2:|\Z)", text, re.DOTALL)
        assert step1_match is not None, "AC2(c): su-observer/SKILL.md に '## Step 1:' セクションが見当たらない"
        step1_text = step1_match.group(0)
        assert MARKER in step1_text, (
            f"AC2(c): su-observer/SKILL.md Step 1 に '{MARKER}' が見当たらない"
        )


# ---------------------------------------------------------------------------
# AC3: autopilot 補助 3 箇所への試験導入
# ---------------------------------------------------------------------------

class TestAC3AutopilotMarkers:
    """AC3: autopilot 補助ファイル 3 箇所に ★HUMAN GATE が導入されていることを検証する。"""

    def test_ac3d_pr_merge_skill_merge_gate_escalation(self):
        # AC: workflow-pr-merge/SKILL.md の merge-gate エスカレーション行の直前に ★HUMAN GATE
        text = PR_MERGE_SKILL.read_text(encoding="utf-8")
        # merge-gate エスカレーション言及行を探し、直前に ★HUMAN GATE があること
        lines = text.splitlines()
        escalation_indices = [
            i for i, line in enumerate(lines)
            if "merge-gate エスカレーション" in line or "merge-gate escalat" in line.lower()
        ]
        assert escalation_indices, (
            "AC3(d): workflow-pr-merge/SKILL.md に merge-gate エスカレーション行が見当たらない"
        )
        # 少なくとも 1 つの escalation 行の直前に ★HUMAN GATE があること
        found = False
        for idx in escalation_indices:
            if idx > 0 and MARKER in lines[idx - 1]:
                found = True
                break
        assert found, (
            f"AC3(d): workflow-pr-merge/SKILL.md の merge-gate エスカレーション行直前に "
            f"'{MARKER}' が見当たらない"
        )

    def test_ac3e_co_autopilot_step2_after_heading(self):
        # AC: co-autopilot/SKILL.md の ## Step 2: 計画承認 見出し直後に ★HUMAN GATE
        text = CO_AUTOPILOT_SKILL.read_text(encoding="utf-8")
        match = re.search(r"## Step 2: 計画承認\n(.*)", text)
        assert match is not None, "AC3(e): co-autopilot/SKILL.md に '## Step 2: 計画承認' 見出しが見当たらない"
        next_line = match.group(1).split("\n")[0]
        assert MARKER in next_line, (
            f"AC3(e): co-autopilot/SKILL.md '## Step 2: 計画承認' 直後の行に "
            f"'{MARKER}' が見当たらない。実際: {next_line!r}"
        )

    def test_ac3f_co_architect_step4_after_heading(self):
        # AC: co-architect/SKILL.md の ## Step 4: ユーザー確認 見出し直後に ★HUMAN GATE
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        match = re.search(r"## Step 4: ユーザー確認\n(.*)", text)
        assert match is not None, "AC3(f): co-architect/SKILL.md に '## Step 4: ユーザー確認' 見出しが見当たらない"
        next_line = match.group(1).split("\n")[0]
        assert MARKER in next_line, (
            f"AC3(f): co-architect/SKILL.md '## Step 4: ユーザー確認' 直後の行に "
            f"'{MARKER}' が見当たらない。実際: {next_line!r}"
        )


# ---------------------------------------------------------------------------
# Issue #1099: AC4（異常系回帰テスト）— セクション境界精度向上
# ---------------------------------------------------------------------------

class TestAC2bSectionBoundaryRegression:
    """Issue #1099: _make_section_regex ヘルパーの異常系回帰テスト。

    RED フェーズ: _make_section_regex が未定義のため NameError で fail する。
    """

    def test_ac1_make_section_regex_helper_exists(self):
        # AC1: _make_section_regex ヘルパー関数が存在し、Pattern を返すこと
        # RED: _make_section_regex が未定義なので NameError で fail する
        assert callable(_make_section_regex), (
            "AC1: _make_section_regex ヘルパー関数が callable でない"
        )
        pattern = _make_section_regex(11)
        assert hasattr(pattern, "search"), (
            "AC1: _make_section_regex(11) が re.Pattern を返さない"
        )

    def test_ac2_make_section_regex_terminates_at_h3(self):
        # AC2: _make_section_regex は ### で始まる H3 見出しを終端境界として認識すること
        # RED: _make_section_regex が未定義なので NameError で fail する
        pattern = _make_section_regex(11)
        fixture = (
            "## 11. テストセクション\n"
            "本文\n"
            "### H3 subsection\n"
            "H3 内本文\n"
            "## 12. 次のセクション\n"
        )
        m = pattern.search(fixture)
        assert m is not None, "AC2: §11 セクションがマッチしない"
        extracted = m.group(0)
        assert "### H3 subsection" not in extracted, (
            f"AC2: _make_section_regex が H3 で終端せず H3 内容を含んでいる。抽出: {extracted!r}"
        )

    def test_ac4_1_h3_subsection_marker_excluded(self):
        # AC4-1: H3 subsection 内の MARKER は §12 抽出範囲から除外されること
        # RED: _make_section_regex が未定義なので NameError で fail する
        pattern = _make_section_regex(12)
        fixture = (
            f"## 12. ヘッダ\n"
            f"本文\n"
            f"### 内部見出し\n"
            f"本文に {MARKER} を含む\n"
            f"## 13. 次\n"
        )
        m = pattern.search(fixture)
        assert m is not None, "AC4-1: §12 セクションがマッチしない"
        sec12_text = m.group(0)
        assert MARKER not in sec12_text, (
            f"AC4-1: H3 subsection 内の MARKER が §12 抽出範囲に含まれている。"
            f"修正後の regex は H3 を終端境界として MARKER を除外すべき。"
            f"抽出: {sec12_text!r}"
        )

    def test_ac4_2_no_next_section_h3_closes_boundary(self):
        # AC4-2: §N+1 不在かつ H3 ありの場合、抽出範囲が H3 で正しく閉じること
        # RED: _make_section_regex が未定義なので NameError で fail する
        pattern = _make_section_regex(12)
        fixture = (
            f"## 12. ヘッダ\n"
            f"{MARKER} 本文\n"
            f"### 内部見出し\n"
            f"H3 内本文"
        )
        m = pattern.search(fixture)
        assert m is not None, "AC4-2: §12 セクションがマッチしない"
        extracted = m.group(0)
        assert len(extracted) < len(fixture), (
            f"AC4-2: 抽出範囲が H3 で閉じておらず fixture 全体を含んでいる。"
            f"抽出長={len(extracted)}, fixture 長={len(fixture)}"
        )

    @pytest.mark.xfail(reason="codeblock-fence-aware terminator は別 Issue で対応")
    def test_ac5_codeblock_fence_resistance(self):
        # AC5: codeblock 内の ### は終端境界として認識されないこと（現状は xfail）
        # RED: _make_section_regex が未定義なので NameError で fail する
        pattern = _make_section_regex(12)
        fixture = (
            f"## 12. ヘッダ\n"
            f"{MARKER} 本文\n"
            f"```bash\n"
            f"### これは codeblock 内なので H3 ではない\n"
            f"echo hello\n"
            f"```\n"
            f"codeblock 後の本文\n"
            f"## 13. 次\n"
        )
        m = pattern.search(fixture)
        assert m is not None, "AC5: §12 セクションがマッチしない"
        extracted = m.group(0)
        # codeblock 内の ### で終端してしまう場合、本文後の内容が欠落する
        assert "codeblock 後の本文" in extracted, (
            f"AC5: codeblock 内の ### が誤って終端境界として認識された。"
            f"抽出: {extracted!r}"
        )


# ---------------------------------------------------------------------------
# AC4: grep 検証 (2 段階)
# ---------------------------------------------------------------------------

class TestAC4GrepVerification:
    """AC4: ★HUMAN GATE マーカーの grep 検証（2 段階）。"""

    def _grep_files_with_marker(self) -> list[str]:
        """★HUMAN GATE を含むファイルの一覧を返す。"""
        result = subprocess.run(
            ["grep", "-rl", MARKER, str(PLUGINS_TWL)],
            capture_output=True,
            text=True,
        )
        # grep: 0=found, 1=not-found, others=error
        if result.returncode not in (0, 1):
            pytest.fail(f"AC4: grep コマンドがエラー終了 (exit={result.returncode}): {result.stderr}")
        return [f.strip() for f in result.stdout.splitlines() if f.strip()]

    def test_ac4_stage1_at_least_6_files(self):
        # AC: Stage 1 — AC2 + AC3 = 6 ファイル以上にヒット
        files = self._grep_files_with_marker()
        assert len(files) >= 6, (
            f"AC4 Stage1: '{MARKER}' が 6 ファイル以上に存在しない。"
            f"現在 {len(files)} ファイル: {files}"
        )

    def test_ac4_stage2_at_least_8_files_including_adr_and_glossary(self):
        # AC: Stage 2 — ADR + glossary.md 含めて 8 ファイル以上
        files = self._grep_files_with_marker()
        assert len(files) >= 8, (
            f"AC4 Stage2: '{MARKER}' が 8 ファイル以上に存在しない。"
            f"現在 {len(files)} ファイル: {files}"
        )
        # ADR ファイルが含まれていること
        adr_files = [f for f in files if "ADR-" in f and "human-gate" in f]
        assert adr_files, (
            f"AC4 Stage2: ADR human-gate ファイルが '{MARKER}' を含むファイル一覧に存在しない。"
            f"ファイル一覧: {files}"
        )
        # glossary.md が含まれていること
        glossary_files = [f for f in files if "glossary.md" in f]
        assert glossary_files, (
            f"AC4 Stage2: glossary.md が '{MARKER}' を含むファイル一覧に存在しない。"
            f"ファイル一覧: {files}"
        )

    def test_ac4_utf8_marker_not_corrupted(self):
        # AC: UTF-8 確認 — U+2605 (0xe2 0x98 0x85) が壊れていないこと
        marker_bytes = "★HUMAN GATE".encode("utf-8")  # \xe2\x98\x85HUMAN GATE
        target_files = [
            INTERVENTION_CATALOG,
            PITFALLS_CATALOG,
            SU_OBSERVER_SKILL,
            PR_MERGE_SKILL,
            CO_AUTOPILOT_SKILL,
            CO_ARCHITECT_SKILL,
            GLOSSARY_PATH,
        ]
        matched_files = [p for p in target_files if p.exists() and marker_bytes in p.read_bytes()]
        assert len(matched_files) >= 6, (
            f"AC4 UTF-8: U+2605 バイト列 ★HUMAN GATE が 6 ファイル以上に存在しない。"
            f"現在 {len(matched_files)} ファイル: {[str(p) for p in matched_files]}"
        )


# ---------------------------------------------------------------------------
# AC5: glossary.md への MUST 用語追加
# ---------------------------------------------------------------------------

class TestAC5GlossaryEntry:
    """AC5: glossary.md に ★HUMAN GATE が MUST 用語として追加されていることを検証する。"""

    def test_ac5_glossary_contains_marker(self):
        # AC: glossary.md の MUST 用語に ★HUMAN GATE を追加する
        text = GLOSSARY_PATH.read_text(encoding="utf-8")
        assert MARKER in text, (
            f"AC5: glossary.md に '{MARKER}' が見当たらない: {GLOSSARY_PATH}"
        )

    def test_ac5_glossary_marker_in_must_section(self):
        # AC: ★HUMAN GATE が MUST 用語セクションに配置されていること
        text = GLOSSARY_PATH.read_text(encoding="utf-8")
        # MUST セクション（大文字 MUST または ## MUST 等）を探す
        must_match = re.search(r"(?i)(## .*must.*|MUST 用語.*)\n(.*?)(?=\n## |\Z)", text, re.DOTALL)
        if must_match is None:
            # MUST セクションが特定できなくても ★HUMAN GATE 自体の存在は test_ac5_glossary_contains_marker で確認済み
            # 補足検証: ★HUMAN GATE の周辺に MUST の記述があること
            marker_match = re.search(re.escape(MARKER) + r".*", text)
            assert marker_match is not None, f"AC5: glossary.md に '{MARKER}' が見当たらない"
            context_start = max(0, marker_match.start() - 200)
            context = text[context_start: marker_match.end() + 200]
            assert "MUST" in context or "must" in context.lower(), (
                f"AC5: '{MARKER}' の周辺に MUST の記述が見当たらない。"
                f"周辺テキスト: {context!r}"
            )
        else:
            must_text = must_match.group(0)
            assert MARKER in must_text, (
                f"AC5: MUST セクションに '{MARKER}' が見当たらない"
            )
