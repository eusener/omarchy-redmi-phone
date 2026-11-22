# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Cesur Polat and MiBudsClient contributors
# https://github.com/CesurPolat/MiBudsClient
# Adaptado de MiBudsClient@52eb3f94: utils/i18n.py (Message, message, error_message),
# utils/error_reports.py (redact) e utils/mibuds_api.py (validate_catalog); alterações:
# só inglês, mensagens embutidas em vez de assets/locales, sem seleção de idioma.
# Modificado em 2026-11-22 para o plugin eusener.headphones.
"""Minimal stand-ins for the MiBudsClient utils the protocol modules import."""
import os
import re
from pathlib import Path

# English strings of the keys used by the vendored modules (assets/locales/en.json).
MESSAGES = {
    "eq.audiophile": "Audiophile",
    "eq.balanced": "Balanced",
    "eq.bass": "Bass",
    "eq.classic": "Classic",
    "eq.classic_legacy": "Classic (legacy)",
    "eq.connect": "Connect the earbuds to adjust EQ.",
    "eq.connection_changed": "Connection changed during EQ request.",
    "eq.current": "Current profile (0x{code})",
    "eq.custom": "Custom EQ",
    "eq.decrease_bass": "Decrease bass",
    "eq.default": "Default",
    "eq.disconnected": "Earbuds are disconnected.",
    "eq.failed": "EQ failed: {details} Close and reopen Equalizer to try again.",
    "eq.harman": "Harman",
    "eq.harman_master": "Harman Master",
    "eq.invalid": "Invalid or incomplete EQ data.",
    "eq.loaded": "EQ loaded.",
    "eq.open": "Open Equalizer to read EQ.",
    "eq.outdoor": "Outdoor",
    "eq.pop": "Pop",
    "eq.presets_only": "Sound profiles loaded. Custom EQ data could not be read.",
    "eq.previewed": "Preview applied. Press Save to store this curve.",
    "eq.profile": "Sound profile",
    "eq.reading": "Reading EQ...",
    "eq.refresh": "Refresh EQ",
    "eq.refresh_first": "Close and reopen Equalizer before making changes.",
    "eq.rejected": "EQ request rejected (status 0x{code}).",
    "eq.reset": "Reset",
    "eq.reset_done": "Custom EQ reset and verified.",
    "eq.rock": "Rock",
    "eq.save": "Save",
    "eq.saved": "EQ saved and verified.",
    "eq.standard": "Standard",
    "eq.timeout": "EQ request timed out.",
    "eq.title": "Equalizer",
    "eq.treble": "Treble",
    "eq.unconfirmed": "The device did not confirm the requested EQ settings.",
    "eq.underwater": "Underwater",
    "eq.unsupported": "EQ operation is not supported for this device.",
    "eq.vocal": "Vocal",
    "eq.volume": "Boost",
    "eq.working": "Applying EQ...",
    "gesture.connect": "Connect your earbuds to manage gestures.",
    "gesture.connection_changed": "Connection changed during gesture request.",
    "gesture.current": "Current: {label}",
    "gesture.disconnected": "Earbuds disconnected. Refresh to read settings again.",
    "gesture.double": "Double tap",
    "gesture.duplicate": "Duplicate gesture assignment",
    "gesture.empty": "The earbuds returned no supported gesture assignments.",
    "gesture.failed": "Gesture request failed: {details}",
    "gesture.incomplete": "Incomplete gesture assignment group",
    "gesture.invalid_length": "Invalid gesture config record length",
    "gesture.loaded": "Gesture settings loaded.",
    "gesture.long": "Long press",
    "gesture.management": "Earbud Management",
    "gesture.no_capabilities": "No confirmed gesture capabilities for this device.",
    "gesture.no_settings": "Device response contains no gesture settings",
    "gesture.open": "Open gestures to read assignments.",
    "gesture.press_double": "Button ×2",
    "gesture.press_single": "Button ×1",
    "gesture.press_triple": "Button ×3",
    "gesture.reading": "Reading gesture settings...",
    "gesture.refresh": "Refresh gestures",
    "gesture.refresh_first": "Refresh gesture settings before changing this assignment.",
    "gesture.rejected": "Gesture request rejected (status 0x{code}).",
    "gesture.saved": "Gesture assignment saved and verified.",
    "gesture.saving": "Saving and verifying assignment...",
    "gesture.single": "Single tap",
    "gesture.squeeze_double": "Squeeze ×2",
    "gesture.squeeze_triple": "Squeeze ×3",
    "gesture.swipe": "Swipe",
    "gesture.timeout": "Gesture request timed out. Refresh to try again.",
    "gesture.title": "Gestures",
    "gesture.triple": "Triple tap",
    "gesture.unconfirmed": "The earbuds did not confirm this assignment. Refresh to read current settings.",
    "gesture.unknown": "Unknown (0x{code})",
    "gesture.unsupported": "This assignment is not supported by this model.",
    "gesture.verification_failed": "Write sent; verification failed: {details}",
    "latency.app_closed": "Tracked app closed. Standard mode restored",
    "latency.auto": "Auto",
    "latency.auto_activated": " activated Game Mode",
    "latency.automatic_set": "Automatic mode set",
    "latency.connection_changed": "Connection changed during Game Mode request.",
    "latency.disconnected": "Earbuds are disconnected.",
    "latency.enabled": "Game Mode enabled",
    "latency.failed": "Game Mode command failed: {details}",
    "latency.fullscreen": "Fullscreen detected. Game Mode enabled",
    "latency.fullscreen_ended": "Fullscreen ended. Standard mode restored",
    "latency.include_left": "Included app left. Standard mode restored",
    "latency.included": "Included app detected. Game Mode enabled",
    "latency.invalid": "Invalid or incomplete Game Mode data.",
    "latency.keeping": "Keeping Game Mode until {app} closes",
    "latency.low_set": "Game Mode set",
    "latency.off": "Off",
    "latency.on": "On",
    "latency.rejected": "Game Mode request rejected (status 0x{code}).",
    "latency.skipped": "Auto game mode skipped for {app}",
    "latency.standard_restored": "Standard mode restored",
    "latency.standard_set": "Standard mode set",
    "latency.timeout": "Game Mode request timed out.",
    "latency.title": "Game Mode",
    "latency.unavailable": "Device controller is unavailable.",
    "latency.unconfirmed": "The device did not confirm the requested Game Mode settings.",
    "latency.unknown": "Game Mode status unknown",
    "latency.wait_disabled": "Wait until app closes disabled",
    "latency.wait_enabled": "Wait until app closes enabled"
}


class Message(str):
    """A str that keeps its key and parameters, like MiBudsClient's Message."""

    def __new__(cls, key, params):
        template = MESSAGES.get(key, key)
        try:
            value = template.format(**params)
        except (KeyError, ValueError, IndexError):
            value = template
        obj = super().__new__(cls, value)
        obj.key, obj.params = key, dict(params)
        return obj


def message(key, **params):
    return Message(key, params)


def error_message(error):
    if error.args and isinstance(error.args[0], Message):
        return error.args[0]
    return str(error) or type(error).__name__


def redact(value):
    text = str(value)
    for root in {str(Path.home()), os.environ.get("HOME", "")}:
        if root:
            text = re.sub(re.escape(root), "[user]", text, flags=re.I)
    text = re.sub(r"(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b", "[address]", text)
    text = re.sub(r"(?i)/home/[^/\s]+", "[user]", text)
    return text


def validate_catalog(catalog):
    """Validate fields consumed by lookup without discarding raw metadata."""
    if not isinstance(catalog, dict) or catalog.get("code") != 0:
        raise ValueError("Invalid catalog response")
    result = catalog.get("result")
    products = result.get("tw_product_list") if isinstance(result, dict) else None
    if not isinstance(products, list) or not products:
        raise ValueError("Catalog has no models")
    for product in products:
        if not isinstance(product, dict):
            raise ValueError("Invalid model")
        for key in ("vid", "pid"):
            if not isinstance(product.get(key), str) or not re.fullmatch(r"[0-9a-fA-F]{1,4}", product[key]):
                raise ValueError("Invalid model identity")
        for key in ("name", "model"):
            if not isinstance(product.get(key), str) or not product[key].strip():
                raise ValueError("Invalid model name")
        if not isinstance(product.get("extra_info", {}), dict):
            raise ValueError("Invalid model metadata")
        if not isinstance(product.get("func_list", []), list):
            raise ValueError("Invalid function list")
    return catalog
