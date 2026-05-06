"""Tests for Issue #1431: observer skill ScheduleWakeup / mailbox poll pattern.

TDD RED phase — all tests fail until implementation is complete.

AC-1: SKILL.md Step 1 に twl_recv_msg polling loop が記述されている
AC-2: mailbox event 受信時の処理が定義されている（spawn 禁止・log+report のみ）
AC-3: ScheduleWakeup を能動 active poll cycle として組み込む手順が記述されている（§11.5 参照リンク明示）
AC-4: observer は spawn 責任を持たないことが SKILL.md に明示されている
AC-5: su-observer-supervise-channels.md に「mailbox poll」channel が追加されている
AC-6: AC 各項目が grep または git diff で機械検証可能（構造的保証テスト）
AC-7: SKILL.md の resume 手順に「mailbox poll loop を再開すること」の記述が含まれる
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parents[3]
SKILL_MD = REPO_ROOT / "plugins/twl/skills/su-observer/SKILL.md"
SUPERVISE_CHANNELS_MD = REPO_ROOT / "plugins/twl/skills/su-observer/refs/su-observer-supervise-channels.md"
PITFALLS_CATALOG_MD = REPO_ROOT / "plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def skill_text() -> str:
    assert SKILL_MD.exists(), f"SKILL.md が存在しない: {SKILL_MD}"
    return SKILL_MD.read_text()


@pytest.fixture(scope="module")
def channels_text() -> str:
    assert SUPERVISE_CHANNELS_MD.exists(), (
        f"su-observer-supervise-channels.md が存在しない: {SUPERVISE_CHANNELS_MD}"
    )
    return SUPERVISE_CHANNELS_MD.read_text()


@pytest.fixture(scope="module")
def pitfalls_text() -> str:
    assert PITFALLS_CATALOG_MD.exists(), (
        f"pitfalls-catalog.md が存在しない: {PITFALLS_CATALOG_MD}"
    )
    return PITFALLS_CATALOG_MD.read_text()


# ---------------------------------------------------------------------------
# AC-1: SKILL.md Step 1 に twl_recv_msg polling loop が記述されている
# ---------------------------------------------------------------------------


class TestAc1TwlRecvMsgInSkillStep1:
    """AC-1: Step 1 常駐ループ内に twl_recv_msg polling loop が記述されている。"""

    def test_ac1_twl_recv_msg_exists_in_skill_md(self, skill_text: str):
        # AC-1: grep 検証可能: `twl_recv_msg` が SKILL.md 内に存在
        # RED: 現在の SKILL.md には twl_recv_msg の記述がない
        assert "twl_recv_msg" in skill_text, (
            "SKILL.md に twl_recv_msg の記述がない。"
            "Step 1 常駐ループに mailbox polling loop を追加する必要がある。"
        )

    def test_ac1_twl_recv_msg_in_step1_section(self, skill_text: str):
        # AC-1: Step 1 セクション内（Step 2 開始前）に twl_recv_msg が存在すること
        # RED: 現在の SKILL.md Step 1 セクションには twl_recv_msg がない
        step1_match = re.search(
            r"## Step 1.*?(?=## Step 2|\Z)",
            skill_text,
            re.DOTALL,
        )
        assert step1_match, "SKILL.md に ## Step 1 セクションが見当たらない"
        step1_text = step1_match.group(0)
        assert "twl_recv_msg" in step1_text, (
            "SKILL.md の Step 1 セクションに twl_recv_msg の記述がない。"
            "常駐ループ内に mailbox polling loop を追加する必要がある。"
        )


# ---------------------------------------------------------------------------
# AC-2: mailbox event 受信時の処理が定義されている（spawn 禁止・log+report のみ）
# ---------------------------------------------------------------------------


class TestAc2MailboxEventHandlingDefined:
    """AC-2: PR-merge event 受領時は intervention-log 記録 + Wave 進捗報告のみ。spawn 禁止を明記。"""

    def test_ac2_mailbox_event_handling_no_spawn(self, skill_text: str):
        # AC-2: mailbox event 受信時に spawn コマンド発行を行わないことが明記されている
        # RED: 現在の SKILL.md には mailbox event 受信時の処理定義がない
        has_mailbox = "mailbox" in skill_text
        assert has_mailbox, (
            "SKILL.md に mailbox event 受信時の処理定義がない。"
            "PR-merge event 受領時の処理フローを追加する必要がある。"
        )

    def test_ac2_intervention_log_on_pr_merge(self, skill_text: str):
        # AC-2: PR-merge event 受信時に intervention-log への記録が明示されている
        # RED: 現在の SKILL.md には PR-merge event に対する intervention-log 記録の記述がない
        has_intervention_log_ref = bool(
            re.search(r"intervention.log", skill_text)
        )
        has_pr_merge_ref = bool(
            re.search(r"PR.merge|pr.merge|PR_merge", skill_text, re.IGNORECASE)
        )
        assert has_intervention_log_ref and has_pr_merge_ref, (
            "SKILL.md に PR-merge event 受信時の intervention-log 記録が明示されていない。"
            f"intervention-log 記述: {has_intervention_log_ref}, "
            f"PR-merge 言及: {has_pr_merge_ref}"
        )

    def test_ac2_no_spawn_on_mailbox_event(self, skill_text: str):
        # AC-2: mailbox event 受信時の spawn 禁止が明記されている
        # RED: 現在の SKILL.md には mailbox event 受信時の spawn 禁止記述がない
        # mailbox event セクションで「spawn コマンド発行を行わない」旨の記述を検証
        mailbox_section_match = re.search(
            r"mailbox.*?(?=\n##|\n###|\Z)",
            skill_text,
            re.DOTALL | re.IGNORECASE,
        )
        assert mailbox_section_match, (
            "SKILL.md に mailbox 関連セクションが存在しない"
        )
        mailbox_section = mailbox_section_match.group(0)
        has_no_spawn_notice = bool(
            re.search(
                r"spawn.*?しない|spawn.*?禁止|spawn.*?発行しない|spawn.*?行わない"
                r"|スポーン.*?禁止",
                mailbox_section,
            )
        )
        assert has_no_spawn_notice, (
            "SKILL.md の mailbox セクションに spawn 禁止の記述がない"
        )


# ---------------------------------------------------------------------------
# AC-3: ScheduleWakeup を能動 active poll cycle として組み込む手順が記述されている
# ---------------------------------------------------------------------------


class TestAc3ScheduleWakeupActivePollCycle:
    """AC-3: ScheduleWakeup 手順が SKILL.md または refs に記述され、pitfalls-catalog.md §11.5 を参照リンクで明示。"""

    def test_ac3_schedulewakeup_in_skill_or_refs(self, skill_text: str, pitfalls_text: str):
        # AC-3: ScheduleWakeup が SKILL.md または pitfalls-catalog.md に記述されている
        # pitfalls-catalog.md §11.5 には既に ScheduleWakeup の記述がある
        has_schedulewakeup_in_skill = "ScheduleWakeup" in skill_text
        has_schedulewakeup_in_pitfalls = "ScheduleWakeup" in pitfalls_text
        assert has_schedulewakeup_in_skill or has_schedulewakeup_in_pitfalls, (
            "SKILL.md および pitfalls-catalog.md のいずれにも ScheduleWakeup の記述がない"
        )

    def test_ac3_pitfalls_section_11_5_referenced_in_skill(self, skill_text: str):
        # AC-3: SKILL.md に pitfalls-catalog.md §11.5 への参照リンクが明示されている
        # RED: 現在の SKILL.md には pitfalls-catalog.md §11.5 への参照がない
        has_11_5_ref = bool(
            re.search(
                r"pitfalls.catalog.*?§\s*11\.5|§\s*11\.5.*?pitfalls.catalog"
                r"|pitfalls-catalog\.md.*?11\.5|11\.5.*?pitfalls-catalog",
                skill_text,
                re.IGNORECASE,
            )
        )
        assert has_11_5_ref, (
            "SKILL.md に pitfalls-catalog.md §11.5 (ScheduleWakeup) への参照リンクがない。"
            "ScheduleWakeup を能動 active poll cycle として組み込む手順に §11.5 参照を追加する必要がある。"
        )

    def test_ac3_active_poll_cycle_described(self, skill_text: str):
        # AC-3: SKILL.md に active poll cycle としての組み込み手順が記述されている
        # RED: 現在の SKILL.md には active poll cycle の記述がない
        has_active_poll = bool(
            re.search(
                r"active\s+poll|polling\s+cycle|poll\s+cycle|active.*?poll.*?cycle",
                skill_text,
                re.IGNORECASE,
            )
        )
        assert has_active_poll, (
            "SKILL.md に active poll cycle としての ScheduleWakeup 組み込み手順がない"
        )


# ---------------------------------------------------------------------------
# AC-4: observer は spawn 責任を持たないことが SKILL.md に明示されている
# ---------------------------------------------------------------------------


class TestAc4ObserverNoSpawnResponsibility:
    """AC-4: 'spawn 責任は wave-progress-watchdog (S3) 単独' 旨の文言が SKILL.md に含まれる。"""

    def test_ac4_spawn_responsibility_not_observer(self, skill_text: str):
        # AC-4: spawn 責任を observer が持たないことが SKILL.md に明示されている
        # RED: 現在の SKILL.md には spawn 責任の帰属に関する明示的記述がない
        has_spawn_responsibility = bool(
            re.search(
                r"spawn\s*責任.*?wave.progress.watchdog"
                r"|wave.progress.watchdog.*?spawn\s*責任"
                r"|spawn\s*責任.*?S3"
                r"|S3.*?spawn\s*責任",
                skill_text,
            )
        )
        assert has_spawn_responsibility, (
            "SKILL.md に 'spawn 責任は wave-progress-watchdog (S3) 単独' 旨の文言がない。"
            "observer が spawn 責任を持たないことを明示する必要がある。"
        )

    def test_ac4_wave_progress_watchdog_s3_mentioned(self, skill_text: str):
        # AC-4: wave-progress-watchdog と (S3) の言及が SKILL.md に存在する
        # RED: 現在の SKILL.md には wave-progress-watchdog の記述がない
        has_wpw = "wave-progress-watchdog" in skill_text
        assert has_wpw, (
            "SKILL.md に wave-progress-watchdog の言及がない。"
            "spawn 責任の帰属を明示するため wave-progress-watchdog (S3) を記述する必要がある。"
        )


# ---------------------------------------------------------------------------
# AC-5: su-observer-supervise-channels.md に「mailbox poll」channel が追加されている
# ---------------------------------------------------------------------------


class TestAc5MailboxPollChannelAdded:
    """AC-5: su-observer-supervise-channels.md の supervise channel テーブルに mailbox poll が追加されている。"""

    def test_ac5_mailbox_poll_channel_in_table(self, channels_text: str):
        # AC-5: channels テーブルに mailbox poll channel が追加されている
        # RED: 現在の su-observer-supervise-channels.md には mailbox poll の記述がない
        # テーブル用語列に限定してマッチ（| mailbox poll | 形式）
        has_mailbox_poll_in_table = bool(
            re.search(r"\|\s*mailbox\s+poll\s*\|", channels_text, re.IGNORECASE)
        )
        assert has_mailbox_poll_in_table, (
            "su-observer-supervise-channels.md のチャンネルテーブルに "
            "'mailbox poll' エントリ（| mailbox poll | 形式）がない。"
            "既存の supervise channel 列挙に追加する必要がある。"
        )

    def test_ac5_mailbox_poll_has_purpose_description(self, channels_text: str):
        # AC-5: mailbox poll channel に目的の記述がある
        # RED: 現在の channels.md には mailbox の記述がない
        has_mailbox = "mailbox" in channels_text.lower()
        assert has_mailbox, (
            "su-observer-supervise-channels.md に mailbox の記述がない。"
            "mailbox poll channel を追加する必要がある。"
        )


# ---------------------------------------------------------------------------
# AC-6: AC 各項目が grep または git diff で機械検証可能（構造的保証テスト）
# ---------------------------------------------------------------------------


class TestAc6MachineVerifiable:
    """AC-6: AC 全項目が grep で機械検証可能な形式で記述されている（文書構造の保証）。"""

    def test_ac6_skill_md_exists_and_readable(self):
        # AC-6: SKILL.md が存在して読み取り可能である
        assert SKILL_MD.exists(), f"SKILL.md が存在しない: {SKILL_MD}"
        content = SKILL_MD.read_text()
        assert len(content) > 0, "SKILL.md が空ファイルである"

    def test_ac6_channels_md_exists_and_readable(self):
        # AC-6: su-observer-supervise-channels.md が存在して読み取り可能である
        assert SUPERVISE_CHANNELS_MD.exists(), (
            f"su-observer-supervise-channels.md が存在しない: {SUPERVISE_CHANNELS_MD}"
        )
        content = SUPERVISE_CHANNELS_MD.read_text()
        assert len(content) > 0, "su-observer-supervise-channels.md が空ファイルである"

    def test_ac6_pitfalls_catalog_md_has_section_11_5(self, pitfalls_text: str):
        # AC-6: pitfalls-catalog.md に §11.5 セクションが存在する（参照先の存在確認）
        has_11_5 = bool(
            re.search(r"11\.5\s+ScheduleWakeup", pitfalls_text)
        )
        assert has_11_5, (
            "pitfalls-catalog.md に §11.5 ScheduleWakeup セクションが存在しない。"
            "AC-3 の参照リンク先として §11.5 が必要。"
        )


# ---------------------------------------------------------------------------
# AC-7: SKILL.md の resume 手順に「mailbox poll loop を再開すること」の記述が含まれる
# ---------------------------------------------------------------------------


class TestAc7ResumeProcedureIncludesMailboxRestart:
    """AC-7: SKILL.md の resume 手順（Step 0 または SessionStart hook 相当）に mailbox poll loop 再開の記述がある。"""

    def test_ac7_resume_and_mailbox_in_proximity(self, skill_text: str):
        # AC-7: `resume` + `mailbox` or `recv_msg` が近傍（200 文字以内）に存在する
        # RED: 現在の SKILL.md には resume 手順内に mailbox/recv_msg の記述がない
        # resume が出現する前後 200 文字以内に mailbox または recv_msg があるかを確認
        resume_positions = [m.start() for m in re.finditer(r"resume", skill_text, re.IGNORECASE)]
        assert resume_positions, "SKILL.md に 'resume' という単語が見当たらない"

        found_proximity = False
        for pos in resume_positions:
            window_start = max(0, pos - 200)
            window_end = min(len(skill_text), pos + 200)
            window = skill_text[window_start:window_end]
            if re.search(r"mailbox|recv_msg", window, re.IGNORECASE):
                found_proximity = True
                break

        assert found_proximity, (
            "SKILL.md の resume 記述近傍（±200 文字）に mailbox または recv_msg の記述がない。"
            "resume 手順に 'mailbox poll loop を再開すること' を追加する必要がある。"
        )

    def test_ac7_resume_section_exists_in_step0(self, skill_text: str):
        # AC-7: Step 0 セクション内に resume に関する記述が存在する
        # RED: 現在の SKILL.md Step 0 には mailbox poll loop 再開の手順がない
        step0_match = re.search(
            r"## Step 0.*?(?=## Step 1|\Z)",
            skill_text,
            re.DOTALL,
        )
        assert step0_match, "SKILL.md に ## Step 0 セクションが見当たらない"
        step0_text = step0_match.group(0)
        has_mailbox_resume = bool(
            re.search(r"mailbox|recv_msg", step0_text, re.IGNORECASE)
        )
        assert has_mailbox_resume, (
            "SKILL.md の Step 0 セクションに mailbox / recv_msg 関連の resume 手順がない。"
            "SessionStart hook または Step 0 相当の箇所に mailbox poll loop 再開の記述を追加する必要がある。"
        )
