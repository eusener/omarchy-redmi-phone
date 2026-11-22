// SPDX-License-Identifier: GPL-3.0-only
//
// Headphones: a bar button with the active Bluetooth headphone's battery and a
// popup panel for its audio mode, codec, default output, autoswitch, media
// buttons and — on Xiaomi/Redmi buds — vendor features.
//
// Live state (connection, battery, default sink) comes from Quickshell's
// Bluetooth and Pipewire services. Card profiles, autoswitch and the
// mpris-proxy unit come from bin/headphones-ctl, polled only while the panel
// is open. Every state change goes through that helper with an argv array.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "eusener.headphones"
  ipcTarget: "eusener.headphones"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function localPath(rel) { return Qt.resolvedUrl(rel).toString().replace(/^file:\/\//, "") }
  readonly property string ctlPath: localPath("bin/headphones-ctl")

  // ---------- Bluetooth state (primitive rows only) ----------
  readonly property var rows: {
    var values = Bluetooth.devices ? Bluetooth.devices.values : []
    var out = []
    for (var i = 0; i < values.length; i++) {
      var r = Model.deviceRow(values[i])
      if (r) out.push(r)
    }
    return out
  }
  // address -> sequence of the last time we saw it connect. Never pruned, so
  // the most recently used headphone is the one offered for reconnection.
  property var connectOrder: ({})
  property int connectSeq: 0
  property var connectedSeen: ({})
  onRowsChanged: {
    var seen = {}
    var order = connectOrder
    var changed = false
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].connected) continue
      seen[rows[i].address] = true
      if (!connectedSeen[rows[i].address]) { order[rows[i].address] = ++connectSeq; changed = true }
    }
    connectedSeen = seen
    if (changed) connectOrder = Object.assign({}, order)
  }

  readonly property string defaultSinkName: Pipewire.defaultAudioSink ? String(Pipewire.defaultAudioSink.name || "") : ""
  readonly property var active: Model.pickActiveHeadphone(rows, defaultSinkName, connectOrder)
  readonly property var reconnectCandidate: active ? null : Model.pickReconnectCandidate(rows, connectOrder)
  readonly property string activeAddress: active ? active.address : ""
  readonly property int batteryPct: active ? Model.batteryPercent(active.battery, active.batteryAvailable) : -1

  function percentText(p) { return Commons.I18n.formatNumber(p) + "%" }

  // ---------- Helper status ----------
  property var status: null
  readonly property bool statusFresh: !!status && status.address === activeAddress
  readonly property var groups: Model.groupProfiles(statusFresh ? status.card : null)
  readonly property bool hasMusic: groups.music.codecs.length > 0
  readonly property bool hasCall: groups.call.codecs.length > 0

  onActiveAddressChanged: {
    status = null
    clearPending()
    errorText = ""
    resetVendor()
    if (opened && activeAddress) refreshStatus()
  }
  onOpenedChanged: {
    if (opened) {
      errorText = ""
      refreshStatus()
      if (hasXiaomi) probeVendor()
    } else {
      vendorRequested = false
    }
  }

  property bool statusDirty: false
  function refreshStatus() {
    if (!activeAddress) return
    if (statusProc.running) { statusDirty = true; return }
    statusDirty = false
    statusProc.command = [ctlPath, "status", activeAddress]
    statusProc.running = true
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseHelperJson(text)
        if (parsed && parsed.ok) root.status = parsed
        root.reconcilePending()
        if (root.statusDirty) Qt.callLater(root.refreshStatus)
      }
    }
  }
  // Event-driven refresh while the panel is open: `pactl subscribe` sleeps until
  // a card (profile), sink/source (devices) or the server (default device)
  // changes. Stream events (sink-input/source-output) are ignored; the profile
  // switch they cause arrives as a card event. Autoswitch and mpris-proxy emit
  // no pactl events, so a slow fallback catches changes made outside the panel.
  Process {
    id: audioEvents
    running: root.opened && root.activeAddress !== ""
    command: ["pactl", "subscribe"]
    environment: ({ LC_ALL: "C" })
    stdout: SplitParser {
      onRead: function(line) {
        if (/ on (card|sink|source|server) #/.test(line)) eventDebounce.restart()
      }
    }
  }
  Timer { id: eventDebounce; interval: 250; onTriggered: root.refreshStatus() }
  Timer { interval: 30000; repeat: true; running: audioEvents.running; onTriggered: root.refreshStatus() }

  // ---------- Actions ----------
  // One helper action at a time; each is followed by a status refresh.
  property string errorText: ""
  property string pendingProfile: ""
  property string pendingSwitch: ""       // "autoswitch" | "media" | "default"
  property string pendingDevice: ""       // "connecting" | "disconnecting"
  property string pendingDeviceAddress: ""
  property var actionQueue: []

  function clearPending() {
    pendingProfile = ""
    pendingSwitch = ""
    pendingTimer.stop()
  }

  function runAction(args, onDone) {
    actionQueue = actionQueue.concat([{ args: [ctlPath].concat(args), onDone: onDone }])
    pumpActions()
  }
  function pumpActions() {
    if (actionProc.running || actionQueue.length === 0) return
    var next = actionQueue[0]
    actionQueue = actionQueue.slice(1)
    actionProc.currentDone = next.onDone || null
    actionProc.command = next.args
    actionProc.running = true
  }
  Process {
    id: actionProc
    property var currentDone: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseHelperJson(text)
        var done = actionProc.currentDone
        actionProc.currentDone = null
        if (done) done(parsed && parsed.ok === true, parsed)
        root.refreshStatus()
        Qt.callLater(root.pumpActions)
      }
    }
  }

  function setProfile(profile) {
    if (!profile || !activeAddress || profile === groups.activeProfile) return
    errorText = ""
    pendingProfile = profile
    pendingTimer.restart()
    runAction(["set-profile", activeAddress, profile], function(ok) {
      if (!ok) failPending(strings.t("error.profile", "Could not switch the audio mode."))
    })
  }
  function setMode(mode) {
    if (mode === groups.activeMode) return
    setProfile(Model.bestProfileFor(groups, mode))
  }
  function setSwitch(kind, args, message) {
    errorText = ""
    pendingSwitch = kind
    pendingTimer.restart()
    runAction(args, function(ok) {
      root.pendingSwitch = ""
      if (!ok) root.errorText = message
    })
  }
  function makeDefault() {
    if (!activeAddress) return
    setSwitch("default", ["set-default", activeAddress], strings.t("error.output", "Could not make the headphones the default output."))
  }
  function toggleAutoswitch() {
    if (!statusFresh || status.autoswitch === null) return
    setSwitch("autoswitch", ["autoswitch", status.autoswitch ? "off" : "on"], strings.t("error.autoswitch", "Could not change automatic call mode."))
  }
  function setMic(which) {
    if (!statusFresh || !status.mic || status.mic.source === which) return
    setSwitch("mic", ["mic", activeAddress, which], strings.t("error.mic", "Could not switch the microphone."))
  }
  function toggleMediaButtons() {
    if (!statusFresh || !status.mediaButtons || !status.mediaButtons.available) return
    var on = status.mediaButtons.enabled && status.mediaButtons.active
    setSwitch("media", ["media-buttons", on ? "off" : "on"], strings.t("error.media", "Could not change the media buttons setting."))
  }

  function failPending(message) {
    pendingProfile = ""
    pendingTimer.stop()
    errorText = message
  }
  // The pending choice resolves when the real profile matches it; otherwise the
  // timer reverts the UI to whatever the card actually reports.
  function reconcilePending() {
    if (pendingProfile && groups.activeProfile === pendingProfile) {
      pendingProfile = ""
      pendingTimer.stop()
    }
  }
  Timer {
    id: pendingTimer
    interval: 5000
    onTriggered: {
      if (root.pendingProfile) root.failPending(strings.t("error.profileTimeout", "The headphones did not switch in time; showing the current mode."))
      root.pendingSwitch = ""
    }
  }

  function connectHeadphone(row) {
    if (!row || !Model.isMac(row.address)) return
    errorText = ""
    pendingDevice = "connecting"
    pendingDeviceAddress = row.address
    deviceTimer.restart()
    runAction(["connect", row.address], function(ok) {
      if (!ok) root.failDevice(strings.t("error.connect", "Could not connect. Take the earbuds out of the case and try again."))
    })
  }
  function disconnectHeadphone() {
    if (!activeAddress) return
    errorText = ""
    pendingDevice = "disconnecting"
    pendingDeviceAddress = activeAddress
    deviceTimer.restart()
    runAction(["disconnect", activeAddress], function(ok) {
      if (!ok) root.failDevice(strings.t("error.disconnect", "Could not disconnect the headphones."))
    })
  }
  function failDevice(message) {
    pendingDevice = ""
    pendingDeviceAddress = ""
    deviceTimer.stop()
    errorText = message
  }
  onActiveChanged: {
    if (pendingDevice === "connecting" && active && active.address === pendingDeviceAddress) { pendingDevice = ""; deviceTimer.stop() }
    if (pendingDevice === "disconnecting" && (!active || active.address !== pendingDeviceAddress)) { pendingDevice = ""; deviceTimer.stop() }
  }
  Timer {
    id: deviceTimer
    interval: 20000
    onTriggered: root.failDevice(root.pendingDevice === "connecting"
      ? strings.t("error.connect", "Could not connect. Take the earbuds out of the case and try again.")
      : strings.t("error.disconnect", "Could not disconnect the headphones."))
  }

  // ---------- Xiaomi vendor features (bin/buds-vendor) ----------
  // Only for headphones that advertise the Xiaomi control UUID, only while the
  // panel is open, one RFCOMM session per helper call (spec xiaomi-vendor-*).
  readonly property string vendorPath: localPath("bin/buds-vendor")
  readonly property bool hasXiaomi: statusFresh && Model.hasXiaomiControl(status.uuids)
  property var vendor: null               // last probe/set result for activeAddress
  property string vendorError: ""         // helper error code
  property string vendorPending: ""       // "probe" | "latency" | "eq" | "gesture:<id>:<side>"
  property bool vendorRequested: false
  property var vendorQueue: []

  function resetVendor() {
    vendor = null
    vendorError = ""
    vendorPending = ""
    vendorRequested = false
    vendorQueue = []
  }
  onHasXiaomiChanged: if (hasXiaomi && opened && !vendorRequested) probeVendor()

  function probeVendor() {
    if (!hasXiaomi || !activeAddress) return
    vendorRequested = true
    vendorError = ""
    runVendor("probe", ["probe", activeAddress])
  }
  function runVendor(kind, args) {
    vendorQueue = vendorQueue.concat([{ kind: kind, address: activeAddress, args: [vendorPath].concat(args) }])
    pumpVendor()
  }
  function pumpVendor() {
    if (vendorProc.running || vendorQueue.length === 0) return
    var next = vendorQueue[0]
    vendorQueue = vendorQueue.slice(1)
    vendorPending = next.kind
    vendorProc.address = next.address
    vendorProc.kind = next.kind
    vendorProc.command = next.args
    vendorProc.running = true
  }
  Process {
    id: vendorProc
    property string address: ""
    property string kind: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseHelperJson(text)
        var stale = vendorProc.address !== root.activeAddress
        root.vendorPending = ""
        if (!stale) {
          if (!parsed) root.vendorError = "protocol"
          else if (!parsed.ok) root.vendorError = String(parsed.error || "failed")
          else root.mergeVendor(vendorProc.kind, parsed)
        }
        Qt.callLater(root.pumpVendor)
      }
    }
  }
  function mergeVendor(kind, r) {
    vendorError = ""
    if (kind === "probe") { vendor = r; return }
    var v = Object.assign({}, vendor || {})
    if (r.latency !== undefined) v.latency = r.latency
    if (r.eq) v.eq = r.eq
    if (r.gestures) v.gestures = r.gestures
    if (r.battery) v.battery = r.battery
    vendor = v
  }
  function vendorHas(feature) {
    return !!vendor && Array.isArray(vendor.features) && vendor.features.indexOf(feature) >= 0
  }
  function setLatency(on) {
    if (vendorPending) return
    runVendor("latency", ["latency", "set", activeAddress, on ? "on" : "off"])
  }
  function setEqProfile(id) {
    if (vendorPending || !vendor || !vendor.eq || String(vendor.eq.profile) === String(id)) return
    runVendor("eq", ["eq", "set", activeAddress, String(id)])
  }
  function setGesture(gesture, side, action) {
    if (vendorPending) return
    runVendor("gesture:" + gesture + ":" + side, ["gestures", "set", activeAddress, String(gesture), side, String(action)])
  }
  function vendorErrorText(code) {
    if (code === "refused") return strings.t("vendor.error.refused", "The headphones refused the control connection. Is a phone with the Xiaomi Earbuds app connected to them?")
    if (code === "auth_failed") return strings.t("vendor.error.auth", "Could not authenticate with the headphones.")
    if (code === "timeout") return strings.t("vendor.error.timeout", "The headphones did not answer in time.")
    if (code === "unconfirmed") return strings.t("vendor.error.unconfirmed", "The headphones did not confirm the change.")
    if (code === "not_connected") return strings.t("vendor.error.notConnected", "The headphones are not connected.")
    return strings.t("vendor.error.protocol", "The headphones sent an unexpected answer.")
  }
  function batteryCellText(label, cell) {
    if (!cell) return ""
    return strings.t("vendor.batteryCell", "%1 %2").arg(label).arg(percentText(cell.percent)) + (cell.charging ? " 󱐋" : "")
  }
  function eqName(id) { return strings.t("eq." + id, strings.t("eq.unknown", "Preset %1").arg(id)) }
  function gestureName(id) { return strings.t("gesture." + id, strings.t("gesture.unknown", "Gesture %1").arg(id)) }
  function actionName(id) { return strings.t("action." + id, strings.t("action.unknown", "Action %1").arg(id)) }

  // ---------- Labels ----------
  readonly property string displayName: active ? (active.name || active.address) : ""
  readonly property string tooltip: active
    ? (batteryPct >= 0 ? strings.t("bar.tooltipBattery", "%1 · %2").arg(displayName).arg(percentText(batteryPct)) : displayName)
    : strings.t("bar.none", "No headphones connected")
  readonly property string heroStatus: {
    if (pendingDevice === "connecting") return strings.t("state.connecting", "Connecting…")
    if (pendingDevice === "disconnecting") return strings.t("state.disconnecting", "Disconnecting…")
    if (!active) return strings.t("state.none", "No headphones connected")
    if (groups.activeMode === "call") return strings.t("state.call", "Call mode · %1").arg(groups.activeCodec)
    if (groups.activeMode === "music") return strings.t("state.music", "Music mode · %1").arg(groups.activeCodec)
    return strings.t("state.connected", "Connected")
  }
  readonly property string iconGlyph: active ? "󰋋" : "󰟎"

  // ---------- Bar button ----------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    opacity: root.active ? 1 : 0.45
    labelText: root.batteryPct >= 0 && !vertical ? root.percentText(root.batteryPct) : ""
    slotSize: Style.bar.iconSlot * (labelText !== "" ? 2 : 1)
    tooltipText: root.tooltip
    onPressed: function(b) { root.toggle() }
  }

  // ---------- Panel ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Touchpad gain, precise steps and momentum after the fingers lift.
        SmoothWheel {
          id: smoothWheel
          flickable: scroller
        }

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(12)

          // Hero: glyph · name/status · battery
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            PlainText {
              id: heroIcon
              text: root.iconGlyph
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.active ? 1 : 0.5
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroPercent.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              PlainText {
                width: parent.width
                text: root.active ? root.displayName : strings.t("panel.title", "Headphones")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              PlainText {
                width: parent.width
                text: root.heroStatus
                color: root.bar.foreground
                opacity: 0.65
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            PlainText {
              id: heroPercent
              text: root.batteryPct >= 0 ? root.percentText(root.batteryPct) : ""
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // No headphone: offer the last paired one, else point at Bluetooth.
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.active
            PlainText {
              width: parent.width
              visible: !root.reconnectCandidate
              wrapMode: Text.WordWrap
              text: strings.t("panel.pairHint", "Pair headphones in the Bluetooth panel first.")
              color: root.bar.foreground
              opacity: 0.7
              font.family: root.bar.fontFamily
            }
            Button {
              visible: !!root.reconnectCandidate
              enabled: root.pendingDevice === ""
              text: root.reconnectCandidate
                ? strings.t("action.connectNamed", "Connect %1").arg(root.reconnectCandidate.name || root.reconnectCandidate.address)
                : ""
              iconText: "󰂱"
              bordered: true
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.connectHeadphone(root.reconnectCandidate)
            }
          }

          // Mode
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: !!root.active && (root.hasMusic || root.hasCall)
            PanelSeparator { width: parent.width; foreground: root.bar.foreground }
            PanelSectionHeader { text: strings.t("section.mode", "Audio mode"); foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            ButtonGroup {
              width: parent.width
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              options: {
                var o = []
                if (root.hasMusic) o.push({ value: "music", label: strings.t("mode.music", "Music"), icon: "󰝚", tooltip: strings.t("mode.musicHint", "High quality, no microphone") })
                if (root.hasCall) o.push({ value: "call", label: strings.t("mode.call", "Call"), icon: "󰋎", tooltip: strings.t("mode.callHint", "Microphone on, lower audio quality") })
                return o
              }
              value: root.pendingProfile ? Model.modeOfProfile(root.pendingProfile) : root.groups.activeMode
              onChanged: function(v) { root.setMode(v) }
            }
            PanelSectionHeader {
              text: strings.t("section.codec", "Codec")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              visible: codecGroup.options.length > 1
            }
            ButtonGroup {
              id: codecGroup
              width: parent.width
              visible: options.length > 1
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              readonly property string mode: root.pendingProfile ? Model.modeOfProfile(root.pendingProfile) : root.groups.activeMode
              options: {
                var list = mode && root.groups[mode] ? root.groups[mode].codecs : []
                var o = []
                for (var i = 0; i < list.length; i++) o.push({ value: list[i].profile, label: list[i].codec })
                return o
              }
              value: root.pendingProfile || root.groups.activeProfile
              onChanged: function(v) { root.setProfile(v) }
            }
          }

          // Output, autoswitch, media buttons
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !!root.active
            PanelSeparator { width: parent.width; foreground: root.bar.foreground }
            Item {
              width: parent.width
              implicitHeight: Math.max(outputLabel.implicitHeight, outputButton.implicitHeight)
              PlainText {
                id: outputLabel
                anchors.left: parent.left
                anchors.right: outputButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.statusFresh && root.status.isDefaultSink
                  ? strings.t("output.isDefault", "Default audio output")
                  : strings.t("output.notDefault", "Not the default audio output")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
              }
              Button {
                id: outputButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.statusFresh && !root.status.isDefaultSink
                enabled: root.pendingSwitch === ""
                text: strings.t("action.useOutput", "Use as output")
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.makeDefault()
              }
            }
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.statusFresh && !!root.status.mic && root.status.mic.internalAvailable
              PanelSectionHeader {
                text: strings.t("section.mic", "Microphone")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              ButtonGroup {
                width: parent.width
                enabled: root.pendingSwitch === ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                options: [
                  { value: "headset", label: strings.t("mic.headset", "Headphones"), icon: "󰋎",
                    tooltip: strings.t("mic.headsetHint", "Talk through the headphones; audio drops to call quality while an app records") },
                  { value: "internal", label: strings.t("mic.internal", "Laptop"), icon: "󰍬",
                    tooltip: strings.t("mic.internalHint", "Talk through the laptop microphone; the headphones keep high-quality audio") }
                ]
                value: root.statusFresh && root.status.mic ? root.status.mic.source : ""
                onChanged: function(v) { root.setMic(v) }
              }
              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.statusFresh && root.status.mic && root.status.mic.source === "internal"
                  ? strings.t("mic.internalNote", "Headphones stay in music quality; apps use the laptop microphone.")
                  : strings.t("mic.headsetNote", "Apps that use the microphone switch the headphones to call mode.")
                color: root.bar.foreground
                opacity: 0.65
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Toggle {
              width: parent.width
              label: strings.t("autoswitch.label", "Switch to call mode automatically")
              description: strings.t("autoswitch.description", "When an app opens the microphone, move the headphones to call mode")
              checked: root.statusFresh && root.status.autoswitch === true
              enabled: root.statusFresh && root.status.autoswitch !== null && root.pendingSwitch === ""
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.toggleAutoswitch()
            }
            Toggle {
              width: parent.width
              readonly property bool available: root.statusFresh && !!root.status.mediaButtons && root.status.mediaButtons.available
              label: strings.t("media.label", "Headphone buttons control the player")
              description: available
                ? strings.t("media.description", "Taps on the headphones play, pause and skip in the active player")
                : strings.t("media.missing", "Unavailable: mpris-proxy (bluez-utils) is not installed")
              checked: available && root.status.mediaButtons.enabled && root.status.mediaButtons.active
              enabled: available && root.pendingSwitch === ""
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.toggleMediaButtons()
            }
          }

          // Xiaomi vendor features
          Column {
            id: vendorSection
            width: parent.width
            spacing: Style.space(8)
            visible: !!root.active && root.hasXiaomi
            readonly property bool busy: root.vendorPending !== ""

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }
            Item {
              width: parent.width
              implicitHeight: Math.max(vendorHeader.implicitHeight, refreshButton.implicitHeight)
              PanelSectionHeader {
                id: vendorHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("vendor.title", "Xiaomi features")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              PanelActionButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                tooltipText: strings.t("vendor.refresh", "Refresh")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: !vendorSection.busy
                onClicked: root.probeVendor()
              }
            }
            PlainText {
              width: parent.width
              visible: vendorSection.busy && !root.vendor
              text: strings.t("vendor.reading", "Reading the headphones…")
              color: root.bar.foreground
              opacity: 0.65
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.vendorError !== ""
              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.vendorErrorText(root.vendorError)
                color: Commons.Color.urgent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                text: strings.t("vendor.retry", "Try again")
                bordered: true
                enabled: !vendorSection.busy
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.probeVendor()
              }
            }

            // Battery per earbud and case
            PlainText {
              width: parent.width
              visible: root.vendorHas("battery") && !!root.vendor.battery
              text: {
                var b = root.vendor && root.vendor.battery ? root.vendor.battery : {}
                return [root.batteryCellText(strings.t("vendor.left", "L"), b.left),
                        root.batteryCellText(strings.t("vendor.right", "R"), b.right),
                        root.batteryCellText(strings.t("vendor.case", "Case"), b["case"])]
                  .filter(function(s) { return s !== "" }).join("   ")
              }
              color: root.bar.foreground
              font.family: root.bar.fontFamily
            }

            // Low latency
            Toggle {
              width: parent.width
              visible: root.vendorHas("latency")
              label: strings.t("vendor.latency", "Low latency (game mode)")
              description: root.vendorPending === "latency"
                ? strings.t("vendor.applying", "Applying…")
                : strings.t("vendor.latencyHint", "Less audio delay, slightly shorter range")
              checked: !!root.vendor && root.vendor.latency === true
              enabled: !vendorSection.busy
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.setLatency(!(root.vendor && root.vendor.latency === true))
            }

            // EQ preset
            Dropdown {
              width: parent.width
              visible: root.vendorHas("eq")
              label: root.vendorPending === "eq" ? strings.t("vendor.eqApplying", "Equalizer · applying…") : strings.t("vendor.eq", "Equalizer")
              enabled: !vendorSection.busy
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              options: {
                var ids = root.vendor && root.vendor.eq ? root.vendor.eq.profiles || [] : []
                var o = []
                for (var i = 0; i < ids.length; i++) o.push({ value: String(ids[i]), label: root.eqName(ids[i]) })
                return o
              }
              value: root.vendor && root.vendor.eq && root.vendor.eq.profile !== null ? String(root.vendor.eq.profile) : ""
              onChanged: function(v) { root.setEqProfile(v) }
            }

            // Gestures: one row per gesture, left and right
            PanelSectionHeader {
              visible: root.vendorHas("gestures")
              text: strings.t("vendor.gestures", "Touch controls")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }
            Repeater {
              model: root.vendorHas("gestures") ? Model.orderGestures(Object.keys(root.vendor.gestures.allowed || {})) : []
              delegate: Column {
                id: gestureRow
                required property string modelData
                readonly property var allowed: root.vendor.gestures.allowed[modelData] || []
                readonly property var assigned: (root.vendor.gestures.assignments || {})[modelData] || null
                readonly property var actionOptions: {
                  var o = []
                  for (var i = 0; i < allowed.length; i++) o.push({ value: String(allowed[i]), label: root.actionName(allowed[i]) })
                  return o
                }
                width: vendorSection.width
                spacing: Style.space(4)
                visible: assigned !== null
                PlainText {
                  text: root.gestureName(gestureRow.modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  opacity: 0.8
                }
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Repeater {
                    model: ["left", "right"]
                    delegate: Dropdown {
                      required property string modelData
                      width: (gestureRow.width - Style.space(8)) / 2
                      label: root.vendorPending === "gesture:" + gestureRow.modelData + ":" + modelData
                        ? strings.t("vendor.applying", "Applying…")
                        : (modelData === "left" ? strings.t("vendor.leftLong", "Left") : strings.t("vendor.rightLong", "Right"))
                      enabled: !vendorSection.busy
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      options: gestureRow.actionOptions
                      value: gestureRow.assigned ? String(gestureRow.assigned[modelData]) : ""
                      onChanged: function(v) {
                        if (gestureRow.assigned && String(gestureRow.assigned[modelData]) === v) return
                        root.setGesture(gestureRow.modelData, modelData, v)
                      }
                    }
                  }
                }
              }
            }
          }

          // Errors
          PlainText {
            width: parent.width
            visible: root.errorText !== ""
            wrapMode: Text.WordWrap
            text: root.errorText
            color: Commons.Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Disconnect
          Button {
            visible: !!root.active
            enabled: root.pendingDevice === ""
            text: strings.t("action.disconnect", "Disconnect")
            iconText: "󰂲"
            bordered: true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.disconnectHeadphone()
          }
        }
      }
    }
  }
}
