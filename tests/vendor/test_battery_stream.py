# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Cesur Polat and MiBudsClient contributors
# Adaptado de MiBudsClient@52eb3f94: tests/test_battery_stream.py; alterações: imports apontam para vendor/mibuds,
# testes que dependem da UI Flet, do BTController ou do LatencyController foram removidos.
import sys, pathlib

def set_language(*args, **kwargs):
    pass  # the vendored code is English-only
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'vendor'))
"""Preserve battery records across fragmented and coalesced RFCOMM reads."""
import unittest
from unittest.mock import Mock
from mibuds.battery_stream import BatteryStreamParser

def battery_frame(values):
    payload = bytes.fromhex('00 0b 02 06 02') + bytes((len(values) + 1, 7)) + bytes(values)
    return bytes.fromhex('fe dc ba 04 02') + len(payload).to_bytes(2, 'big') + payload + bytes.fromhex('ef')

class BatteryStreamTests(unittest.TestCase):

    def test_every_split_position_and_bytewise_delivery(self):
        record = battery_frame([188, 70, 255])
        for split in range(len(record) + 1):
            parser = BatteryStreamParser()
            records = parser.feed(record[:split]) + parser.feed(record[split:])
            self.assertEqual(len(records), 1)
            self.assertEqual((records[0].left, records[0].right, records[0].case), (188, 70, 255))
        parser = BatteryStreamParser()
        records = [item for byte in record for item in parser.feed(bytes([byte]))]
        self.assertEqual(len(records), 1)

    def test_multiple_records_and_noise_are_consumed_exactly_once(self):
        parser = BatteryStreamParser()
        records = parser.feed(b'noise' + battery_frame([60, 70, 80]) + b'noise' + battery_frame([61, 71, 81]))
        self.assertEqual([item.left for item in records], [60, 61])
        self.assertEqual(parser.feed(b''), [])
        parser.feed(b'x' * 100000)
        self.assertLessEqual(parser._parser.buffered_bytes, 2)

    def test_disconnect_reset_prevents_cross_connection_records(self):
        parser = BatteryStreamParser()
        record = battery_frame([60, 70, 80])
        parser.feed(record[:5])
        parser.reset()
        self.assertEqual(parser.feed(record[5:]), [])
        self.assertEqual(len(parser.feed(record)), 1)
