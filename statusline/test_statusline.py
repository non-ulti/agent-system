import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import statusline as sl

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def strip(s):
    return ANSI.sub("", s)


class TestStatusline(unittest.TestCase):
    def test_format_tokens(self):
        self.assertEqual(sl.format_tokens(None), "—")
        self.assertEqual(sl.format_tokens(0), "0")
        self.assertEqual(sl.format_tokens(500), "500")
        self.assertEqual(sl.format_tokens(999), "999")
        self.assertEqual(sl.format_tokens(1000), "1k")
        self.assertEqual(sl.format_tokens(1500), "1.5k")
        self.assertEqual(sl.format_tokens(15000), "15k")
        self.assertEqual(sl.format_tokens(15500), "15.5k")
        self.assertEqual(sl.format_tokens(1_200_000), "1.2M")
        self.assertEqual(sl.format_tokens(2_000_000), "2M")

    def test_bar_fill(self):
        self.assertEqual(sl.bar_fill(0), 0)
        self.assertEqual(sl.bar_fill(8), 2)     # 0.08*20=1.6 -> round 2
        self.assertEqual(sl.bar_fill(50), 10)
        self.assertEqual(sl.bar_fill(80), 16)
        self.assertEqual(sl.bar_fill(100), 20)
        self.assertEqual(sl.bar_fill(120), 20)  # 클램프
        self.assertEqual(sl.bar_fill(-5), 0)    # 클램프

    def test_pick_color(self):
        self.assertEqual(sl.pick_color(0), sl.GREEN)
        self.assertEqual(sl.pick_color(49), sl.GREEN)
        self.assertEqual(sl.pick_color(50), sl.ORANGE)
        self.assertEqual(sl.pick_color(79), sl.ORANGE)
        self.assertEqual(sl.pick_color(80), sl.RED)
        self.assertEqual(sl.pick_color(100), sl.RED)

    def test_make_bar(self):
        bar = sl.make_bar(8)
        # 색코드 제거 후 20칸, 앞 2칸 채움
        self.assertEqual(strip(bar), "██" + "░" * 18)
        self.assertIn(sl.GREEN, bar)  # 8% -> 초록


    def test_branch_from_worktree(self):
        data = {"workspace": {"git_worktree": "feature-x"}}
        self.assertEqual(sl.branch_from_worktree(data), "feature-x")
        self.assertIsNone(sl.branch_from_worktree({}))
        self.assertIsNone(sl.branch_from_worktree({"workspace": {}}))

    def test_branch_from_git_non_repo(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(sl.branch_from_git(d))
        self.assertIsNone(sl.branch_from_git(None))

    def test_branch_from_git_real_repo(self):
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-b", "my-branch", d],
                           capture_output=True, check=True)
            self.assertEqual(sl.branch_from_git(d), "my-branch")

    def test_resolve_branch_prefers_worktree(self):
        data = {"workspace": {"git_worktree": "wt"}, "cwd": "/tmp"}
        self.assertEqual(sl.resolve_branch(data), "wt")

    FULL = {
        "model": {"display_name": "Opus 4.8"},
        "effort": {"level": "high"},
        "cost": {"total_cost_usd": 0.0123},
        "context_window": {
            "used_percentage": 8,
            "total_input_tokens": 15500,
            "total_output_tokens": 1200,
        },
        "rate_limits": {"five_hour": {"used_percentage": 23.5}},
        "workspace": {"git_worktree": "feature-x"},
        "cwd": "/tmp",
    }

    def test_render_full(self):
        lines = strip(sl.render(self.FULL)).split("\n")
        self.assertEqual(
            lines[0], "feature-x · Opus 4.8 · high · $0.012 · ↑15.5k ↓1.2k")
        self.assertEqual(
            lines[1],
            "ctx ██░░░░░░░░░░░░░░░░░░ 8% · usage(24%)",
        )

    def test_format_reset_days(self):
        now = int(sl.time.time())
        self.assertEqual(sl.format_reset(now + 3 * 86400 + 4 * 3600 + 120), "3d4h")
        self.assertEqual(sl.format_reset(now + 2 * 3600 + 610), "2h10m")

    def test_render_seven_day(self):
        now = int(sl.time.time())
        data = {"rate_limits": {
            "five_hour": {"used_percentage": 23.5},
            "seven_day": {"used_percentage": 41.2,
                          "resets_at": now + 3 * 86400 + 4 * 3600 + 120},
        }}
        self.assertEqual(strip(sl.render(data)),
                         "usage(24%) · week ████░░░░░░ 41% (3d4h left)")

    def test_render_seven_day_only(self):
        data = {"rate_limits": {"seven_day": {"used_percentage": 10}}}
        self.assertEqual(strip(sl.render(data)), "week █░░░░░░░░░ 10%")

    def test_render_omits_missing_effort_and_cost(self):
        data = {"model": {"display_name": "Opus"}, "workspace": {"git_worktree": "b"}}
        self.assertEqual(strip(sl.render(data)), "b · Opus")

    def test_render_no_context_window_drops_second_line(self):
        data = {"model": {"display_name": "Opus"}}
        self.assertEqual(strip(sl.render(data)), "Opus")

    def test_render_null_tokens_shows_dash(self):
        data = {"context_window": {"used_percentage": 8}}
        line2 = strip(sl.render(data))
        self.assertIn("↑— ↓—", line2)

    def test_render_no_rate_limits(self):
        data = {"context_window": {"used_percentage": 8,
                                   "total_input_tokens": 100,
                                   "total_output_tokens": 50}}
        out = strip(sl.render(data))
        self.assertNotIn("usage(", out)
        self.assertNotIn("week", out)

    def test_render_empty_data(self):
        self.assertEqual(sl.render({}), "")

    SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.py")

    def _run(self, stdin_text):
        return subprocess.run(
            [sys.executable, self.SCRIPT],
            input=stdin_text, capture_output=True, text=True,
        )

    def test_main_valid_json(self):
        p = self._run(json.dumps(self.FULL))
        self.assertEqual(p.returncode, 0)
        self.assertIn("Opus 4.8", strip(p.stdout))

    def test_main_garbage_never_crashes(self):
        p = self._run("this is not json")
        self.assertEqual(p.returncode, 0)
        self.assertEqual(p.stderr, "")

    def test_main_empty_input(self):
        p = self._run("")
        self.assertEqual(p.returncode, 0)
        self.assertEqual(p.stderr, "")


if __name__ == "__main__":
    unittest.main()
