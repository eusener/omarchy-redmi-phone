# SPDX-License-Identifier: GPL-3.0-only
# Untrusted earbud input: malformed and oversized RCSP frames never surface.
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "vendor"))

from mibuds.rcsp import MAX_FRAME_BYTES, RcspStreamParser  # noqa: E402
from mibuds.battery_stream import BatteryStreamParser  # noqa: E402

VALID = bytes.fromhex("fedcba0402000300011def")


class FrameLimitTests(unittest.TestCase):
    def test_length_beyond_received_bytes_is_held_not_emitted(self):
        parser = RcspStreamParser()
        truncated = bytes.fromhex("fedcba04020010") + b"\x00\x01"  # claims 16 payload bytes, sends 2
        self.assertEqual(parser.feed(truncated), [])
        self.assertLessEqual(parser.buffered_bytes, MAX_FRAME_BYTES)

    def test_oversized_frame_is_dropped_and_parser_resyncs(self):
        parser = RcspStreamParser()
        oversized = bytes.fromhex("fedcbac402") + (MAX_FRAME_BYTES).to_bytes(2, "big") + b"\x00" * 64
        packets = parser.feed(oversized + VALID)
        self.assertEqual(len(packets), 1)
        self.assertEqual(packets[0].opcode, 0x02)

    def test_bad_trailer_is_not_a_packet(self):
        parser = RcspStreamParser()
        bad = bytearray(VALID)
        bad[-1] = 0x00
        self.assertEqual(parser.feed(bytes(bad)), [])

    def test_garbage_never_raises(self):
        parser = RcspStreamParser()
        battery = BatteryStreamParser()
        for chunk in (b"\xff" * 2000, b"\xfe\xdc\xba" * 50, bytes(range(256)) * 4):
            parser.feed(chunk)
            battery.feed(chunk)


if __name__ == "__main__":
    unittest.main()
