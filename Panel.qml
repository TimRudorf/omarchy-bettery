import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Bettery.js" as Bettery

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false

  // ---------- Battery care (sailing) ----------
  // The plugin's own service owns the hardware; the panel reads it and calls it.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  property var care: null
  // Slider values while a handle is held, so the hardware is written on release.
  property var draftLimits: null
  // Keyboard rows, top to bottom: care, end, start, actions, profiles.
  property string cursorRow: "care"
  property int actionIndex: 0
  readonly property var careHw: care ? care.hw : Bettery.parseStatus("")
  readonly property bool careSupported: !!care && careHw.supported
  readonly property bool careWritable: careSupported && careHw.writable
  readonly property bool careEnabled: careSupported && care.enabled
  readonly property string careMode: careSupported ? care.mode : "normal"
  // Pause and discharge stop the flow into the battery although the charger is in.
  readonly property bool careStopsCharging: careMode === "pause" || careMode === "discharge"
  readonly property var shownLimits: draftLimits || (care ? care.limits : Bettery.clampLimits())
  readonly property var careActions: {
    if (!careWritable || UPower.onBattery) return []
    var list = []
    if (careEnabled) list.push({ id: "topUp", icon: Bettery.modeIcon("topUp"), label: strings.t("action.topUp") })
    if (careHw.canPause) list.push({ id: "pause", icon: Bettery.modeIcon("pause"), label: strings.t("action.pause") })
    if (careEnabled && careHw.canDischarge) list.push({ id: "discharge", icon: Bettery.modeIcon("discharge"), label: strings.t("action.discharge") })
    return list
  }
  readonly property var cursorRows: {
    var rows = []
    if (careWritable) rows.push("care")
    if (careWritable && careEnabled) {
      rows.push("end")
      if (careHw.hasStart) rows.push("start")
    }
    if (careActions.length > 0) rows.push("actions")
    if (profiles.length > 0) rows.push("profiles")
    return rows
  }

  function findCare() {
    var api = root.bar ? root.bar.shell : null
    var service = api && typeof api.serviceFor === "function" ? api.serviceFor("bettery") : null
    if (service) root.care = service
  }

  function careLabel() {
    if (careMode === "topUp") return strings.t("status.topUp")
    if (careMode === "pause") return strings.t("status.paused")
    if (careMode === "discharge") return strings.t("status.dischargingTo").arg(root.reading(shownLimits.end + "%"))
    return ""
  }

  function moveCursorRow(dy) {
    var rows = cursorRows
    if (rows.length === 0) return
    var idx = rows.indexOf(cursorRow)
    cursorRow = rows[idx < 0 ? 0 : Math.max(0, Math.min(rows.length - 1, idx + dy))]
  }

  function moveCursorColumn(dx) {
    if (cursorRow === "end") commitLimits(Bettery.withEnd(shownLimits, shownLimits.end + dx))
    else if (cursorRow === "start") commitLimits(Bettery.withStart(shownLimits, shownLimits.start + dx))
    else if (cursorRow === "actions") actionIndex = Model.clampIndex(actionIndex + dx, careActions.length)
    else if (cursorRow === "profiles") selectProfileByDelta(dx)
  }

  function activateCursor() {
    if (cursorRow === "care") care.setEnabled(!care.enabled)
    else if (cursorRow === "actions" && careActions[actionIndex]) care.toggleMode(careActions[actionIndex].id)
    else if (cursorRow === "profiles") activateSelectedProfile()
  }

  function commitLimits(limits) {
    draftLimits = null
    if (care) care.setLimits(limits.start, limits.end)
  }

  Timer {
    interval: 1000
    running: !root.care
    repeat: true
    triggeredOnStart: true
    onTriggered: root.findCare()
  }

  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    if (device && device.isPresent && Bettery.modeIcon(root.careMode)) return Bettery.modeIcon(root.careMode)
    if (device && device.isPresent && root.careSupported && root.care.holding) return Bettery.levelIcon(device.percentage)
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates(), Commons.I18n.t)
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    if (root.careSupported) return root.care.holding
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle && !root.careStopsCharging
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Commons.Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    Commons.I18n.t("power.chargingPhrase1"),
    Commons.I18n.t("power.chargingPhrase2"),
    Commons.I18n.t("power.chargingPhrase3"),
    Commons.I18n.t("power.chargingPhrase4"),
    Commons.I18n.t("power.chargingPhrase5"),
    Commons.I18n.t("power.chargingPhrase6"),
    Commons.I18n.t("power.chargingPhrase7"),
    Commons.I18n.t("power.chargingPhrase8"),
    Commons.I18n.t("power.chargingPhrase9")
  ]
  readonly property var onBatteryPhrases: [
    Commons.I18n.t("power.dischargingPhrase1"),
    Commons.I18n.t("power.dischargingPhrase2"),
    Commons.I18n.t("power.dischargingPhrase3"),
    Commons.I18n.t("power.dischargingPhrase4"),
    Commons.I18n.t("power.dischargingPhrase5"),
    Commons.I18n.t("power.dischargingPhrase6"),
    Commons.I18n.t("power.dischargingPhrase7"),
    Commons.I18n.t("power.dischargingPhrase8"),
    Commons.I18n.t("power.dischargingPhrase9")
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged || careLabel() !== "") return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  // The battery script's readings in the current language's digits; the
  // time field already comes translated, so it is shown as it arrives.
  function reading(raw) {
    return Model.localizeReading(raw, Commons.I18n.formatNumber)
  }

  readonly property string heroStatusText: {
    if (careLabel() !== "") return careLabel()
    if (chargeThresholdActive && careSupported) return strings.t("status.holding").arg(root.reading(Bettery.rangeLabel(shownLimits, careHw)))
    if (fullyCharged) return Commons.I18n.t("power.fullyCharged")
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  ShellIpc {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        // Deferred: closing here writes the very property whose change
        // is being notified, which QML reports as a binding loop for
        // Panel.opened on every open attempt without a battery.
        Qt.callLater(function() { root.close() })
        return
      }

      refresh()
      if (care) care.refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      cursorRow = cursorRows.length > 0 ? cursorRows[0] : "profiles"
      actionIndex = 0
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: panel.loadedContent ? panel.loadedContent.heroStatus : null; property: "opacity"
      to: 0.0; duration: Style.duration(150); easing.type: Easing.OutCubic
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: panel.loadedContent ? panel.loadedContent.heroStatus : null; property: "opacity"
      to: 1.0; duration: Style.duration(200); easing.type: Easing.OutCubic
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        if (panel.loadedContent) panel.loadedContent.heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.batteryIcon()
    labelText: root.showPercentage && !vertical ? Commons.I18n.formatNumber(Math.round(root.batteryFraction * 100)) + "%" : ""
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias heroStatus: heroStatus
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursorRow(dy)
        else if (dx !== 0) root.moveCursorColumn(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: Commons.I18n.t("power.battery")
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.reading(root.batteryInfo.percentage) || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Style.duration(220) } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened && !Style.reduceMotion
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: Style.duration(950); easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: Style.duration(950); easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: Commons.I18n.t("power.batterySize"); value: root.reading(root.batteryInfo.size) }
            InfoPair { label: Commons.I18n.t("power.chargeCycles"); value: root.reading(root.batteryInfo.cycles) || "—" }
            InfoPair {
              visible: root.careHw.health > 0
              label: strings.t("stats.health")
              value: root.reading(root.careHw.health + "%")
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              readonly property bool showLimit: root.chargeThresholdActive || root.careStopsCharging
              label: showLimit ? Commons.I18n.t("power.chargeLimit") : (root.discharging ? Commons.I18n.t("power.timeLeft") : Commons.I18n.t("power.timeToFull"))
              value: showLimit
                ? (root.careSupported ? root.reading(Bettery.rangeLabel(root.shownLimits, root.careHw)) : (root.reading(root.batteryInfo.threshold) || "-"))
                : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.careMode === "discharge" ? Commons.I18n.t("power.discharging")
                : (root.chargeThresholdActive || root.careMode === "pause") ? Commons.I18n.t("power.batteryState")
                : (root.discharging ? Commons.I18n.t("power.discharging") : Commons.I18n.t("power.charging"))
              value: root.careMode === "discharge" ? root.reading(root.batteryInfo.rate)
                : root.careMode === "pause" ? strings.t("stats.paused")
                : root.chargeThresholdActive ? Commons.I18n.t("power.holding")
                : (root.batteryFull ? "-" : root.reading(root.batteryInfo.rate))
            }
          }
        }

        // ---------- Battery care: charge limit, sailing, top up, pause, discharge ----------
        PanelSeparator {
          visible: root.careSupported
          foreground: root.bar.foreground
        }

        Column {
          visible: root.careSupported
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(careHeader.implicitHeight, careSwitch.implicitHeight)

            PanelSectionHeader {
              id: careHeader
              anchors.left: parent.left
              anchors.right: careSwitch.left
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("care.title")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            ToggleSwitch {
              id: careSwitch
              visible: root.careWritable
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.careEnabled
              hasCursor: root.cursorActive && root.cursorRow === "care"
              foreground: root.bar.foreground
              onHovered: function(on) {
                if (on) {
                  root.cursorActive = true
                  root.cursorRow = "care"
                }
              }
              onToggled: root.care.setEnabled(!root.care.enabled)
            }
          }

          CareNote {
            visible: root.careSupported && !root.careWritable
            text: strings.t("care.setup").arg(root.care ? root.care.pluginDir + "/install.sh" : "install.sh")
          }

          LimitSlider {
            row: "end"
            visible: root.careWritable && root.careEnabled
            label: strings.t("care.stopAt")
            value: root.shownLimits.end
            minimum: Bettery.MIN_END
            maximum: Bettery.MAX_END
            onMovedTo: function(v) { root.draftLimits = Bettery.withEnd(root.shownLimits, v) }
            onReleasedAt: function(v) { root.commitLimits(Bettery.withEnd(root.shownLimits, v)) }
          }

          LimitSlider {
            row: "start"
            visible: root.careWritable && root.careEnabled && root.careHw.hasStart
            label: strings.t("care.resumeAt")
            value: root.shownLimits.start
            minimum: Bettery.MIN_START
            maximum: Bettery.MAX_END - 1
            onMovedTo: function(v) { root.draftLimits = Bettery.withStart(root.shownLimits, v) }
            onReleasedAt: function(v) { root.commitLimits(Bettery.withStart(root.shownLimits, v)) }
          }

          Row {
            id: actionRow
            visible: root.careActions.length > 0
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.careActions.length > 0
              ? (width - spacing * (root.careActions.length - 1)) / root.careActions.length
              : 0

            Repeater {
              model: root.careActions
              Button {
                required property var modelData
                required property int index
                width: actionRow.cellWidth
                iconText: modelData.icon
                iconSize: Style.font.title
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.careMode === modelData.id
                hasCursor: root.cursorActive && root.cursorRow === "actions" && root.actionIndex === index
                onClicked: root.care.toggleMode(modelData.id)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.cursorRow = "actions"
                    root.actionIndex = index
                  }
                }
              }
            }
          }

          CareNote {
            visible: root.careWritable && !!root.care && root.care.lastError !== ""
            text: root.care ? root.care.lastError : ""
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: Commons.I18n.t("power.powerProfile")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: Model.profileLabel(modelData, Commons.I18n.t)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.cursorRow === "profiles" && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.cursorRow = "profiles"
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component LimitSlider: CursorSurface {
    id: limitRow
    property string row: ""
    property string label: ""
    property int value: 0
    property int minimum: 0
    property int maximum: 100
    signal movedTo(int value)
    signal releasedAt(int value)

    width: parent.width
    height: limitColumn.implicitHeight + Style.spacing.controlGap
    hasCursor: root.cursorActive && root.cursorRow === row
    foreground: root.bar.foreground
    outline: true

    Column {
      id: limitColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      InfoPair { label: limitRow.label; value: root.reading(limitRow.value + "%") }

      PanelSlider {
        width: parent.width
        bar: root.bar
        minimum: limitRow.minimum
        maximum: limitRow.maximum
        step: 1
        integer: true
        value: limitRow.value
        onMoved: function(v) { limitRow.movedTo(Math.round(v)) }
        onReleased: function(v) { limitRow.releasedAt(Math.round(v)) }
      }
    }

    HoverHandler {
      onHoveredChanged: if (hovered) {
        root.cursorActive = true
        root.cursorRow = limitRow.row
      }
    }
  }

  component CareNote: Text {
    width: parent.width
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.7
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
