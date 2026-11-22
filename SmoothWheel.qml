// SPDX-License-Identifier: GPL-3.0-only
// Copiado sem alterações de eusener.power/SmoothWheel.qml (o mesmo componente
// usado em eusener.yubikey e eusener.vpn).
import QtQuick
import Quickshell.Io
import qs.Commons

// Touchpad and mouse-wheel scrolling for a Flickable, ListView or GridView
// inside the Omarchy shell. Put it inside the view and set `flickable`.
//
// Qt Quick's own wheel handling turns touchpad gestures into slow, stepped
// motion here: Hyprland scales touchpad deltas by input:touchpad:scroll_factor
// (often 0.4, tuned for browsers that add their own acceleration), pixelDelta
// arrives rounded to whole pixels, and Flickable.flick() does not move when
// started from a wheel gesture. So:
//   - the gain undoes scroll_factor (clamped to 1-4);
//   - steps come from angleDelta / 12, which carries the same motion at
//     about 12x the resolution of pixelDelta;
//   - lifting the fingers coasts with constant deceleration (an animation,
//     off when Omarchy animations are off);
//   - a mouse notch moves `step` px with a short eased animation that
//     accumulates consecutive notches.
WheelHandler {
  id: root
  required property Flickable flickable
  property real step: Style.space(96)
  property real deceleration: 5000
  property real touchpadGain: Math.max(1, Math.min(4, 1 / Math.max(0.05, scrollFactor)))
  property real scrollFactor: 1

  property real _velocity: 0
  property real _lastAt: 0

  target: null
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  orientation: Qt.Vertical

  readonly property real minY: flickable.originY - flickable.topMargin
  readonly property real maxY: Math.max(minY, flickable.originY + flickable.contentHeight + flickable.bottomMargin - flickable.height)
  function clamp(y) { return Math.max(minY, Math.min(maxY, y)) }

  function stop() { anim.stop() }

  function coast(velocity) {
    var speed = Math.min(Math.abs(velocity), 6000)
    var distance = speed * speed / (2 * deceleration)
    var to = clamp(flickable.contentY + (velocity < 0 ? distance : -distance))
    var duration = Style.duration(Math.round(speed / deceleration * 1000))
    if (duration <= 0 || Math.abs(to - flickable.contentY) < 1) return
    anim.easing.type = Easing.OutQuad
    anim.duration = duration
    anim.from = flickable.contentY
    anim.to = to
    anim.restart()
  }

  onWheel: function(event) {
    if (flickable.contentHeight + flickable.topMargin + flickable.bottomMargin <= flickable.height) {
      event.accepted = false
      return
    }
    var now = Date.now()
    var touchpad = (event.device && event.device.type === PointerDevice.TouchPad)
      || event.phase !== Qt.NoScrollPhase || event.pixelDelta.y !== 0
    if (!touchpad) {
      let from = anim.running ? anim.to : flickable.contentY
      let to = clamp(from - event.angleDelta.y / 120 * step)
      anim.stop()
      anim.easing.type = Easing.OutCubic
      anim.duration = Style.duration(140)
      if (anim.duration <= 0) { flickable.contentY = to; return }
      anim.from = flickable.contentY
      anim.to = to
      anim.start()
      return
    }
    if (event.phase === Qt.ScrollEnd) {
      // The gesture ends with an empty event: keep its motion going.
      if (now - _lastAt < 80 && Math.abs(_velocity) > 200) coast(_velocity)
      _velocity = 0
      return
    }
    var d = (event.angleDelta.y !== 0 ? event.angleDelta.y / 12 : event.pixelDelta.y) * touchpadGain
    anim.stop()
    if (flickable.flicking) flickable.cancelFlick()
    flickable.contentY = clamp(flickable.contentY - d)
    var dt = now - _lastAt
    var v = (dt > 0 && dt < 80) ? d * 1000 / dt : 0
    _velocity = dt >= 80 ? v : _velocity * 0.7 + v * 0.3
    _lastAt = now
  }

  property NumberAnimation anim: NumberAnimation {
    target: root.flickable
    property: "contentY"
  }

  property Connections dragStop: Connections {
    target: root.flickable
    function onDraggingChanged() { if (root.flickable.dragging) root.anim.stop() }
  }

  property Process scrollFactorProc: Process {
    running: true
    command: ["hyprctl", "-j", "getoption", "input:touchpad:scroll_factor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          let f = Number(JSON.parse(text || "{}").float)
          if (isFinite(f) && f > 0) root.scrollFactor = f
        } catch (e) {}
      }
    }
  }
}
