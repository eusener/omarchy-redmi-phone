# SPDX-License-Identifier: GPL-3.0-only
# Run: python3 -I tests/test_buds_vendor.py
import errno
import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("buds_vendor", str(ROOT / "bin" / "buds-vendor"))
spec = importlib.util.spec_from_loader("buds_vendor", loader)
bv = importlib.util.module_from_spec(spec)
loader.exec_module(bv)

from mibuds.auth_session import AuthError  # noqa: E402  (path set up by buds-vendor)
from mibuds.capabilities import resolve_capabilities  # noqa: E402

MAC = "AA:BB:CC:DD:EE:FF"
CAPS = resolve_capabilities("Redmi Buds 6 Play")


class FakeSession:
    """Records every call that would reach the earbuds."""

    def __init__(self):
        self.sent = []
        self.closed = False
        self.device_name = "Redmi Buds 6 Play"
        self.identity = None
        self.authenticated = False
        self.result = SimpleNamespace(channel=6)
        self._battery = SimpleNamespace(left=0x80 | 40, right=58, case=255)
        self.equalizer = SimpleNamespace(
            read=lambda *a, **k: SimpleNamespace(success=True, state=SimpleNamespace(profile=0), message=""),
            apply=self._apply)
        self.gestures = SimpleNamespace(write=self._gesture_write)
        self.latency = SimpleNamespace(read=lambda *a: False, write=self._latency_write)

    def _apply(self, op, profile=None, timeout=5):
        self.sent.append(("eq", profile))
        return SimpleNamespace(success=True, state=SimpleNamespace(profile=profile), message="")

    def _gesture_write(self, g, side, action, timeout):
        self.sent.append(("gesture", g, side, action))
        return SimpleNamespace(success=True, assignments={g: (action, action)}, message="")

    def _latency_write(self, want, timeout):
        self.sent.append(("latency", want))
        return want

    def read_gestures(self, timeout):
        return SimpleNamespace(success=True, assignments={2: (3, 3)}, message="")

    @property
    def capabilities(self):
        return CAPS

    def close(self):
        self.closed = True


def run_main(argv, session=None, connected=True, open_error=None):
    out = io.StringIO()
    with mock.patch.object(bv, "device_info", return_value=("Redmi Buds 6 Play", connected, set())), \
         mock.patch.object(bv, "open_session", side_effect=open_error or (lambda m, n: session)), \
         redirect_stdout(out):
        status = bv.main(argv)
    return status, json.loads(out.getvalue())


class ValidationTests(unittest.TestCase):
    def test_invalid_mac_refused_before_any_connection(self):
        with mock.patch.object(bv, "open_session") as opener:
            status, out = run_main(["battery", "AA:BB:CC:DD:EE:FF; rm -rf ~"])
            opener.assert_not_called()
        self.assertEqual(out, {"ok": False, "error": "invalid_mac"})
        self.assertNotEqual(status, 0)

    def test_usage_errors(self):
        for argv in ([], ["nope", MAC], ["probe"], ["eq", "get", MAC, "extra"], ["latency", "set", MAC, "maybe"],
                     ["gestures", "set", MAC, "2", "middle", "3"], ["eq", "set", MAC, "-1"]):
            status, out = run_main(argv)
            self.assertFalse(out["ok"], argv)
            self.assertIn(out["error"], ("usage", "invalid_value", "invalid_mac"), argv)

    def test_eq_profile_outside_catalog_is_never_sent(self):
        session = FakeSession()
        status, out = run_main(["eq", "set", MAC, "10"], session)  # 10 = custom, excluded
        self.assertEqual(out["error"], "invalid_value")
        self.assertEqual(session.sent, [])
        self.assertTrue(session.closed)

    def test_gesture_action_outside_catalog_is_never_sent(self):
        session = FakeSession()
        status, out = run_main(["gestures", "set", MAC, "3", "left", "4"], session)  # long press allows 0/9/8
        self.assertEqual(out["error"], "invalid_value")
        self.assertEqual(session.sent, [])

    def test_valid_writes_reach_the_session(self):
        session = FakeSession()
        status, out = run_main(["eq", "set", MAC, "5"], session)
        self.assertTrue(out["ok"])
        self.assertEqual(session.sent, [("eq", 5)])
        session = FakeSession()
        status, out = run_main(["gestures", "set", MAC, "2", "right", "2"], session)
        self.assertTrue(out["ok"], out)
        self.assertEqual(session.sent, [("gesture", 2, "right", 2)])

    def test_not_connected_does_not_open_rfcomm(self):
        with mock.patch.object(bv, "open_session") as opener:
            status, out = run_main(["probe", MAC], connected=False)
            opener.assert_not_called()
        self.assertEqual(out["error"], "not_connected")


class ResultTests(unittest.TestCase):
    def test_battery_cells(self):
        status, out = run_main(["battery", MAC], FakeSession())
        self.assertEqual(out["battery"], {"left": {"percent": 40, "charging": True},
                                          "right": {"percent": 58, "charging": False}, "case": None})

    def test_error_codes(self):
        cases = [
            (ConnectionRefusedError(errno.ECONNREFUSED, "refused"), "refused"),
            (OSError(errno.EBUSY, "busy"), "refused"),
            (AuthError("bad answer"), "auth_failed"),
            (TimeoutError("slow"), "timeout"),
            (ValueError("bad frame"), "protocol"),
        ]
        for exc, code in cases:
            status, out = run_main(["battery", MAC], open_error=exc)
            self.assertEqual(out, {"ok": False, "error": code}, exc)
            self.assertNotEqual(status, 0)

    def test_timeout_mid_command_still_closes_the_session(self):
        session = FakeSession()
        session.latency = SimpleNamespace(read=mock.Mock(side_effect=TimeoutError("deadline")))
        status, out = run_main(["latency", "get", MAC], session)
        self.assertEqual(out["error"], "timeout")
        self.assertTrue(session.closed)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.tmp.name})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def test_discovery_writes_cache_and_bad_cache_is_rediscovered_once(self):
        good = FakeSession()
        calls = []

        def fake_open(mac, name, channel, policy):
            calls.append(channel)
            if channel == 3:
                raise ConnectionError("No usable RFCOMM service for selected device")
            return good

        with mock.patch.object(bv, "try_open", side_effect=fake_open):
            bv.open_session(MAC, "Redmi Buds 6 Play")
            self.assertEqual(bv.cache_entry(MAC), (6, "direct"))
            self.assertEqual(calls, [None])
            calls.clear()
            bv.open_session(MAC, "Redmi Buds 6 Play")
            self.assertEqual(calls, [6], "uses the cache")
            calls.clear()
            bv.store_cache(MAC, 3, "direct")
            bv.open_session(MAC, "Redmi Buds 6 Play")
            self.assertEqual(calls, [3, None], "bad cache dropped, rediscovered once")
            self.assertEqual(bv.cache_entry(MAC), (6, "direct"))

    def test_corrupt_cache_is_ignored(self):
        path = bv.cache_path()
        path.parent.mkdir(parents=True)
        path.write_text('{"%s": {"channel": 99, "policy": "x"}}' % MAC)
        self.assertIsNone(bv.cache_entry(MAC))
        path.write_text("not json")
        self.assertIsNone(bv.cache_entry(MAC))


if __name__ == "__main__":
    unittest.main()
