# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Cesur Polat and MiBudsClient contributors
# https://github.com/CesurPolat/MiBudsClient
# Adaptado de MiBudsClient@52eb3f94: controllers/bluetooth/constants.py; alterações: nenhuma.
# Modificado em 2026-11-22 para o plugin eusener.headphones.
"""Bluetooth Controller Constants."""

# ─────────────────────────────────────────────────────────────────────────────
# Connection Settings
# ─────────────────────────────────────────────────────────────────────────────
RFCOMM_PORT = 6
SOCKET_TIMEOUT = 2
RECONNECT_DELAY = 5
RECV_BUFFER_SIZE = 1024

# ─────────────────────────────────────────────────────────────────────────────
# Data Packet Sizes
# ─────────────────────────────────────────────────────────────────────────────
PACKET_SIZE_MODE_ACK = 14

# ─────────────────────────────────────────────────────────────────────────────
# Protocol Patterns
# ─────────────────────────────────────────────────────────────────────────────
BATTERY_PATTERN = bytes.fromhex("02020407")
# Live queries allocate a sequence through the target-info frame builder.
BATTERY_REQUEST_PAYLOAD = "fedcbac40200050bffffffffef"
MODE_COMMAND_TEMPLATE = "fedcbac4f20005{counter}03002f{param}ef"
COUNTER_VALUE = 0x90
