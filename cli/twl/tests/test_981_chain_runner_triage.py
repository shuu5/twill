"""RED tests for Issue #981: chain-runner.sh token_bloat triage epic.

5 atomics (arch-ref, chain-status, dispatch-info, llm-complete, llm-delegate) share
the same path 'scripts/chain-runner.sh', causing 14 token_bloat criticals in twl_audit.
This epic evaluates Options A-F and implements the selected option.

All tests are RED (fail) until the implementation is complete.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

PLUGINS_TWL = Path(__file__).parents[3] / "plugins" / "twl"
DECISIONS_DIR = PLUGINS_TWL / "architecture" / "decisions"
DESIGNS_DIR = PLUGINS_TWL / "architecture" / "designs"
DEPS_YAML = PLUGINS_TWL / "deps.yaml"
CHAIN_RUNNER = PLUGINS_TWL / "scripts" / "chain-runner.sh"


# ---------------------------------------------------------------------------
# AC-1: Option selection design note / issue comment exists
# ---------------------------------------------------------------------------

def test_ac1_option_selection_design_note_exists():
    """AC-1: 6 Option trade-off 整理と採用 Option 選定が design note に明文化されていること。

    RED: design note がまだ作成されていないため fail する。
    GREEN: `architecture/designs/981-chain-runner-triage-option-selection.md` が存在し
          'Adopted Option' 等のキーワードを含む。
    """
    # RED: 実装前は design note が存在しない
    candidate_files = list(DESIGNS_DIR.glob("*981*")) + list(DESIGNS_DIR.glob("*chain-runner-triage*"))
    assert candidate_files, (
        "AC-1 RED: Option selection design note が見つかりません。"
        f"対象ディレクトリ: {DESIGNS_DIR}\n"
        "実装後は architecture/designs/ に 981 または chain-runner-triage を含むファイルが必要です。"
    )
    # Further: adopted option keyword
    content = candidate_files[0].read_text()
    assert any(kw in content for kw in ("採用", "Adopted", "Selected Option")), (
        "AC-1 RED: design note に採用 Option の明示がありません。"
    )


# ---------------------------------------------------------------------------
# AC-2: ADR or design note with rationale for selected option
# ---------------------------------------------------------------------------

def test_ac2_adr_or_design_note_with_rationale():
    """AC-2: 採用 Option の選定根拠が ADR または design note に明文化されていること。

    RED: 対応する ADR/design note がまだ作成されていないため fail する。
    GREEN: ADR-029 以降に chain-runner 関連のファイルが存在し、選定根拠を含む。
    """
    # Check ADR (ADR-029 or later)
    adr_files = list(DECISIONS_DIR.glob("ADR-02[89]-*.md")) + list(DECISIONS_DIR.glob("ADR-0[3-9][0-9]-*.md"))
    chain_adrs = [
        f for f in adr_files
        if any(kw in f.read_text() for kw in ("chain-runner", "shared_host", "token_bloat", "#981"))
    ]

    # Also check design notes
    design_notes = list(DESIGNS_DIR.glob("*981*")) + list(DESIGNS_DIR.glob("*chain-runner-triage*"))
    design_with_rationale = [
        f for f in design_notes
        if any(kw in f.read_text() for kw in ("trade-off", "根拠", "rationale", "因为", "なぜ"))
    ]

    assert chain_adrs or design_with_rationale, (
        "AC-2 RED: 採用 Option の選定根拠を含む ADR または design note が見つかりません。\n"
        f"ADR dir: {DECISIONS_DIR}\n"
        f"Design notes dir: {DESIGNS_DIR}"
    )


# ---------------------------------------------------------------------------
# AC-3: twl audit shows token_bloat critical count ≤ 9
# ---------------------------------------------------------------------------

def test_ac3_chain_runner_token_bloat_criticals_resolved():
    """AC-3: 採用 Option 実装後、chain-runner.sh 由来の token_bloat critical が解消されること。

    現状: 5 atomics (arch-ref/chain-status/dispatch-info/llm-complete/llm-delegate) が
          scripts/chain-runner.sh (14698 tok) を共有し、5 件の critical が発生している。

    RED: 実装前は 5 件の chain-runner.sh 由来 critical が存在する。
    GREEN: 採用 Option 実装後、chain-runner.sh 由来 critical が 0 件になる。
    """
    try:
        import yaml
        from twl.validation.audit import audit_collect
    except ImportError as e:
        pytest.fail(f"audit モジュールのインポート失敗: {e}")

    if not DEPS_YAML.exists():
        pytest.fail(f"deps.yaml が見つかりません: {DEPS_YAML}")

    with open(DEPS_YAML) as f:
        deps = yaml.safe_load(f)

    items = audit_collect(deps, PLUGINS_TWL)
    # These 5 atomics share chain-runner.sh (14698 tok each)
    _shared_atomics = {"arch-ref", "chain-status", "dispatch-info", "llm-complete", "llm-delegate"}
    chain_runner_criticals = [
        i for i in items
        if i.get("severity") == "critical"
        and i.get("section") == "token_bloat"
        and i.get("component") in _shared_atomics
    ]
    count = len(chain_runner_criticals)
    # RED: currently 5 chain-runner.sh related criticals exist
    assert count == 0, (
        f"AC-3 RED: chain-runner.sh 由来の token_bloat critical が {count} 件残存しています。\n"
        "該当 atomic: "
        + ", ".join(i.get("component", "?") for i in chain_runner_criticals)
        + "\n採用 Option を実装して shared path による重複計上を解消してください。"
    )


# ---------------------------------------------------------------------------
# AC-4: ADR-022 chain SSoT boundary invariant maintained
# ---------------------------------------------------------------------------

def test_ac4_chain_steps_ssot_invariant_not_violated_by_implementation():
    """AC-4: 採用 Option 実装後も deps.yaml chain SSoT 不変性 (ADR-022) が壊れていないこと。

    具体的: 5 shared atomics の実装変更後に check_deps_integrity がエラーを返さないこと。

    RED: 実装が進行中で deps.yaml が不整合な中間状態にある場合に fail する。
         また、設計文書がなければ fail する（AC-2 と連動）。
    GREEN: 採用 Option の実装完了後、deps.yaml 整合性チェックが通る。
    """
    try:
        from twl.chain.integrity import check_deps_integrity
    except ImportError as e:
        pytest.fail(f"twl.chain.integrity のインポート失敗: {e}")

    errors, warnings = check_deps_integrity(PLUGINS_TWL)
    assert not errors, (
        "AC-4 RED: chain SSoT boundary (ADR-022) 違反が検出されました:\n"
        + "\n".join(errors)
        + "\n採用 Option の実装中に deps.yaml SSoT 整合性が損なわれています。"
    )

    # Additionally: verify that the shared-path problem is actually fixed (AC-3 linked check)
    # If 5 atomics still share chain-runner.sh, the problem is unresolved
    import re
    deps_text = DEPS_YAML.read_text()
    shared_count = len(re.findall(r"path:\s+scripts/chain-runner\.sh", deps_text))
    assert shared_count < 5, (
        f"AC-4 RED: 依然として {shared_count} atomics が scripts/chain-runner.sh を共有しています。"
        "ADR-022 は chain.py CHAIN_STEPS と deps.yaml.chains の整合性を要求しますが、"
        "この共有 path は設計意図（各 atomic が独立の host script を持つ）と矛盾します。"
    )


# ---------------------------------------------------------------------------
# AC-5: Workflow skill orchestrate/step responsibility separation maintained
# ---------------------------------------------------------------------------

def test_ac5_shared_atomics_path_reduced_or_verified():
    """AC-5: 採用 Option 実装後、chain SSoT 境界が #985 と整合していること。

    具体的検証: deps.yaml の 'scripts/chain-runner.sh' を参照する atomic が
    実装前の 5 件から減少しているか、または整合性確認ドキュメントが存在すること。

    RED: 実装前は依然として 5 atomics が chain-runner.sh を共有している。
    GREEN: Option A (script 分割) 等の実装後、共有 path が消滅または減少する。
    """
    import re

    deps_text = DEPS_YAML.read_text()
    # Count how many atomics reference 'scripts/chain-runner.sh'
    matches = re.findall(r"path:\s+scripts/chain-runner\.sh", deps_text)
    shared_count = len(matches)

    # RED: before implementation, 5 atomics share chain-runner.sh
    # GREEN: after Option A implementation, shared_count drops to 0 (or Option C/D: different fix)
    assert shared_count < 5, (
        f"AC-5 RED: deps.yaml に 'scripts/chain-runner.sh' を参照する atomic が {shared_count} 件あります。"
        "採用 Option の実装前の状態です。"
        "Option A (script 分割) 等を実装し、共有参照を解消してください。"
        "Option C/D 採用時は本テストを issue #981 選択 Option に合わせて修正してください。"
    )


# ---------------------------------------------------------------------------
# AC-6: Shared host script pattern investigation documented
# ---------------------------------------------------------------------------

def test_ac6_shared_host_pattern_investigation_exists():
    """AC-6: deps.yaml 内で「複数 atomic が共有 host script を参照」するパターンの
    調査結果が記録されていること。

    RED: 調査結果ファイルがまだ作成されていないため fail する。
    GREEN: `.explore/981/shared-host-patterns.md` 等に調査結果が記録されている。
    """
    # Check explore directory
    explore_dir = PLUGINS_TWL.parents[1] / ".explore" / "981"
    worktree_root = PLUGINS_TWL.parents[1]

    candidate_paths = [
        # git-tracked（PR に含まれる）: 設計文書の AC-6 セクション
        DESIGNS_DIR / "981-chain-runner-triage-option-selection.md",
        # local only (gitignored): 詳細調査ファイル
        explore_dir / "shared-host-patterns.md",
        explore_dir / "summary.md",
        worktree_root / ".dev-session" / "issue-981" / "shared-host-investigation.md",
    ]
    found = [p for p in candidate_paths if p.exists()]

    assert found, (
        "AC-6 RED: 共有 host script パターン調査結果ファイルが見つかりません。\n"
        "期待されるパス:\n"
        + "\n".join(f"  - {p}" for p in candidate_paths)
        + "\n`yq` 等で deps.yaml を調査し、結果を記録してください。"
    )

    # Verify content includes investigation results
    content = found[0].read_text()
    assert any(kw in content for kw in ("chain-runner.sh", "shared_host", "共有", "AC-6", "ユニーク")), (
        f"AC-6 RED: {found[0]} に調査結果（chain-runner.sh 共有パターン）が含まれていません。"
    )
