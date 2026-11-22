# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Cesur Polat and MiBudsClient contributors
# https://github.com/CesurPolat/MiBudsClient
# Adaptado de MiBudsClient@52eb3f94: controllers/bluetooth/sdp.py; alterações: consulta SDP do Windows (PowerShell/Winsock) removida; só Linux.
# Modificado em 2026-11-22 para o plugin eusener.headphones.
"""Bounded SDP lookup through Windows Winsock or Linux BlueZ (no BT packages).

The PowerShell child isolates blocking native SDP calls so cancellation kills
and reaps the actual query, including WSALookupServiceBegin. Works when frozen.
"""
import base64
import re
import socket
import subprocess
import sys
import time
from uuid import UUID
import xml.etree.ElementTree as ET


class ConnectionCancelled(OSError):
    pass


SERVICE_UUIDS = (
    "0000fd2d-0000-1000-8000-00805f9b34fb",
    "00001101-0000-1000-8000-008584d01810",
    "00001101-0000-1000-8000-00805f9b34fb",
)

class PlatformBackend:
    @property
    def resolution_source(self):
        return "linux_sdp"

    def resolve_rfcomm_channel(self, address, service_uuid, timeout, cancel):
        if sys.platform != "win32" and not sys.platform.startswith("linux"):
            return None
        if not re.fullmatch(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}", address):
            raise ValueError("Invalid Bluetooth address")
        service_uuid = str(UUID(service_uuid))
        if sys.platform.startswith("linux"):
            return self._resolve_linux_channel(address, service_uuid, timeout, cancel)
        raise OSError("Only Linux SDP is supported")

    def _resolve_linux_channel(self, address, service_uuid, timeout, cancel):
        deadline = time.monotonic() + timeout
        if cancel.is_set():
            raise ConnectionCancelled("SDP lookup cancelled")
        if timeout <= 0:
            raise TimeoutError("SDP lookup timed out")
        # Search Bluetooth-base UUIDs directly, including services that are not
        # in the public browse group. sdptool search cannot accept an arbitrary
        # vendor 128-bit UUID, so browse this peer for those and match locally.
        # No RFCOMM channels are probed and no other Bluetooth peers are scanned.
        if service_uuid[8:] == "-0000-1000-8000-00805f9b34fb":
            command = ["sdptool", "search", "--bdaddr", address, "--xml",
                       f"0x{int(service_uuid[:8], 16):x}"]
        else:
            command = ["sdptool", "browse", "--xml", address]
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
        except FileNotFoundError as error:
            raise OSError("Linux SDP discovery requires BlueZ's sdptool") from error
        with process:
            try:
                while True:
                    if cancel.is_set():
                        raise ConnectionCancelled("SDP lookup cancelled")
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError("Linux SDP lookup timed out")
                    try:
                        output, error = process.communicate(timeout=min(0.05, remaining))
                        break
                    except subprocess.TimeoutExpired:
                        continue
                if cancel.is_set():
                    raise ConnectionCancelled("SDP lookup cancelled")
                if time.monotonic() >= deadline:
                    raise TimeoutError("Linux SDP lookup timed out")
                if process.returncode:
                    raise OSError("Linux SDP query failed: " + error.decode(errors="replace").strip())
                # Some sdptool versions report failed browse requests on stderr
                # while returning zero. Do not present those as empty catalogs.
                if error.strip():
                    raise OSError("Linux SDP query reported: " + error.decode(errors="replace").strip())
                return _linux_record_channel(output, service_uuid)
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()

    def create_rfcomm_socket(self):
        return socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)


def _sdp_uuid(value):
    """Expand only standard short UUIDs; preserve vendor-specific 128-bit IDs."""
    if re.fullmatch(r"(?:0x)?[0-9a-fA-F]{1,8}", value):
        short = int(value, 16)
        return str(UUID(f"{short:08x}-0000-1000-8000-00805f9b34fb"))
    return str(UUID(value))


def _linux_record_channel(output, service_uuid):
    """Read RFCOMM only from the exact service's own ProtocolDescriptorList."""
    # BlueZ emits separate XML documents, with optional human-readable headers.
    # Parse each record independently, so channels cannot cross record bounds.
    records = re.findall(rb"<record\b[^>]*>.*?</record\s*>", output, re.DOTALL)
    if output.count(b"<record") != len(records):
        raise OSError("Incomplete Linux SDP XML records")
    channels = set()
    for raw in records:
        try:
            record = ET.fromstring(raw)
            attributes = {int(attr.attrib["id"], 0): attr for attr in record.findall("attribute")}
            services = []
            for attribute_id in (0x0001, 0x0003):  # ServiceClassIDList, ServiceID
                attr = attributes.get(attribute_id)
                if attr is not None:
                    services.extend(_sdp_uuid(node.attrib["value"]) for node in attr.iter("uuid"))
            if service_uuid not in services:
                continue
            protocols = attributes.get(0x0004)
            if protocols is None:
                continue
            for descriptor in protocols.findall("./sequence/sequence"):
                fields = list(descriptor)
                if not fields or fields[0].tag != "uuid":
                    continue
                if _sdp_uuid(fields[0].attrib["value"]) != "00000003-0000-1000-8000-00805f9b34fb":
                    continue
                if len(fields) != 2 or fields[1].tag != "uint8":
                    raise ValueError("Invalid RFCOMM descriptor")
                channel = int(fields[1].attrib["value"], 0)
                if not 1 <= channel <= 30:
                    raise ValueError("Invalid RFCOMM channel")
                channels.add(channel)
        except (ET.ParseError, KeyError, ValueError) as error:
            raise OSError("Invalid Linux SDP service record") from error
    if len(channels) > 1:
        raise OSError("Ambiguous RFCOMM channels for the requested service UUID")
    return next(iter(channels), None)
