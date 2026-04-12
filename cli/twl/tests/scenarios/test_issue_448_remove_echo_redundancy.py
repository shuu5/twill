"""Tests for Issue #448: change-propose.md Step 0 auto_init echo 補完削除.

Spec: deltaspec/changes/issue-448/specs/remove-echo-redundancy/spec.md

Coverage:

  Requirement: Step 0 auto_init フローの echo 補完削除
    - Scenario: twl spec new 呼出後に echo 補完が存在しない
        WHEN: change-propose.md の Step 0 auto_init フローを参照する
        THEN: `echo "name: ..." >> .deltaspec.yaml` および
              `echo "status: ..." >> .deltaspec.yaml` の行が存在しない

    - Scenario: twl spec new の自動補完を説明するコメントが存在する
        WHEN: change-propose.md の Step 0 内の `twl spec new "issue-<N>"` 呼出直後を参照する
        THEN: `twl spec new` が issue 番号・name・status を自動補完することを説明する
              コメントが存在する

  Requirement: .deltaspec.yaml への重複エントリ防止
    - Scenario: issue-N 形式の change 作成後に .deltaspec.yaml が重複なし (integration)
        WHEN: twl spec new "issue-<N>" を実行する
        THEN: .deltaspec.yaml に name:, status:, issue: が各 1 回のみ存在する

  Edge cases (--coverage=edge-cases):
    - echo 行が部分一致（コメントなど）しても誤検知しないこと
    - 空の .deltaspec.yaml に対して cmd_new が正常に動作すること
    - issue-0 のような境界値 issue 番号でも重複なし
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.new import cmd_new


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# change-propose.md へのパス（リポジトリルート相対）
# conftest.py が sys.path を調整しているが、ファイルパスはこのテストファイルから算出する
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent.parent
_CHANGE_PROPOSE_MD = _REPO_ROOT / "plugins" / "twl" / "commands" / "change-propose.md"

# Step 0 auto_init セクション（### Step 0 から 次の ### Step まで）を抽出する正規表現
_STEP0_RE = re.compile(
    r"### Step 0:.*?(?=### Step [^0]|\Z)",
    re.DOTALL,
)

# echo 補完行のパターン: `echo "name: ...`  or  `echo "status: ...` が .deltaspec.yaml へ append
_ECHO_NAME_RE = re.compile(r'echo\s+"name:\s*[^"]*"\s*>>\s*\S*\.deltaspec\.yaml')
_ECHO_STATUS_RE = re.compile(r'echo\s+"status:\s*[^"]*"\s*>>\s*\S*\.deltaspec\.yaml')

# twl spec new 呼出行のパターン
_SPEC_NEW_RE = re.compile(r'twl\s+spec\s+new\s+"issue-')


def _load_step0_content() -> str:
    """change-propose.md から Step 0 セクションのテキストを抽出して返す。"""
    assert _CHANGE_PROPOSE_MD.exists(), (
        f"change-propose.md が見つかりません: {_CHANGE_PROPOSE_MD}\n"
        "テスト対象ファイルが存在することを確認してください。"
    )
    content = _CHANGE_PROPOSE_MD.read_text(encoding="utf-8")
    m = _STEP0_RE.search(content)
    assert m is not None, "change-propose.md に '### Step 0:' セクションが見つかりません"
    return m.group(0)


def make_project(tmp_path: Path) -> Path:
    """最小限の deltaspec プロジェクト構造を作成する。"""
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    (tmp_path / "deltaspec" / "config.yaml").write_text(
        "schema: spec-driven\ncontext: {}\n", encoding="utf-8"
    )
    return tmp_path


# ===========================================================================
# Requirement: Step 0 auto_init フローの echo 補完削除
# ===========================================================================


class TestEchoCompletionRemoved:
    """Requirement: Step 0 auto_init フローの echo 補完削除

    change-propose.md の Step 0 auto_init フローに echo による手動補完行が
    存在しないことを確認する（Markdown コンテンツ検証）。
    """

    # ------------------------------------------------------------------
    # Scenario: twl spec new 呼出後に echo 補完が存在しない
    # WHEN: change-propose.md の Step 0 auto_init フローを参照する
    # THEN: `echo "name: ..." >> .deltaspec.yaml` および
    #       `echo "status: ..." >> .deltaspec.yaml` の行が存在しない
    # ------------------------------------------------------------------

    def test_echo_name_line_absent_in_step0(self) -> None:
        """WHEN Step 0 を参照 THEN `echo "name: ..." >> .deltaspec.yaml` が存在しない。"""
        step0 = _load_step0_content()
        matches = _ECHO_NAME_RE.findall(step0)
        assert matches == [], (
            "Step 0 に `echo \"name: ...\" >> .deltaspec.yaml` 行が残っています。\n"
            f"削除が必要な行: {matches}"
        )

    def test_echo_status_line_absent_in_step0(self) -> None:
        """WHEN Step 0 を参照 THEN `echo "status: ..." >> .deltaspec.yaml` が存在しない。"""
        step0 = _load_step0_content()
        matches = _ECHO_STATUS_RE.findall(step0)
        assert matches == [], (
            "Step 0 に `echo \"status: ...\" >> .deltaspec.yaml` 行が残っています。\n"
            f"削除が必要な行: {matches}"
        )

    def test_neither_echo_name_nor_echo_status_present(self) -> None:
        """WHEN Step 0 を参照 THEN echo による name/status 補完行がどちらも存在しない。"""
        step0 = _load_step0_content()
        name_matches = _ECHO_NAME_RE.findall(step0)
        status_matches = _ECHO_STATUS_RE.findall(step0)
        assert name_matches == [] and status_matches == [], (
            f"name echo 行: {name_matches}, status echo 行: {status_matches}"
        )

    def test_echo_append_pattern_not_present_for_deltaspec_yaml(self) -> None:
        """Edge case: `.deltaspec.yaml` への echo append がコード例として残っていないこと。

        コメント内の記述例も含め、echo >> .deltaspec.yaml 形式の行が Step 0 にないことを確認。
        """
        step0 = _load_step0_content()
        # より広いパターン: echo ... >> ... .deltaspec.yaml
        broad_echo_re = re.compile(r'echo\s+["\']?(name|status):', re.IGNORECASE)
        matches = [line for line in step0.splitlines() if broad_echo_re.search(line)]
        assert matches == [], (
            "Step 0 に echo name:/status: パターンの行が残存しています:\n"
            + "\n".join(f"  {line}" for line in matches)
        )


# ===========================================================================
# Requirement: Step 0 auto_init フローの echo 補完削除
# （コメント追加確認）
# ===========================================================================


class TestAutoCompletionCommentPresent:
    """Requirement: twl spec new 自動補完コメントの存在確認

    twl spec new 呼出後に、name/status/issue の自動補完を説明するコメントが
    存在することを確認する（Markdown コンテンツ検証）。
    """

    # ------------------------------------------------------------------
    # Scenario: twl spec new の自動補完を説明するコメントが存在する
    # WHEN: change-propose.md の Step 0 内の `twl spec new "issue-<N>"` 呼出直後を参照する
    # THEN: twl spec new が issue 番号・name・status を自動補完することを説明する
    #       コメントが存在する
    # ------------------------------------------------------------------

    def test_auto_completion_comment_exists_after_spec_new(self) -> None:
        """WHEN Step 0 の `twl spec new` 呼出直後を参照 THEN 自動補完コメントが存在する。"""
        step0 = _load_step0_content()

        # twl spec new 呼出行を探し、その後に自動補完に言及するテキストがあるか確認
        spec_new_pos = step0.find("twl spec new")
        assert spec_new_pos != -1, "Step 0 に `twl spec new` 呼出が見つかりません"

        # twl spec new 呼出より後の内容を検索対象とする
        after_spec_new = step0[spec_new_pos:]

        # 自動補完に言及するキーワードを確認（日本語・英語どちらでも可）
        auto_complete_keywords = [
            "自動補完",
            "auto",
            "automatically",
            "automatically fills",
            "fills in",
        ]
        has_comment = any(kw in after_spec_new for kw in auto_complete_keywords)
        assert has_comment, (
            "`twl spec new` 呼出後に自動補完を説明するコメントが見つかりません。\n"
            "キーワード候補: " + ", ".join(repr(k) for k in auto_complete_keywords) + "\n"
            "Step 0 の該当箇所:\n" + after_spec_new[:500]
        )

    def test_auto_completion_comment_mentions_name_or_status(self) -> None:
        """WHEN 自動補完コメントを参照 THEN name または status フィールドに言及している。"""
        step0 = _load_step0_content()
        spec_new_pos = step0.find("twl spec new")
        assert spec_new_pos != -1, "Step 0 に `twl spec new` 呼出が見つかりません"
        after_spec_new = step0[spec_new_pos:]

        # name か status のどちらかに言及していること
        mentions_field = "name" in after_spec_new or "status" in after_spec_new
        assert mentions_field, (
            "自動補完コメントに `name` または `status` フィールドへの言及がありません。\n"
            "Step 0 (twl spec new 以降):\n" + after_spec_new[:500]
        )

    def test_step0_retains_spec_new_call(self) -> None:
        """WHEN Step 0 を参照 THEN `twl spec new "issue-<N>"` 呼出が存在する。

        リファクタリング後も twl spec new 自体は削除されていないことを確認。
        """
        step0 = _load_step0_content()
        assert _SPEC_NEW_RE.search(step0) is not None, (
            "Step 0 に `twl spec new \"issue-<N>\"` 呼出が見つかりません。"
        )

    def test_no_manual_echo_replaced_by_comment_not_new_code(self) -> None:
        """Edge case: echo 削除後に別の手動補完コードが追加されていないこと。

        echo を別のファイル書き込みコード（python/awk など）に置き換えていないことを確認。
        """
        step0 = _load_step0_content()
        # 許容しない代替パターン: name: や status: を .deltaspec.yaml に書き込む命令
        # bash の printf/tee 経由での書き込みも禁止
        forbidden_patterns = [
            re.compile(r'printf\s+["\']name:'),
            re.compile(r'printf\s+["\']status:'),
            re.compile(r'tee\s+-a\s+\S*\.deltaspec\.yaml'),
            re.compile(r'python.*name.*\.deltaspec\.yaml'),
        ]
        violations: list[str] = []
        for line in step0.splitlines():
            for pat in forbidden_patterns:
                if pat.search(line):
                    violations.append(line.strip())

        assert violations == [], (
            "Step 0 に echo 以外の手動フィールド書き込みが検出されました:\n"
            + "\n".join(f"  {v}" for v in violations)
        )


# ===========================================================================
# Requirement: .deltaspec.yaml への重複エントリ防止 (integration)
# ===========================================================================


class TestDeltaspecYamlNoDuplicates:
    """Requirement: .deltaspec.yaml への重複エントリ防止

    `twl spec new "issue-<N>"` 実行後に .deltaspec.yaml に name:, status:, issue: が
    各 1 回のみ存在することを統合テストで確認する。
    """

    # ------------------------------------------------------------------
    # Scenario: issue-N 形式の change 作成後に .deltaspec.yaml が重複なし
    # WHEN: change-propose.md の Step 0 フローに従い `twl spec new "issue-<N>"` を実行する
    # THEN: .deltaspec.yaml に name:, status:, issue: が各 1 回のみ存在する
    # ------------------------------------------------------------------

    @pytest.fixture()
    def yaml_content_448(self, tmp_path: Path, monkeypatch) -> str:
        """issue-448 で twl spec new を実行し .deltaspec.yaml の内容を返す共通フィクスチャ。"""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-448")
        assert rc == 0
        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-448" / ".deltaspec.yaml"
        assert yaml_path.exists(), ".deltaspec.yaml が作成されていません"
        return yaml_path.read_text(encoding="utf-8")

    def test_name_field_appears_exactly_once(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN .deltaspec.yaml に name: が 1 回のみ存在する。"""
        name_lines = [line for line in yaml_content_448.splitlines() if line.startswith("name:")]
        assert len(name_lines) == 1, (
            f"name: フィールドが {len(name_lines)} 回存在します（期待: 1 回）\n"
            f"内容:\n{yaml_content_448}"
        )

    def test_status_field_appears_exactly_once(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN .deltaspec.yaml に status: が 1 回のみ存在する。"""
        status_lines = [line for line in yaml_content_448.splitlines() if line.startswith("status:")]
        assert len(status_lines) == 1, (
            f"status: フィールドが {len(status_lines)} 回存在します（期待: 1 回）\n"
            f"内容:\n{yaml_content_448}"
        )

    def test_issue_field_appears_exactly_once(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN .deltaspec.yaml に issue: が 1 回のみ存在する。"""
        issue_lines = [line for line in yaml_content_448.splitlines() if line.startswith("issue:")]
        assert len(issue_lines) == 1, (
            f"issue: フィールドが {len(issue_lines)} 回存在します（期待: 1 回）\n"
            f"内容:\n{yaml_content_448}"
        )

    def test_all_three_fields_appear_exactly_once(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN name:, status:, issue: が各 1 回のみ存在する。"""
        lines = yaml_content_448.splitlines()
        for field in ("name:", "status:", "issue:"):
            field_lines = [line for line in lines if line.startswith(field)]
            assert len(field_lines) == 1, (
                f"'{field}' フィールドが {len(field_lines)} 回存在します（期待: 1 回）\n"
                f"内容:\n{yaml_content_448}"
            )

    def test_no_duplicates_after_spec_new_issue_1(self, tmp_path: Path, monkeypatch) -> None:
        """Edge case: WHEN twl spec new 'issue-1' THEN 最小 issue 番号でも重複なし。"""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-1")
        assert rc == 0

        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-1" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        lines = content.splitlines()

        for field in ("name:", "status:", "issue:"):
            count = sum(1 for line in lines if line.startswith(field))
            assert count == 1, (
                f"'issue-1' の .deltaspec.yaml: '{field}' が {count} 回 (期待: 1 回)\n"
                f"内容:\n{content}"
            )

    def test_no_duplicates_after_spec_new_large_issue_number(
        self, tmp_path: Path, monkeypatch
    ) -> None:
        """Edge case: WHEN twl spec new 'issue-9999' THEN 大きな issue 番号でも重複なし。"""
        monkeypatch.chdir(make_project(tmp_path))
        rc = cmd_new("issue-9999")
        assert rc == 0

        yaml_path = tmp_path / "deltaspec" / "changes" / "issue-9999" / ".deltaspec.yaml"
        content = yaml_path.read_text(encoding="utf-8")
        lines = content.splitlines()

        for field in ("name:", "status:", "issue:"):
            count = sum(1 for line in lines if line.startswith(field))
            assert count == 1, (
                f"'issue-9999' の .deltaspec.yaml: '{field}' が {count} 回 (期待: 1 回)\n"
                f"内容:\n{content}"
            )

    def test_name_value_matches_change_id(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN name: の値が 'issue-448' である。"""
        assert "name: issue-448" in yaml_content_448, (
            f"name: フィールドの値が 'issue-448' ではありません\n内容:\n{yaml_content_448}"
        )

    def test_status_value_is_pending(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN status: の値が 'pending' である。"""
        assert "status: pending" in yaml_content_448, (
            f"status: フィールドの値が 'pending' ではありません\n内容:\n{yaml_content_448}"
        )

    def test_issue_number_extracted_correctly(self, yaml_content_448: str) -> None:
        """WHEN twl spec new 'issue-448' THEN issue: の値が 448 である。"""
        assert "issue: 448" in yaml_content_448, (
            f"issue: フィールドの値が 448 ではありません\n内容:\n{yaml_content_448}"
        )
