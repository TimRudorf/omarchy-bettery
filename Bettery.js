// Charge-care policy for the Bettery plugin, kept free of QML so it can be
// tested with node.
//
// Modes:
//   normal     the configured limit (or the hardware default when it is off)
//   topUp      charge to 100% once; ends when the charger is unplugged
//   pause      hold the charge where it is (charge_behaviour inhibit-charge)
//   discharge  run from the battery while plugged in until it reaches the limit

var MIN_END = 50
var MAX_END = 100
var MIN_START = 40
var DEFAULT_START = 75
var DEFAULT_END = 80

function toInt(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? Math.round(n) : fallback
}

function parseStatus(raw) {
  var fields = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    fields[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  var behaviours = fields.behaviours ? fields.behaviours.split(/\s+/) : []
  return {
    known: fields.supported !== undefined,
    supported: fields.supported === "1",
    battery: fields.battery || "",
    writable: fields.writable === "1",
    hasStart: fields.start !== undefined,
    start: toInt(fields.start, -1),
    end: toInt(fields.end, -1),
    canPause: behaviours.indexOf("inhibit-charge") !== -1,
    canDischarge: behaviours.indexOf("force-discharge") !== -1,
    behaviour: fields.behaviour || "",
    health: fields.health !== undefined ? toInt(fields.health, -1) : -1,
    capacity: toInt(fields.capacity, -1),
    status: fields.status || "",
    errorCode: toInt(fields.errorCode, 0),
    error: fields.error || ""
  }
}

// Keeps a configured pair inside what the hardware and the battery accept:
// the end between 50 and 100, the start below the end and not under 40.
function clampLimits(start, end) {
  var e = Math.max(MIN_END, Math.min(MAX_END, toInt(end, DEFAULT_END)))
  var s = Math.max(MIN_START, Math.min(e - 1, toInt(start, DEFAULT_START)))
  return { start: s, end: e }
}

// Moving one handle pushes the other along so the pair stays valid.
function withEnd(limits, end) {
  var e = clampLimits(MIN_START, end).end
  var s = Math.min(limits.start, e - 1)
  return clampLimits(s, e)
}

function withStart(limits, start) {
  var s = Math.max(MIN_START, Math.min(MAX_END - 1, toInt(start, DEFAULT_START)))
  var e = Math.max(limits.end, s + 1)
  return clampLimits(s, e)
}

// What the hardware should be told now, and which mode follows.
// config: { enabled, start, end }; hw: parseStatus(); percent: 0..100.
function plan(config, mode, hw, percent, onBattery) {
  var limits = clampLimits(config.start, config.end)
  var next = mode || "normal"

  if (next === "topUp" && onBattery) next = "normal"
  if (next === "pause" && (!hw.canPause || onBattery)) next = "normal"
  if (next === "discharge") {
    if (!hw.canDischarge || !config.enabled || onBattery || percent <= limits.end) next = "normal"
  }

  var start, end
  if (next === "topUp" || !config.enabled) {
    start = 0
    end = 100
  } else {
    start = limits.start
    end = limits.end
  }

  var behaviour = "auto"
  if (next === "pause") behaviour = "inhibit-charge"
  else if (next === "discharge") behaviour = "force-discharge"

  return {
    mode: next,
    start: hw.hasStart ? start : -1,
    end: end,
    behaviour: hw.canPause || hw.canDischarge ? behaviour : ""
  }
}

function needsApply(target, hw) {
  if (!hw.supported) return false
  if (target.end !== hw.end) return true
  if (target.start >= 0 && target.start !== hw.start) return true
  if (target.behaviour !== "" && target.behaviour !== hw.behaviour) return true
  return false
}

function applyArgs(target) {
  return [
    target.start >= 0 ? String(target.start) : "-",
    String(target.end),
    target.behaviour !== "" ? target.behaviour : "-"
  ]
}

// The battery is held at the limit: plugged in, limit on, and at or above
// where charging resumes without charging.
function holding(config, mode, hw, percent, onBattery, charging) {
  if (onBattery || !config.enabled || mode !== "normal" || charging) return false
  var limits = clampLimits(config.start, config.end)
  return percent >= (hw.hasStart ? limits.start : limits.end - 5)
}

function modeIcon(mode) {
  if (mode === "pause") return "󱞜"
  if (mode === "discharge") return "󱟞"
  if (mode === "topUp") return "󱟠"
  return ""
}

// The plain level glyph, without the charging bolt, for a battery held at its limit.
function levelIcon(fraction) {
  var icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  return icons[Math.max(0, Math.min(9, Math.floor(Number(fraction || 0) * 10)))]
}

function rangeLabel(config, hw) {
  var limits = clampLimits(config.start, config.end)
  return hw.hasStart ? limits.start + "-" + limits.end + "%" : limits.end + "%"
}

if (typeof module !== "undefined") {
  module.exports = {
    MIN_END: MIN_END,
    MAX_END: MAX_END,
    MIN_START: MIN_START,
    DEFAULT_START: DEFAULT_START,
    DEFAULT_END: DEFAULT_END,
    parseStatus: parseStatus,
    clampLimits: clampLimits,
    withEnd: withEnd,
    withStart: withStart,
    plan: plan,
    needsApply: needsApply,
    applyArgs: applyArgs,
    holding: holding,
    modeIcon: modeIcon,
    levelIcon: levelIcon,
    rangeLabel: rangeLabel
  }
}
