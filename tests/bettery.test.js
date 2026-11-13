const test = require("node:test")
const assert = require("node:assert")
const S = require("../Bettery.js")

const thinkpad = S.parseStatus("supported\t1\nbattery\tBAT0\nwritable\t1\nend\t80\nstart\t75\nbehaviours\tauto inhibit-charge force-discharge\nbehaviour\tauto\nhealth\t87\n")
const endOnly = S.parseStatus("supported\t1\nbattery\tBAT1\nwritable\t1\nend\t80\n")
const on = { enabled: true, start: 75, end: 80 }

test("parseStatus reads capabilities", () => {
  assert.equal(thinkpad.hasStart, true)
  assert.equal(thinkpad.canPause, true)
  assert.equal(thinkpad.canDischarge, true)
  assert.equal(thinkpad.health, 87)
  assert.equal(endOnly.hasStart, false)
  assert.equal(endOnly.canPause, false)
  assert.equal(S.parseStatus("supported\t0\n").supported, false)
  assert.equal(S.parseStatus("").known, false)
})

test("clampLimits keeps a valid pair", () => {
  assert.deepEqual(S.clampLimits(75, 80), { start: 75, end: 80 })
  assert.deepEqual(S.clampLimits(90, 80), { start: 79, end: 80 })
  assert.deepEqual(S.clampLimits(10, 30), { start: 40, end: 50 })
  assert.deepEqual(S.clampLimits("x", "y"), { start: 75, end: 80 })
  assert.deepEqual(S.clampLimits(99, 120), { start: 99, end: 100 })
})

test("moving one handle pushes the other", () => {
  assert.deepEqual(S.withEnd({ start: 75, end: 80 }, 70), { start: 69, end: 70 })
  assert.deepEqual(S.withStart({ start: 75, end: 80 }, 85), { start: 85, end: 86 })
  assert.deepEqual(S.withStart({ start: 75, end: 80 }, 20), { start: 40, end: 80 })
})

test("normal mode applies the limit, off restores the default", () => {
  assert.deepEqual(S.plan(on, "normal", thinkpad, 60, false), { mode: "normal", start: 75, end: 80, behaviour: "auto" })
  assert.deepEqual(S.plan({ enabled: false, start: 75, end: 80 }, "normal", thinkpad, 60, false), { mode: "normal", start: 0, end: 100, behaviour: "auto" })
  assert.deepEqual(S.plan(on, "normal", endOnly, 60, false), { mode: "normal", start: -1, end: 80, behaviour: "" })
})

test("top up charges to 100 and ends on unplug", () => {
  assert.deepEqual(S.plan(on, "topUp", thinkpad, 80, false), { mode: "topUp", start: 0, end: 100, behaviour: "auto" })
  assert.equal(S.plan(on, "topUp", thinkpad, 100, true).mode, "normal")
})

test("pause inhibits charging and needs support", () => {
  assert.equal(S.plan(on, "pause", thinkpad, 60, false).behaviour, "inhibit-charge")
  assert.equal(S.plan(on, "pause", endOnly, 60, false).mode, "normal")
  assert.equal(S.plan(on, "pause", thinkpad, 60, true).mode, "normal")
})

test("discharge runs down to the limit, then stops", () => {
  assert.deepEqual(S.plan(on, "discharge", thinkpad, 95, false), { mode: "discharge", start: 75, end: 80, behaviour: "force-discharge" })
  assert.equal(S.plan(on, "discharge", thinkpad, 80, false).mode, "normal")
  assert.equal(S.plan(on, "discharge", thinkpad, 80, false).behaviour, "auto")
  assert.equal(S.plan(on, "discharge", thinkpad, 95, true).mode, "normal")
  assert.equal(S.plan({ enabled: false, start: 75, end: 80 }, "discharge", thinkpad, 95, false).mode, "normal")
})

test("needsApply compares with the hardware", () => {
  assert.equal(S.needsApply(S.plan(on, "normal", thinkpad, 60, false), thinkpad), false)
  assert.equal(S.needsApply(S.plan(on, "pause", thinkpad, 60, false), thinkpad), true)
  assert.equal(S.needsApply(S.plan({ enabled: true, start: 60, end: 80 }, "normal", thinkpad, 60, false), thinkpad), true)
  assert.deepEqual(S.applyArgs({ start: -1, end: 80, behaviour: "" }), ["-", "80", "-"])
})

test("holding means plugged in, limit on, no charge flowing", () => {
  assert.equal(S.holding(on, "normal", thinkpad, 78, false, false), true)
  assert.equal(S.holding(on, "normal", thinkpad, 70, false, false), false)
  assert.equal(S.holding(on, "normal", thinkpad, 78, false, true), false)
  assert.equal(S.holding(on, "normal", thinkpad, 78, true, false), false)
  assert.equal(S.holding(on, "pause", thinkpad, 78, false, false), false)
})

test("levelIcon follows the charge", () => {
  assert.equal(S.levelIcon(0.85), "󰂂")
  assert.equal(S.levelIcon(1), "󰁹")
  assert.equal(S.levelIcon(0.05), "󰁺")
})
