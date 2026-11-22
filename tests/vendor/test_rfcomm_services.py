# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Cesur Polat and MiBudsClient contributors
# Adaptado de MiBudsClient@52eb3f94: tests/test_rfcomm_services.py; alterações: imports apontam para vendor/mibuds,
# testes que dependem da UI Flet, do BTController ou do LatencyController foram removidos.
import sys, pathlib

def set_language(*args, **kwargs):
    pass
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'vendor'))
'Transport tests with fake backends: these do not validate earbuds hardware.'
import threading
import unittest
from unittest.mock import Mock, patch
from mibuds.connection import BluetoothConnection
from mibuds.sdp import ConnectionCancelled, PlatformBackend, SERVICE_UUIDS

class ServiceConnectionTests(unittest.TestCase):

    def backend(self, channels):
        backend = Mock()
        backend.resolve_rfcomm_channel.side_effect = channels
        backend.create_rfcomm_socket.side_effect = lambda: Mock()
        return backend

    def test_same_service_different_peer_channels(self):
        for address, channel in (('AA:BB:CC:DD:EE:01', 6), ('AA:BB:CC:DD:EE:02', 24)):
            backend = self.backend([channel])
            connection = BluetoothConnection(backend)
            result = connection.connect(address)
            result.socket.connect.assert_called_once_with((address, channel))
            self.assertEqual(result.service_uuid, SERVICE_UUIDS[0])
            self.assertEqual(result.resolution_source, 'windows_sdp')
            self.assertEqual(backend.resolve_rfcomm_channel.call_args.args[:2], (address, SERVICE_UUIDS[0]))
            connection.disconnect()
            result.socket.close.assert_called_once()
            self.assertIsNone(connection.result)

    def test_service_order_and_failed_socket_cleanup(self):
        backend = self.backend([24, None, 7])
        failed, good = (Mock(), Mock())
        failed.connect.side_effect = OSError('refused')
        backend.create_rfcomm_socket.side_effect = [failed, good]
        result = BluetoothConnection(backend).connect('AA:BB:CC:DD:EE:FF')
        self.assertEqual([c.args[1] for c in backend.resolve_rfcomm_channel.call_args_list], list(SERVICE_UUIDS))
        failed.close.assert_called_once()
        self.assertEqual(result.service_uuid, SERVICE_UUIDS[2])
        self.assertEqual(result.channel, 7)

    def test_eof_preserves_metadata_until_controller_disconnect(self):
        connection = BluetoothConnection(self.backend([24]))
        result = connection.connect('AA:BB:CC:DD:EE:FF')
        result.socket.recv.return_value = b''
        self.assertEqual(connection.receive(), b'')
        result.socket.close.assert_not_called()
        self.assertTrue(connection.connected)
        self.assertIs(connection.result, result)
        connection.disconnect()
        result.socket.close.assert_called_once()
        self.assertFalse(connection.connected)
        self.assertIsNone(connection.result)

    def test_profile_fallback_is_explicit_and_only_for_6_play(self):
        backend = self.backend([None] * 3)
        result = BluetoothConnection(backend).connect('AA:BB:CC:DD:EE:FF', 'Redmi Buds 6 Play')
        self.assertEqual((result.service_uuid, result.channel, result.resolution_source), (None, 6, 'profile_fallback'))
        for name in ('', 'Redmi Buds 6', 'Redmi Buds 6 Pro'):
            backend = self.backend([None] * 3)
            with self.assertRaises(ConnectionError):
                BluetoothConnection(backend).connect('AA:BB:CC:DD:EE:FF', name)
            backend.create_rfcomm_socket.assert_not_called()

    def test_failed_resolved_service_does_not_trigger_profile_fallback(self):
        backend = self.backend([24, None, None])
        sock = Mock()
        sock.connect.side_effect = OSError('refused')
        backend.create_rfcomm_socket.side_effect = [sock]
        connection = BluetoothConnection(backend)
        with self.assertRaises(ConnectionError):
            connection.connect('AA:BB:CC:DD:EE:FF', 'Redmi Buds 6 Play')
        sock.close.assert_called_once()
        self.assertFalse(connection.connected)

    def test_resolution_errors_allow_profile_fallback_but_bugs_propagate(self):
        backend = self.backend([TimeoutError('SDP timeout'), OSError('SDP failed'), None])
        self.assertIsNone(BluetoothConnection(backend).connect('AA:BB:CC:DD:EE:FF', 'Redmi Buds 6 Play').service_uuid)
        backend = self.backend([RuntimeError('bug')])
        with self.assertRaisesRegex(RuntimeError, 'bug'):
            BluetoothConnection(backend).connect('AA:BB:CC:DD:EE:FF', 'Redmi Buds 6 Play')
        backend.create_rfcomm_socket.assert_not_called()

    def test_disconnect_cancels_pending_socket_without_publishing_success(self):
        backend = self.backend([24])
        sock = Mock()
        backend.create_rfcomm_socket.side_effect = [sock]
        connection = BluetoothConnection(backend)
        sock.connect.side_effect = lambda _: connection.disconnect()
        with self.assertRaises(ConnectionCancelled):
            connection.connect('AA:BB:CC:DD:EE:FF')
        self.assertFalse(connection.connected)
        self.assertIsNone(connection.result)
        self.assertTrue(sock.close.called)
        self.assertEqual(backend.resolve_rfcomm_channel.call_count, 1)

    def test_disconnect_cancels_pending_resolution(self):
        backend = self.backend([])
        connection = BluetoothConnection(backend)

        def resolve(address, uuid, timeout, cancel):
            connection.disconnect()
            raise ConnectionCancelled('cancelled')
        backend.resolve_rfcomm_channel.side_effect = resolve
        with self.assertRaises(ConnectionCancelled):
            connection.connect('AA:BB:CC:DD:EE:FF', 'Redmi Buds 6 Play')
        backend.create_rfcomm_socket.assert_not_called()

    def test_total_budget_prevents_opening_socket(self):
        backend = self.backend([24])
        with patch('mibuds.connection.time.monotonic', side_effect=[0, 0, 20, 20]):
            with self.assertRaises(TimeoutError):
                BluetoothConnection(backend).connect('AA:BB:CC:DD:EE:FF', timeout=1)
        backend.create_rfcomm_socket.assert_not_called()
if __name__ == '__main__':
    unittest.main()
