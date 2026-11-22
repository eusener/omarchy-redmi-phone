# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Cesur Polat and MiBudsClient contributors
# https://github.com/CesurPolat/MiBudsClient
# Adaptado de MiBudsClient@52eb3f94: controllers/bluetooth/controller.py (connect, on_connect_setup,
# listen/_process_data, request_device_identity, request_battery, EQ/gesture/latency accessors);
# alterações: sessão curta e síncrona para um helper de linha de comando — sem reconexão, sem UI,
# sem ANC, sem polling; um listener em thread que encerra com a sessão; cache de canal RFCOMM.
# Modificado em 2026-11-22 para o plugin eusener.headphones.
"""One short-lived control session with a Xiaomi/Redmi earbud over RFCOMM."""
import socket
import sys
import threading
import time

from .auth_session import AuthPolicy, CommandAuthSession
from .battery_stream import BatteryStreamParser
from .capabilities import resolve_capabilities
from .config_transport import parse_config_records
from .connection import BluetoothConnection
from .eq_transport import EqTransport
from .gesture_transport import GestureTransport
from .gestures import gesture_config
from .latency_transport import LatencyTransport
from .rcsp import RcspStreamParser, build_identity_request, is_supported_target, parse_identity_fields
from .sdp import PlatformBackend, SERVICE_UUIDS

# Legacy setup frame MiBudsClient sends to an unauthenticated 6 Play session.
_LEGACY_6_PLAY_SETUP = bytes.fromhex("fedcba04510003000301ef")


class CachedChannelBackend(PlatformBackend):
    """PlatformBackend that answers the FD2D lookup from a known channel first."""

    def __init__(self, channel=None):
        self.channel = channel

    def resolve_rfcomm_channel(self, address, service_uuid, timeout, cancel):
        if self.channel is not None and service_uuid == SERVICE_UUIDS[0]:
            return self.channel
        return super().resolve_rfcomm_channel(address, service_uuid, timeout, cancel)


class BudsSession:
    def __init__(self, address, device_name, *, channel=None, policy=AuthPolicy.AUTO):
        self.address = address
        self.device_name = device_name
        self.policy = AuthPolicy(policy)
        self.connection = BluetoothConnection(CachedChannelBackend(channel))
        self.gestures = GestureTransport(self.connection)
        self.equalizer = EqTransport(self.gestures)
        self.latency = LatencyTransport(self.gestures)
        self._parser = RcspStreamParser()
        self._battery_parser = BatteryStreamParser()
        self._lock = threading.Condition()
        self._identity_request = None   # (counter, done, identity, error)
        self._battery = None
        self._counter = 0x10
        self._running = False
        self._listener = None
        self.identity = None

    # ---------- lifecycle ----------
    def open(self, timeout=8.0):
        self.connection.connect(self.address, device_name=self.device_name, timeout=timeout,
                                session_policy=self.policy)
        self._running = True
        prefetched = getattr(self.connection, "_prefetched", b"")
        self._listener = threading.Thread(target=self._listen, daemon=True)
        self._listener.start()
        if prefetched:
            self._feed(prefetched)
        if not self.connection.session_authenticated and \
                " ".join(self.device_name.split()).casefold() == "redmi buds 6 play":
            self.connection.send(_LEGACY_6_PLAY_SETUP)
            time.sleep(0.1)
        return self

    def close(self):
        self._running = False
        try:
            self.gestures.reset("session closed")
        except Exception:
            pass
        self.connection.disconnect()
        if self._listener is not None:
            self._listener.join(timeout=1.0)

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()

    @property
    def result(self):
        return self.connection.result

    @property
    def authenticated(self):
        return bool(self.connection.session_authenticated)

    # ---------- listener ----------
    def _listen(self):
        while self._running:
            try:
                data = self.connection.receive()
            except socket.timeout:
                continue
            except OSError:
                break
            if not data:
                break
            self._feed(data)
        with self._lock:
            self._running = False
            self._lock.notify_all()

    def _feed(self, data):
        packets = self._parser.feed(data)
        self.gestures.feed_packets(packets)
        statuses = self._battery_parser.feed_packets(packets)
        with self._lock:
            for packet in packets:
                self._maybe_identity(packet)
            if statuses:
                self._battery = statuses[-1]
            self._lock.notify_all()
        for packet in packets:
            if packet.opcode in (0x50, 0x51):
                auth = self.connection.auth_session
                if isinstance(auth, CommandAuthSession) and auth.authenticated:
                    auth.feed(bytes.fromhex(packet.raw_hex))
                continue
            if not is_supported_target(packet.flags):
                continue
            if packet.opcode == 0xF4:
                offset = 1 if packet.flags & 0x80 else 2
                if len(packet.payload) < offset or (offset == 2 and packet.payload[0]):
                    continue
                try:
                    records = parse_config_records(packet.payload[offset:])
                except ValueError:
                    continue
                generation = self.gestures.generation
                self.gestures.notify(generation, records)
                self.latency.notify(generation, records)
                self.equalizer.notify(generation, records)
            elif packet.opcode != 0x0E:
                continue
            # The earbud asks for an ACK with bit 6 on its own requests.
            if packet.flags & 0x80 and packet.flags & 0x40 and packet.payload:
                try:
                    self.connection.send(bytes.fromhex("fe dc ba 04") +
                                         bytes((packet.opcode, 0, 2, 0, packet.payload[0], 0xEF)))
                except OSError:
                    pass

    def _maybe_identity(self, packet):
        req = self._identity_request
        if req is None or req["done"]:
            return
        if packet.flags & 0x80 or not is_supported_target(packet.flags) or packet.opcode != 0x02 \
                or len(packet.payload) < 2:
            return
        status, counter = packet.payload[:2]
        if counter != req["counter"]:
            return
        if status:
            req["error"] = f"rejected status 0x{status:02X}"
        else:
            req["identity"] = parse_identity_fields(packet.payload[2:])
            if req["identity"] is None:
                req["error"] = "invalid identity"
        req["done"] = True

    def _next_counter(self):
        with self._lock:
            c = self._counter
            self._counter = (c + 1) & 0xFF
            if self._counter in (0x90,):
                self._counter = 0x91
            return c

    # ---------- requests ----------
    def target_info(self, timeout=5.0):
        """GetTargetInfo: returns identity and refreshes the battery reading."""
        counter = self._next_counter()
        with self._lock:
            self._identity_request = {"counter": counter, "done": False, "identity": None, "error": ""}
            self._battery = None
        self.connection.send(build_identity_request(counter))
        deadline = time.monotonic() + timeout
        with self._lock:
            req = self._identity_request
            while not req["done"] and self._running:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("target info timed out")
                self._lock.wait(min(0.2, remaining))
            if not req["done"]:
                raise ConnectionError("connection closed")
            if req["error"]:
                raise ConnectionError(req["error"])
            self.identity = req["identity"]
            # The battery parser sees the same frame; give it a moment if split.
            end = time.monotonic() + 0.5
            while self._battery is None and time.monotonic() < end:
                self._lock.wait(0.05)
            return self.identity, self._battery

    @property
    def capabilities(self):
        return resolve_capabilities(self.device_name, self.identity)

    def read_gestures(self, timeout=5.0):
        caps = self.capabilities.gestures
        configs = tuple(dict.fromkeys(gesture_config(g) for g in caps)) or (2,)
        return self.gestures.read(timeout, None, configs)


def debug(*args):
    print(*args, file=sys.stderr)
