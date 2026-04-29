"""Issue #1084: ★HUMAN GATE マーカー試験導入 — AC テスト (RED フェーズ).

全テストは実装前に FAIL する（RED）。実装完了後に GREEN になる。

★ = U+2605 BLACK STAR (UTF-8: 0xe2 0x98 0x85)
"""

from __future__ import annotations

import glob
import re
from pathlib import Path

import pytest

# リポジトリルートを決定（このファイルから 3 レベル上が cli/twl、そこから 2 つ上がリポジトリルート）
_REPO_ROOT = Path(__file__).resolve().parents[3]
_PLUGINS_ROOT = _REPO_ROOT / "plugins" / "twl"
_DECISIONS_DIR = _PLUGINS_ROOT / "architecture" / "decisions"

HUMAN_GATE_MARKER = "★HUMAN GATE"  # ★HUMAN GATE


# ---------------------------------------------------------------------------
# AC1: ADR 起票
# ---------------------------------------------------------------------------


def test_ac1_adr_file_exists():
    """AC1: ADR-<NNNN>-human-gate-marker.md が存在すること。"""
    matches = list(_DECISIONS_DIR.glob("ADR-*-human-gate-marker.md"))
    assert len(matches) >= 1, (
        f"ADR-<NNNN>-human-gate-marker.md が {_DECISIONS_DIR} に存在しない"
    )


def test_ac1_adr_required_sections():
    """AC1: ADR に Status / Context / Decision / Consequences / Alternatives セクションが存在すること。"""
    matches = list(_DECISIONS_DIR.glob("ADR-*-human-gate-marker.md"))
    assert matches, f"ADR ファイルが {_DECISIONS_DIR} に存在しない"

    adr_path = matches[0]
    content = adr_path.read_text(encoding="utf-8")

    required_sections = [
        "Status",
        "Context",
        "Decision",
        "Consequences",
        "Alternatives",
    ]
    missing = [s for s in required_sections if re.search(rf"#+\s*{s}", content) is None]
    assert not missing, (
        f"{adr_path.name} に以下のセクションが不足: {missing}"
    )


# ---------------------------------------------------------------------------
# AC2: observer 主体 3 箇所への ★HUMAN GATE 挿入
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("layer_num", [1, 2])
def test_ac2a_intervention_catalog_layer(layer_num: int):
    """AC2(a): intervention-catalog.md の Layer N セクション見出し直後に ★HUMAN GATE が存在すること。"""
    path = _PLUGINS_ROOT / "refs" / "intervention-catalog.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    found = False
    for i, line in enumerate(lines):
        if re.search(rf"Layer\s*{layer_num}", line, re.IGNORECASE) and line.lstrip().startswith("#"):
            window = "\n".join(lines[i : i + 6])
            if HUMAN_GATE_MARKER in window:
                found = True
                break
    assert found, (
        f"{path.name}: Layer {layer_num} セクション見出し直後に {HUMAN_GATE_MARKER!r} が見つからない"
    )


def test_ac2b_pitfalls_catalog_escalation_trigger():
    """AC2(b): pitfalls-catalog.md §11/§12 の escalation trigger 行に ★HUMAN GATE が存在すること。"""
    path = _PLUGINS_ROOT / "skills" / "su-observer" / "refs" / "pitfalls-catalog.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    # §11 または §12 のセクション内に escalation trigger + ★HUMAN GATE
    found = False
    in_target_section = False
    for line in lines:
        if re.search(r"§\s*(11|12)", line):
            in_target_section = True
        elif re.search(r"^#{1,3}\s", line) and re.search(r"§\s*\d+", line):
            # 別のセクションに入った
            if in_target_section:
                in_target_section = False
        if in_target_section and "escalation" in line.lower() and HUMAN_GATE_MARKER in line:
            found = True
            break

    assert found, (
        f"{path.name}: §11/§12 の escalation trigger 行に {HUMAN_GATE_MARKER!r} が見つからない"
    )


def test_ac2c_observer_skill_askuserquestion():
    """AC2(c): su-observer/SKILL.md の AskUserQuestion 起動条件箇所に ★HUMAN GATE が存在すること。"""
    path = _PLUGINS_ROOT / "skills" / "su-observer" / "SKILL.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    found = False
    for i, line in enumerate(lines):
        if "AskUserQuestion" in line:
            # AskUserQuestion が現れる周辺 5 行以内に ★HUMAN GATE
            window = "\n".join(lines[max(0, i - 2) : i + 6])
            if HUMAN_GATE_MARKER in window:
                found = True
                break

    assert found, (
        f"{path.name}: AskUserQuestion 起動条件箇所に {HUMAN_GATE_MARKER!r} が見つからない"
    )


# ---------------------------------------------------------------------------
# AC3: autopilot 補助 3 箇所への ★HUMAN GATE 挿入
# ---------------------------------------------------------------------------


def test_ac3d_workflow_pr_merge_gate():
    """AC3(d): workflow-pr-merge/SKILL.md の merge-gate エスカレーション直前に ★HUMAN GATE が存在すること。"""
    path = _PLUGINS_ROOT / "skills" / "workflow-pr-merge" / "SKILL.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    # merge-gate またはエスカレーション関連行の直前に ★HUMAN GATE
    found = False
    for i, line in enumerate(lines):
        if re.search(r"merge.gate|escalat", line, re.IGNORECASE):
            # 直前 3 行以内に ★HUMAN GATE
            window = "\n".join(lines[max(0, i - 3) : i + 1])
            if HUMAN_GATE_MARKER in window:
                found = True
                break

    assert found, (
        f"{path.name}: merge-gate エスカレーション直前に {HUMAN_GATE_MARKER!r} が見つからない"
    )


def test_ac3e_co_autopilot_step2_approval():
    """AC3(e): co-autopilot/SKILL.md の Step 2 計画承認直後に ★HUMAN GATE が存在すること。"""
    path = _PLUGINS_ROOT / "skills" / "co-autopilot" / "SKILL.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    found = False
    for i, line in enumerate(lines):
        if re.search(r"Step\s*2", line, re.IGNORECASE) and re.search(
            r"承認|approval|plan", line, re.IGNORECASE
        ):
            # 直後 5 行以内に ★HUMAN GATE
            window = "\n".join(lines[i : i + 6])
            if HUMAN_GATE_MARKER in window:
                found = True
                break

    assert found, (
        f"{path.name}: Step 2 計画承認直後に {HUMAN_GATE_MARKER!r} が見つからない"
    )


def test_ac3f_co_architect_step4_confirmation():
    """AC3(f): co-architect/SKILL.md の Step 4 ユーザー確認直後に ★HUMAN GATE が存在すること。"""
    path = _PLUGINS_ROOT / "skills" / "co-architect" / "SKILL.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    found = False
    for i, line in enumerate(lines):
        if re.search(r"Step\s*4", line, re.IGNORECASE) and re.search(
            r"確認|confirm|ユーザー|user", line, re.IGNORECASE
        ):
            window = "\n".join(lines[i : i + 6])
            if HUMAN_GATE_MARKER in window:
                found = True
                break

    assert found, (
        f"{path.name}: Step 4 ユーザー確認直後に {HUMAN_GATE_MARKER!r} が見つからない"
    )


# ---------------------------------------------------------------------------
# AC4: grep 検証
# ---------------------------------------------------------------------------


def test_ac4_human_gate_at_least_6_files():
    """AC4: plugins/ 配下で ★HUMAN GATE が 6 ファイル以上ヒットすること。"""
    hit_files = set()
    for path in _PLUGINS_ROOT.rglob("*.md"):
        try:
            if HUMAN_GATE_MARKER in path.read_text(encoding="utf-8"):
                hit_files.add(str(path))
        except (UnicodeDecodeError, OSError):
            pass

    assert len(hit_files) >= 6, (
        f"★HUMAN GATE ヒット数: {len(hit_files)} ファイル（6 以上必要）\n"
        f"ヒット済み: {sorted(hit_files)}"
    )


def test_ac4_human_gate_at_least_8_files_including_adr_glossary():
    """AC4: ADR と glossary を含めて ★HUMAN GATE が 8 ファイル以上ヒットすること。"""
    search_roots = [_PLUGINS_ROOT, _REPO_ROOT / "cli" / "twl"]
    hit_files = set()

    for root in search_roots:
        if not root.exists():
            continue
        for path in root.rglob("*.md"):
            try:
                if HUMAN_GATE_MARKER in path.read_text(encoding="utf-8"):
                    hit_files.add(str(path))
            except (UnicodeDecodeError, OSError):
                pass

    # ADR ファイルも含める
    for path in _DECISIONS_DIR.glob("ADR-*-human-gate-marker.md"):
        try:
            if HUMAN_GATE_MARKER in path.read_text(encoding="utf-8"):
                hit_files.add(str(path))
        except (UnicodeDecodeError, OSError):
            pass

    assert len(hit_files) >= 8, (
        f"★HUMAN GATE ヒット数: {len(hit_files)} ファイル（ADR/glossary 含め 8 以上必要）\n"
        f"ヒット済み: {sorted(hit_files)}"
    )


def test_ac4_human_gate_utf8_codepoint():
    """AC4: ★ が U+2605 BLACK STAR (UTF-8: 0xe2 0x98 0x85) であること。"""
    # マーカー文字列の先頭が U+2605 であることをバイト列で確認
    marker_bytes = HUMAN_GATE_MARKER.encode("utf-8")
    assert marker_bytes[:3] == b"\xe2\x98\x85", (
        f"★ の UTF-8 バイト列が想定外: {marker_bytes[:3]!r}（期待: b'\\xe2\\x98\\x85'）"
    )

    # plugins/ 内のいずれかのファイルに実際のバイト列が含まれること
    found_correct_bytes = False
    for path in _PLUGINS_ROOT.rglob("*.md"):
        try:
            raw = path.read_bytes()
            if b"\xe2\x98\x85HUMAN GATE" in raw:
                found_correct_bytes = True
                break
        except OSError:
            pass

    assert found_correct_bytes, (
        "plugins/ 配下のいずれのファイルにも b'\\xe2\\x98\\x85HUMAN GATE' が見つからない"
    )


# ---------------------------------------------------------------------------
# AC5: glossary.md への MUST 用語追加
# ---------------------------------------------------------------------------


def test_ac5_glossary_has_human_gate_entry():
    """AC5: glossary.md の MUST 用語に ★HUMAN GATE が追加されていること。"""
    path = _PLUGINS_ROOT / "architecture" / "domain" / "glossary.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")

    assert HUMAN_GATE_MARKER in content, (
        f"{path.name} に {HUMAN_GATE_MARKER!r} が見つからない"
    )


def test_ac5_glossary_human_gate_in_must_section():
    """AC5: glossary.md の MUST セクション内に ★HUMAN GATE エントリが存在すること。"""
    path = _PLUGINS_ROOT / "architecture" / "domain" / "glossary.md"
    assert path.exists(), f"{path} が存在しない"

    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()

    in_must_section = False
    found = False
    for line in lines:
        if re.search(r"MUST", line) and line.lstrip().startswith("#"):
            in_must_section = True
        elif line.lstrip().startswith("#") and re.search(r"^#{1,3}\s", line):
            # 別のセクションに移った可能性（MUST でない見出し）
            if in_must_section and "MUST" not in line:
                in_must_section = False
        if in_must_section and HUMAN_GATE_MARKER in line:
            found = True
            break

    assert found, (
        f"{path.name}: MUST セクション内に {HUMAN_GATE_MARKER!r} が見つからない"
    )
