// SPDX-License-Identifier: GPL-3.0-only
// Pure logic for the headphones plugin. No QML types in here: the shell imports
// it with `import "Model.js" as Model`, and the tests load it with node.
//
// Device inputs are primitive rows (address, name, icon, connected, battery…),
// never live Quickshell.Bluetooth objects — BlueZ can destroy those while a
// binding still holds them (see omarchy.bluetooth's Model.deviceRow).

var MAC_RE = /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/
var XIAOMI_CONTROL_UUID = "0000fd2d-0000-1000-8000-00805f9b34fb"
var AUDIO_UUID_PREFIXES = ["0000110b-", "0000111e-", "00001108-"] // A2DP sink, Handsfree, Headset
var AUDIO_ICONS = ["audio-headset", "audio-headphones"]
var MAX_STATUS_BYTES = 65536

function isMac(value) {
  return typeof value === "string" && MAC_RE.test(value)
}

function underscored(mac) {
  return isMac(mac) ? mac.replace(/:/g, "_") : ""
}

function cardNameFor(mac) {
  var u = underscored(mac)
  return u ? "bluez_card." + u : ""
}

function sinkPrefixFor(mac) {
  var u = underscored(mac)
  return u ? "bluez_output." + u : ""
}

function deviceRow(d) {
  if (!d) return null
  return {
    address: String(d.address || ""),
    name: String(d.name || d.deviceName || ""),
    icon: String(d.icon || ""),
    connected: !!d.connected,
    paired: !!d.paired,
    batteryAvailable: !!d.batteryAvailable,
    battery: typeof d.battery === "number" ? d.battery : 0
  }
}

function hasAudioUuid(uuids) {
  if (!Array.isArray(uuids)) return false
  for (var i = 0; i < uuids.length; i++) {
    var u = String(uuids[i]).toLowerCase()
    for (var j = 0; j < AUDIO_UUID_PREFIXES.length; j++)
      if (u.indexOf(AUDIO_UUID_PREFIXES[j]) === 0) return true
  }
  return false
}

// A headphone is a device whose BlueZ icon says headset/headphones, or whose
// UUID list (when known, from the helper) includes an audio profile.
function isHeadphone(row) {
  if (!row || !isMac(row.address)) return false
  if (AUDIO_ICONS.indexOf(row.icon) >= 0) return true
  return hasAudioUuid(row.uuids)
}

// rows: deviceRow()s. defaultSinkName: Pipewire default sink node name.
// connectOrder: {address: sequence} — higher means connected more recently.
function pickActiveHeadphone(rows, defaultSinkName, connectOrder) {
  var list = Array.isArray(rows) ? rows : []
  var order = connectOrder || {}
  var sink = String(defaultSinkName || "")
  var candidates = []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].connected && isHeadphone(list[i])) candidates.push(list[i])
  if (candidates.length === 0) return null
  for (var k = 0; k < candidates.length; k++) {
    var prefix = sinkPrefixFor(candidates[k].address)
    if (prefix && sink.indexOf(prefix) === 0) return candidates[k]
  }
  var best = candidates[0]
  for (var m = 1; m < candidates.length; m++) {
    var a = order[candidates[m].address] || 0
    var b = order[best.address] || 0
    if (a > b) best = candidates[m]
  }
  return best
}

// Last paired headphone to offer "Connect" when none is connected.
function pickReconnectCandidate(rows, connectOrder) {
  var list = Array.isArray(rows) ? rows : []
  var order = connectOrder || {}
  var best = null
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (!r || r.connected || !r.paired || !isHeadphone(r)) continue
    if (!best || (order[r.address] || 0) > (order[best.address] || 0)) best = r
  }
  return best
}

function batteryPercent(fraction, available) {
  if (!available || typeof fraction !== "number" || isNaN(fraction)) return -1
  var pct = fraction <= 1 ? Math.round(fraction * 100) : Math.round(fraction)
  return Math.max(0, Math.min(100, pct))
}

function modeOfProfile(name) {
  var n = String(name || "")
  if (n.indexOf("a2dp-sink") === 0) return "music"
  if (n.indexOf("headset-head-unit") === 0) return "call"
  return ""
}

var SUFFIX_CODECS = { sbc: "SBC", sbc_xq: "SBC-XQ", aac: "AAC", aptx: "aptX", aptx_hd: "aptX HD",
                      aptx_ll: "aptX LL", ldac: "LDAC", lc3: "LC3", opus_05: "Opus", cvsd: "CVSD", msbc: "mSBC" }

function codecOfProfile(name, description) {
  var m = /codec ([A-Za-z0-9_\- ]+)\)/.exec(String(description || ""))
  if (m) {
    var c = m[1].trim()
    return c.toUpperCase() === "MSBC" ? "mSBC" : c
  }
  var n = String(name || "")
  var dash = n.lastIndexOf("-")
  var suffix = dash >= 0 ? n.slice(dash + 1) : ""
  if (SUFFIX_CODECS[suffix]) return SUFFIX_CODECS[suffix]
  return ""
}

// card: one entry of `pactl --format=json list cards`.
// Returns { activeProfile, activeMode, activeCodec, music: {codecs}, call: {codecs} }
// where each codec is { profile, codec, priority } sorted by priority desc.
function groupProfiles(card) {
  var out = { activeProfile: "", activeMode: "", activeCodec: "",
              music: { codecs: [] }, call: { codecs: [] } }
  if (!card || typeof card !== "object" || !card.profiles || typeof card.profiles !== "object") return out
  var active = String(card.active_profile || "")
  for (var name in card.profiles) {
    if (!Object.prototype.hasOwnProperty.call(card.profiles, name)) continue
    var p = card.profiles[name] || {}
    var mode = modeOfProfile(name)
    if (!mode || p.available === false) continue
    var entry = { profile: name, codec: codecOfProfile(name, p.description) || name,
                  priority: typeof p.priority === "number" ? p.priority : 0 }
    out[mode].codecs.push(entry)
    if (name === active) { out.activeMode = mode; out.activeCodec = entry.codec }
  }
  out.music.codecs.sort(byPriority)
  out.call.codecs.sort(byPriority)
  out.activeProfile = active
  return out
}

function byPriority(a, b) { return b.priority - a.priority || (a.profile < b.profile ? -1 : 1) }

function bestProfileFor(groups, mode) {
  if (!groups || !groups[mode] || groups[mode].codecs.length === 0) return ""
  return groups[mode].codecs[0].profile
}

function hasXiaomiControl(uuids) {
  if (!Array.isArray(uuids)) return false
  for (var i = 0; i < uuids.length; i++)
    if (String(uuids[i]).toLowerCase() === XIAOMI_CONTROL_UUID) return true
  return false
}

// Parse one JSON object printed by a helper. Bounded, never throws.
function parseHelperJson(text) {
  var s = String(text || "")
  if (s.length === 0 || s.length > MAX_STATUS_BYTES) return null
  try {
    var v = JSON.parse(s)
    return v && typeof v === "object" && !Array.isArray(v) ? v : null
  } catch (e) {
    return null
  }
}

// Vendor battery byte: bit 7 = charging, low 7 bits = percent, 0xFF = absent.
function vendorBatteryCell(value) {
  if (typeof value !== "number" || value < 0 || value > 255 || value === 255) return null
  var pct = value & 0x7f
  if (pct > 100) return null
  return { percent: pct, charging: (value & 0x80) !== 0 }
}

// Physical order for the panel: single, double, triple, long, swipe, then the
// squeeze/press variants; unknown IDs keep their relative order at the end.
var GESTURE_ORDER = ["4", "1", "2", "3", "5", "4018", "4004", "4012", "4005", "4013", "4014"]
function orderGestures(ids) {
  var list = Array.isArray(ids) ? ids.map(String) : []
  return list.slice().sort(function(a, b) {
    var ia = GESTURE_ORDER.indexOf(a), ib = GESTURE_ORDER.indexOf(b)
    if (ia < 0) ia = 1000 + list.indexOf(a)
    if (ib < 0) ib = 1000 + list.indexOf(b)
    return ia - ib
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    isMac: isMac,
    cardNameFor: cardNameFor,
    sinkPrefixFor: sinkPrefixFor,
    deviceRow: deviceRow,
    isHeadphone: isHeadphone,
    pickActiveHeadphone: pickActiveHeadphone,
    pickReconnectCandidate: pickReconnectCandidate,
    batteryPercent: batteryPercent,
    modeOfProfile: modeOfProfile,
    codecOfProfile: codecOfProfile,
    groupProfiles: groupProfiles,
    bestProfileFor: bestProfileFor,
    hasXiaomiControl: hasXiaomiControl,
    parseHelperJson: parseHelperJson,
    vendorBatteryCell: vendorBatteryCell,
    orderGestures: orderGestures
  }
}
