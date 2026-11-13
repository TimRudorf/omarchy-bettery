import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import "Bettery.js" as Bettery

// Keeps the battery's charge controls in line with the user's settings and
// the active mode (top up, pause, discharge). The bar widget only reads this
// service and calls its functions; the CLI reaches the same functions over IPC.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string hwCommand: pluginDir + "/bin/bettery-hw"
  readonly property string configPath: {
    var base = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    return base + "/omarchy/bettery.json"
  }

  property var hw: Bettery.parseStatus("")
  property string lastError: ""
  property bool needsSetup: false

  readonly property string mode: persisted.mode
  readonly property bool enabled: config.enabled
  readonly property var limits: Bettery.clampLimits(config.start, config.end)
  readonly property bool supported: hw.supported
  readonly property real percent: {
    var d = UPower.displayDevice
    return d && d.isPresent ? Math.floor(d.percentage * 100 + 0.001) : -1
  }
  readonly property bool onBattery: UPower.onBattery
  readonly property bool charging: {
    var d = UPower.displayDevice
    return !!(d && d.isPresent && d.state === UPowerDeviceState.Charging && Number(d.changeRate || 0) > 0.2)
  }
  readonly property bool holding: Bettery.holding(configObject(), mode, hw, percent, onBattery, charging)

  PersistentProperties {
    id: persisted
    reloadableId: "bettery-service"
    property string mode: "normal"
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    onLoaded: root.sync()
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) writeAdapter()
    }

    JsonAdapter {
      id: config
      property bool enabled: true
      property int start: Bettery.DEFAULT_START
      property int end: Bettery.DEFAULT_END
    }
  }

  function configObject() {
    return { enabled: config.enabled, start: config.start, end: config.end }
  }

  // ---- Actions (widget and IPC) ----

  function setEnabled(value) {
    config.enabled = !!value
    if (!config.enabled && persisted.mode === "discharge") persisted.mode = "normal"
    sync()
  }

  function setLimits(start, end) {
    var next = Bettery.clampLimits(start, end)
    config.start = next.start
    config.end = next.end
    sync()
  }

  function setMode(next) {
    persisted.mode = next
    sync()
  }

  function toggleMode(next) {
    setMode(persisted.mode === next ? "normal" : next)
  }

  function resume() {
    persisted.mode = "normal"
    sync()
  }

  // ---- Hardware sync ----

  // Every change asks for a sync; a short timer folds a burst of them (both
  // limits set one after the other, a quick on/off) into one write and waits
  // for a running bettery-hw call to finish.
  function sync() {
    syncTimer.restart()
  }

  Timer {
    id: syncTimer
    interval: 80
    onTriggered: root.runSync()
  }

  function runSync() {
    if (hwProc.running) {
      syncTimer.restart()
      return
    }
    var target = Bettery.plan(configObject(), persisted.mode, hw, percent, onBattery)
    if (persisted.mode !== target.mode) persisted.mode = target.mode
    if (hw.known && hw.supported && !Bettery.needsApply(target, hw)) return
    hwProc.command = hw.known && hw.supported
      ? [hwCommand, "apply"].concat(Bettery.applyArgs(target))
      : [hwCommand, "status"]
    hwProc.running = true
  }

  // bettery-hw answers every call with the battery's status on stdout, with
  // any failure reported in-band, so one stream carries the whole result.
  Process {
    id: hwProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.takeStatus(text)
    }
  }

  function takeStatus(raw) {
    var wasKnown = hw.known
    var next = Bettery.parseStatus(raw)
    if (!next.known) return
    hw = next
    lastError = next.error.substring(0, 300)
    needsSetup = next.errorCode === 4 || (next.supported && !next.writable)
    // The first read only learns what the battery supports; apply right after.
    if (!wasKnown) sync()
  }

  function refresh() {
    if (hwProc.running) return
    hwProc.command = [hwCommand, "status"]
    hwProc.running = true
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() { root.sync() }
  }

  onPercentChanged: if (persisted.mode === "discharge") sync()

  // Catches changes made behind the plugin's back (another tool, a firmware
  // reset after resume) and keeps discharge from overshooting.
  Timer {
    interval: persisted.mode === "normal" ? 60000 : 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: sync()

  ShellIpc {
    target: "bettery"

    function status(): string {
      return JSON.stringify({
        supported: root.hw.supported,
        writable: root.hw.writable,
        enabled: root.enabled,
        start: root.limits.start,
        end: root.limits.end,
        mode: root.mode,
        holding: root.holding,
        percent: root.percent,
        health: root.hw.health,
        hardware: { start: root.hw.start, end: root.hw.end, behaviour: root.hw.behaviour },
        error: root.lastError
      })
    }
    function enable(): void { root.setEnabled(true) }
    function disable(): void { root.setEnabled(false) }
    function toggle(): void { root.setEnabled(!root.enabled) }
    function setLimit(start: int, end: int): void { root.setLimits(start, end) }
    function topUp(): void { root.setMode("topUp") }
    function pause(): void { root.setMode("pause") }
    function discharge(): void { root.setMode("discharge") }
    function resume(): void { root.resume() }
  }
}
