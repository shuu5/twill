"""Tests for Issue #1596: AC2 手動検証結果を PR または Issue に記録 (#1588).

TDD RED フェーズ。実装前（= GitHub コメント投稿前）は全テストが FAIL する（意図的 RED）。

Issue #1596 は **process 型 Issue** — コード変更なし、手動検証 + GitHub コメント投稿が実施内容。

AC 対応:
  AC1 (process): worktree cwd から `twl mcp restart` を実行し、新 PID / session reconnect を確認する
  AC2 (process): 手順と結果（実行 cwd・出力 PID・session reconnect 確認）を Issue #1588 コメント
                 または PR #1595 description に記録する

テスト戦略:
  - `gh issue view 1588 --comments` / `gh pr view 1595` の出力を subprocess で取得し、
    worktree smoke test の証跡キーワードが含まれているかを検証する
  - GitHub CLI (`gh`) が利用できない環境（CI offline 等）は pytest.skip でスキップ
  - 「証跡が存在しない」状態では FAIL → コメント投稿後に GREEN に変わる RED テスト

注意: ac-verify コメントに「PID/cwd/reconnect 記録なし」という否定文が存在するが、
これは証跡ではない。以下の具体的なパターンで検証する:
  - cwd 証跡: "worktrees/" を含むパス文字列（例: worktrees/feat/1596-...）
  - PID 証跡: "PID:" または "pid:" に続く 4 桁以上の数値
  - reconnect 証跡: "reconnect" / "session 復帰" / "OK" など肯定的確認表現
                    ただし「記録なし」「Deferred」を含む行は除外する
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

# Issue / PR 番号
_ISSUE_NUM = 1588
_PR_NUM = 1595

# worktree cwd の証跡パターン: "worktrees/<branch>/" 形式（実際の cwd パス）
# ac-verify コメントの "worktree portability smoke" や "worktrees/" 単体とは区別可能
_WORKTREE_CWD_PATTERN = re.compile(r"worktrees/[^/\s]+")

# PID の証跡パターン: "PID:" や "pid:" に続く 4 桁以上の数値
# ac-verify コメントの "PID/cwd/reconnect" はスラッシュで続くため区別可能
_PID_PATTERN = re.compile(r"\bpid[:\s]+\d{4,}", re.IGNORECASE)

# reconnect 確認の肯定的証跡パターン
# 「記録なし」「Deferred」を含む行は除外
_RECONNECT_POSITIVE_PATTERNS = [
    re.compile(r"reconnect.*ok", re.IGNORECASE),
    re.compile(r"session.{0,20}(復帰|reconnect).{0,30}(ok|確認|成功)", re.IGNORECASE),
    re.compile(r"(ok|確認|成功).{0,30}(reconnect|session.*復帰)", re.IGNORECASE),
]
# 否定文のある行（これらが含まれる行は証跡とみなさない）
_NEGATIVE_LINE_PATTERNS = [
    "記録なし",
    "Deferred",
    "手動確認要",
    "not found",
    "missing",
]


def _gh_available() -> bool:
    """GitHub CLI が利用可能かどうかを確認する。"""
    try:
        result = subprocess.run(
            ["gh", "--version"],
            capture_output=True,
            timeout=10,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _fetch_issue_comments(issue_num: int) -> str:
    """gh issue view --comments でコメント本文を取得する。"""
    result = subprocess.run(
        ["gh", "issue", "view", str(issue_num), "--comments", "--repo", "shuu5/twill"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        pytest.skip(f"gh issue view {issue_num} が失敗: {result.stderr}")
    return result.stdout


def _fetch_pr_body(pr_num: int) -> str:
    """gh pr view で PR body を取得する。"""
    result = subprocess.run(
        ["gh", "pr", "view", str(pr_num), "--repo", "shuu5/twill"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        pytest.skip(f"gh pr view {pr_num} が失敗: {result.stderr}")
    return result.stdout


def _filter_positive_lines(text: str) -> str:
    """否定文（記録なし・Deferred 等）を含む行を除去して返す。

    ac-verify コメントの否定文がキーワードとして誤マッチしないよう除外する。
    """
    lines = text.splitlines()
    positive_lines = [
        line for line in lines
        if not any(neg in line for neg in _NEGATIVE_LINE_PATTERNS)
    ]
    return "\n".join(positive_lines)


# ===========================================================================
# AC1: worktree cwd での twl mcp restart 実行（process AC: コメント記録が証跡）
# ===========================================================================


class TestAC1ProcessVerification:
    """AC1: worktree cwd から twl mcp restart を実行し新 PID / session reconnect を確認する。

    このテストは process AC の「証跡」検証テストであり、
    「GitHub コメントに記録されているか」を機械チェックする。
    コメント投稿が完了するまでは FAIL（RED）状態となる。

    否定文除外ポリシー:
      ac-verify コメントに「PID/cwd/reconnect 記録なし → Deferred Issue #1596」という
      文字列が存在するが、これは証跡ではない。
      _filter_positive_lines() で「記録なし」「Deferred」「手動確認要」を含む行を除外してから検証する。
    """

    def test_ac1_gh_cli_available(self):
        # AC: gh コマンドが利用可能（テスト前提条件）
        # RED: gh が見つからない場合は skip（offline CI 等）
        if not _gh_available():
            pytest.skip("gh CLI が利用できないため、このテストをスキップする")

    def test_ac1_issue_comment_or_pr_body_contains_worktree_cwd_path(self):
        """Issue #1588 コメントまたは PR #1595 body に 'worktrees/' パスが含まれること。

        AC2 要件: 実行 cwd が worktrees/<branch>/ であることを記録する。
        否定文除外: 「記録なし」「Deferred」を含む行は除外してから検証する。
        """
        # AC: worktree cwd（worktrees/ パス形式）の実行記録が存在する
        # RED: コメント投稿前はパス形式の記録が見つからず FAIL する
        if not _gh_available():
            pytest.skip("gh CLI が利用できないため、このテストをスキップする")

        issue_text = _fetch_issue_comments(_ISSUE_NUM)
        pr_text = _fetch_pr_body(_PR_NUM)
        # 否定文を含む行（ac-verify の「記録なし」等）を除外
        combined_positive = _filter_positive_lines(issue_text + "\n" + pr_text)

        assert _WORKTREE_CWD_PATTERN.search(combined_positive) is not None, (
            f"Issue #{_ISSUE_NUM} コメントまたは PR #{_PR_NUM} body に "
            f"'worktrees/' パスが見つからない（否定文行は除外済み）。\n"
            f"AC2 要件: 実行 cwd（例: worktrees/feat/1596-...）を記録すること。\n"
            f"Issue コメントに worktree smoke test 結果を投稿してください。\n"
            f"例: 'cwd: /home/user/project/worktrees/feat/1596-...' を含むコメント"
        )

    def test_ac1_issue_comment_or_pr_body_contains_pid_value(self):
        """Issue #1588 コメントまたは PR #1595 body に PID 数値が含まれること。

        AC2 要件: 新 PID が立ち上がったことを記録する。
        否定文除外: 「記録なし」「Deferred」を含む行は除外してから検証する。
        パターン: "PID: 12345" または "pid: 12345" 形式（4 桁以上の数値）
        """
        # AC: 新 PID 数値の記録が存在する
        # RED: コメント投稿前は PID: <数値> が見つからず FAIL する
        if not _gh_available():
            pytest.skip("gh CLI が利用できないため、このテストをスキップする")

        issue_text = _fetch_issue_comments(_ISSUE_NUM)
        pr_text = _fetch_pr_body(_PR_NUM)
        # 否定文を含む行（ac-verify の「記録なし」等）を除外
        combined_positive = _filter_positive_lines(issue_text + "\n" + pr_text)

        assert _PID_PATTERN.search(combined_positive) is not None, (
            f"Issue #{_ISSUE_NUM} コメントまたは PR #{_PR_NUM} body に "
            f"PID 数値（例: 'PID: 12345'）が見つからない（否定文行は除外済み）。\n"
            f"AC2 要件: 新 PID（`twl mcp restart` で立ち上がったサーバー PID）を記録すること。\n"
            f"例: 'New PID: 12345' または '新 PID: 12345' を含むコメントを投稿してください。"
        )

    def test_ac1_issue_comment_or_pr_body_contains_reconnect_evidence(self):
        """Issue #1588 コメントまたは PR #1595 body に session reconnect の肯定的証跡が含まれること。

        AC2 要件: session 復帰確認を記録する。
        否定文除外: 「記録なし」「Deferred」を含む行は除外してから検証する。
        """
        # AC: session reconnect 確認の肯定的記録が存在する
        # RED: コメント投稿前は reconnect の肯定的記録が見つからず FAIL する
        if not _gh_available():
            pytest.skip("gh CLI が利用できないため、このテストをスキップする")

        issue_text = _fetch_issue_comments(_ISSUE_NUM)
        pr_text = _fetch_pr_body(_PR_NUM)
        # 否定文を含む行（ac-verify の「記録なし」等）を除外
        combined_positive = _filter_positive_lines(issue_text + "\n" + pr_text)

        reconnect_found = any(
            pattern.search(combined_positive) for pattern in _RECONNECT_POSITIVE_PATTERNS
        )
        assert reconnect_found, (
            f"Issue #{_ISSUE_NUM} コメントまたは PR #{_PR_NUM} body に "
            f"session reconnect の肯定的証跡が見つからない（否定文行は除外済み）。\n"
            f"期待パターン: 'reconnect OK' / 'session 復帰 確認' 等\n"
            f"AC2 要件: session 復帰確認（reconnect または session 復帰）を記録すること。"
        )


# ===========================================================================
# AC2: 手順と結果の記録（process AC: GitHub コメントが証跡）
# ===========================================================================


class TestAC2GithubCommentRecord:
    """AC2: 手順と結果（実行 cwd・出力 PID・session reconnect 確認）が Issue または PR に記録されること。

    このクラスは Issue #1588 AC2 の「検証記録の存在確認」を行う。
    worktree smoke test の実施内容（cwd・PID・reconnect）を 1 ケース分まとめて検証する。

    否定文除外ポリシー:
      ac-verify コメントに「PID/cwd/reconnect 記録なし → Deferred Issue #1596」という
      否定文が存在する。これを誤って証跡とみなさないよう、
      _filter_positive_lines() で否定文行を除外してから検証する。
    """

    def test_ac2_issue_1588_has_smoke_test_comment(self):
        """Issue #1588 のコメントに worktree smoke test の記録が存在すること。

        GitHub CLI なし環境では NotImplementedError を raise して明示的 RED にする。
        """
        # AC: Issue #1588 に worktree smoke test の手動検証記録が存在する
        # RED: 実装（= コメント投稿）前は fail する
        #
        # process AC のため、テストは 2 段構え:
        #   1. gh が利用可能: 実際にコメントを取得して証跡パターンを検証（否定文除外）
        #   2. gh が利用不可: pytest.skip で skip（TestAC1 と同一ポリシー）
        if not _gh_available():
            pytest.skip(
                "gh CLI が利用できないため、このテストをスキップする。\n"
                "AC2 (#1596) の手動検証: worktree cwd で twl mcp restart を実行し "
                "Issue #1588 にコメントを投稿してください。"
            )

        issue_text = _fetch_issue_comments(_ISSUE_NUM)
        # 否定文行を除外してから判定
        positive_text = _filter_positive_lines(issue_text)

        has_worktree_cwd = _WORKTREE_CWD_PATTERN.search(positive_text) is not None
        has_pid = _PID_PATTERN.search(positive_text) is not None
        has_reconnect = any(
            pattern.search(positive_text) for pattern in _RECONNECT_POSITIVE_PATTERNS
        )

        missing = []
        if not has_worktree_cwd:
            missing.append("実行 cwd (worktrees/<branch>/ パス形式)")
        if not has_pid:
            missing.append("新 PID 数値 (例: PID: 12345)")
        if not has_reconnect:
            missing.append("session reconnect 確認の肯定文 (例: reconnect OK)")

        assert not missing, (
            f"Issue #{_ISSUE_NUM} のコメントに以下の記録が不足している（否定文行は除外済み）:\n"
            + "\n".join(f"  - {m}" for m in missing)
            + f"\n\nAC2 要件: worktree cwd・新 PID・session reconnect 確認を記録すること。\n"
            f"Issue #{_ISSUE_NUM} にコメントを投稿してください。"
        )

    def test_ac2_verification_record_completeness(self):
        """worktree smoke test の記録が 3 要件（cwd・PID・reconnect）を満たすこと。

        Issue コメントまたは PR body のどちらかに記録があれば合格とする。
        否定文除外: _filter_positive_lines() で除外後に検証する。
        """
        # AC: Issue #1588 コメントまたは PR #1595 description に全 3 要件の記録が存在する
        # RED: 証跡が揃っていない状態で FAIL する
        if not _gh_available():
            pytest.skip(
                "gh CLI が利用できないため、このテストをスキップする。\n"
                "AC2 (#1596) の手動検証: 3 要件（cwd・PID・reconnect）を Issue または PR に記録してください。"
            )

        issue_text = _fetch_issue_comments(_ISSUE_NUM)
        pr_text = _fetch_pr_body(_PR_NUM)
        # 否定文を含む行（ac-verify の「記録なし」等）を除外
        combined_positive = _filter_positive_lines(issue_text + "\n" + pr_text)

        checks = {
            "実行 cwd (worktrees/ パス形式)": _WORKTREE_CWD_PATTERN.search(combined_positive) is not None,
            "新 PID 数値 (PID: <4桁+>)": _PID_PATTERN.search(combined_positive) is not None,
            "session reconnect 確認の肯定文": any(
                p.search(combined_positive) for p in _RECONNECT_POSITIVE_PATTERNS
            ),
        }

        failed = [label for label, ok in checks.items() if not ok]
        assert not failed, (
            f"worktree smoke test の記録が以下の点で不完全（否定文行は除外済み）:\n"
            + "\n".join(f"  - {f}" for f in failed)
            + f"\n\nIssue #{_ISSUE_NUM} または PR #{_PR_NUM} にコメントを投稿してください。\n"
            f"投稿例:\n"
            f"  cwd: worktrees/feat/1596-... で twl mcp restart を実行\n"
            f"  新 PID: 12345\n"
            f"  session reconnect OK"
        )
