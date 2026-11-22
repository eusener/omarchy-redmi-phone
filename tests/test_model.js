// SPDX-License-Identifier: GPL-3.0-only
// Run: node tests/test_model.js
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const model = require('../Model.js')

const BUDS = 'AA:BB:CC:DD:EE:FF'
const OTHER = 'AA:BB:CC:DD:EE:01'
const row = (o) => Object.assign({ address: BUDS, name: 'Redmi Buds 6 Play', icon: 'audio-headset',
  connected: true, paired: true, batteryAvailable: true, battery: 0.6 }, o)

// ---- MAC / names ----
assert.equal(model.isMac(BUDS), true)
assert.equal(model.isMac('aa:bb:cc:dd:ee:ff'), false, 'lowercase is not what BlueZ reports')
assert.equal(model.isMac('AA:BB:CC:DD:EE'), false)
assert.equal(model.isMac('AA:BB:CC:DD:EE:FF; rm -rf ~'), false)
assert.equal(model.isMac('<img src="https://example.invalid/x">'), false)
assert.equal(model.isMac(null), false)
assert.equal(model.cardNameFor(BUDS), 'bluez_card.AA_BB_CC_DD_EE_FF')
assert.equal(model.cardNameFor('bogus'), '')
assert.equal(model.sinkPrefixFor(BUDS), 'bluez_output.AA_BB_CC_DD_EE_FF')
console.log('MAC helpers: OK')

// ---- deviceRow keeps markup as data ----
const evil = model.deviceRow({ address: BUDS, name: '<img src="https://example.invalid/x">', icon: 'audio-headset', connected: true })
assert.equal(evil.name, '<img src="https://example.invalid/x">')
assert.equal(model.deviceRow(null), null)
console.log('deviceRow: OK')

// ---- active headphone ----
assert.equal(model.pickActiveHeadphone([row()], '', {}).address, BUDS, 'one headphone')
const keyboard = row({ address: '11:22:33:44:55:66', name: 'Keyboard', icon: 'input-keyboard' })
assert.equal(model.pickActiveHeadphone([keyboard], '', {}), null, 'keyboard only')
assert.equal(model.pickActiveHeadphone([row({ connected: false })], '', {}), null, 'disconnected')
const other = row({ address: OTHER, name: 'Other' })
assert.equal(model.pickActiveHeadphone([row(), other], 'bluez_output.AA_BB_CC_DD_EE_01.1', {}).address, OTHER, 'default sink wins')
assert.equal(model.pickActiveHeadphone([row(), other], 'alsa_output.x', { [BUDS]: 2, [OTHER]: 1 }).address, BUDS, 'most recent wins')
assert.equal(model.pickActiveHeadphone([row(), other], 'alsa_output.x', { [BUDS]: 1, [OTHER]: 5 }).address, OTHER)
const byUuid = row({ icon: '', uuids: ['0000110b-0000-1000-8000-00805f9b34fb'] })
assert.equal(model.pickActiveHeadphone([byUuid], '', {}).address, BUDS, 'audio uuid without icon')
assert.equal(model.pickActiveHeadphone(null, null, null), null)
console.log('pickActiveHeadphone: OK')

assert.equal(model.pickReconnectCandidate([row({ connected: false })], {}).address, BUDS)
assert.equal(model.pickReconnectCandidate([row({ connected: false, paired: false })], {}), null)
assert.equal(model.pickReconnectCandidate([row()], {}), null, 'already connected')
console.log('pickReconnectCandidate: OK')

// ---- battery ----
assert.equal(model.batteryPercent(0.6, true), 60)
assert.equal(model.batteryPercent(0.6, false), -1, 'unavailable is not 0%')
assert.equal(model.batteryPercent(undefined, true), -1)
assert.equal(model.batteryPercent(1.0, true), 100)
assert.equal(model.batteryPercent(0, true), 0)
console.log('batteryPercent: OK')

// ---- profiles: the Redmi Buds 6 Play as observed with `pactl list cards` ----
const redmiObserved = {
  name: 'bluez_card.AA_BB_CC_DD_EE_FF', active_profile: 'a2dp-sink',
  profiles: {
    off: { description: 'Off', sinks: 0, sources: 0, priority: 0, available: true },
    'a2dp-sink': { description: 'High Fidelity Playback (A2DP Sink, codec SBC)', sinks: 1, sources: 0, priority: 132, available: true },
    'a2dp-sink-sbc_xq': { description: 'High Fidelity Playback (A2DP Sink, codec SBC-XQ)', sinks: 1, sources: 0, priority: 131, available: true },
    'headset-head-unit-cvsd': { description: 'Headset Head Unit (HSP/HFP, codec CVSD)', sinks: 1, sources: 1, priority: 4, available: true },
    'headset-head-unit': { description: 'Headset Head Unit (HSP/HFP, codec MSBC)', sinks: 1, sources: 1, priority: 5, available: true }
  }
}
function checkRedmi(card, label) {
  const g = model.groupProfiles(card)
  assert.equal(g.activeMode, 'music', label)
  assert.equal(g.activeCodec, 'SBC', label)
  assert.deepEqual(g.music.codecs.map(c => c.codec), ['SBC', 'SBC-XQ'], label)
  assert.deepEqual(g.call.codecs.map(c => c.codec), ['mSBC', 'CVSD'], label)
  assert.equal(model.bestProfileFor(g, 'call'), 'headset-head-unit', label + ': highest-priority call profile is mSBC')
  assert.equal(model.bestProfileFor(g, 'music'), 'a2dp-sink', label)
}
checkRedmi(redmiObserved, 'observed')
const realFixture = path.join(__dirname, 'fixtures', 'redmi-buds-6-play.json')
if (fs.existsSync(realFixture)) {
  const cards = JSON.parse(fs.readFileSync(realFixture, 'utf8'))
  const card = cards.find(c => c.name === 'bluez_card.AA_BB_CC_DD_EE_FF')
  assert.ok(card, 'fixture holds the Redmi card')
  const g = model.groupProfiles(card)
  assert.deepEqual(g.music.codecs.map(c => c.codec).sort(), ['SBC', 'SBC-XQ'])
  assert.deepEqual(g.call.codecs.map(c => c.codec).sort(), ['CVSD', 'mSBC'])
  console.log('Real Redmi fixture: OK')
}

const synthetic = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'synthetic-cards.json'), 'utf8'))
const ldac = model.groupProfiles(synthetic[0])
assert.equal(ldac.activeCodec, 'LDAC')
assert.deepEqual(ldac.music.codecs.map(c => c.codec), ['LDAC', 'AAC', 'SBC'])
assert.deepEqual(ldac.call.codecs.map(c => c.codec), ['LC3-SWB'], 'unavailable CVSD is hidden')
const a2dpOnly = model.groupProfiles(synthetic[1])
assert.equal(a2dpOnly.call.codecs.length, 0, 'no call mode offered')
assert.equal(model.bestProfileFor(a2dpOnly, 'call'), '')
assert.equal(model.groupProfiles(null).activeMode, '')
assert.equal(model.groupProfiles({ profiles: 'x' }).music.codecs.length, 0)
assert.equal(model.codecOfProfile('a2dp-sink-sbc_xq', ''), 'SBC-XQ', 'suffix fallback')
console.log('groupProfiles: OK')

// ---- vendor helpers ----
assert.equal(model.hasXiaomiControl(['0000FD2D-0000-1000-8000-00805F9B34FB']), true)
assert.equal(model.hasXiaomiControl(['0000110b-0000-1000-8000-00805f9b34fb']), false)
assert.equal(model.hasXiaomiControl(null), false)
assert.deepEqual(model.vendorBatteryCell(60), { percent: 60, charging: false })
assert.deepEqual(model.vendorBatteryCell(0x80 | 40), { percent: 40, charging: true })
assert.equal(model.vendorBatteryCell(255), null)
assert.equal(model.vendorBatteryCell(0x7f), null, '127% is invalid')
console.log('vendor helpers: OK')

// ---- helper json ----
assert.deepEqual(model.parseHelperJson('{"ok":true}'), { ok: true })
assert.equal(model.parseHelperJson('not json'), null)
assert.equal(model.parseHelperJson('[1]'), null)
assert.equal(model.parseHelperJson('x'.repeat(70000)), null)
console.log('parseHelperJson: OK')

// ---- gesture order ----
assert.deepEqual(model.orderGestures(['1', '2', '3', '4']), ['4', '1', '2', '3'])
assert.deepEqual(model.orderGestures(['9999', '3', '4']), ['4', '3', '9999'])
assert.deepEqual(model.orderGestures(null), [])
console.log('orderGestures: OK')
