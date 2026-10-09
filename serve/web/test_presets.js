// Run: node --test serve/web/test_presets.js
// Pure validation tests. A real-browser interaction test is documented in docs/reports/iteration-003.
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const presets = require("./presets.js");

function sample() {
  return {thinking: "high", temperature: 0.6, top_p: 0.95, top_k: 20, min_p: 0,
    repetition_penalty: 1, presence_penalty: 0, frequency_penalty: 0, penalty_last_n: 64,
    max: "", seed: "", show: true, esp: false, mcp: true};
}
function one(name = "Work", settings = sample()) {
  return presets.upsert(presets.empty(), name, settings);
}

test("empty document has explicit portable schema", () => {
  assert.deepEqual(presets.empty(), {format: "strata-sampling-presets", version: 1, presets: []});
  assert.deepEqual(presets.validate(presets.empty()), presets.empty());
});
test("round trip preserves every supported field", () => {
  const input = one("Quality", {...sample(), temperature: 0, thinking: "none", seed: "1234", max: "1024"});
  assert.deepEqual(presets.validate(JSON.parse(JSON.stringify(input))), input);
  assert.deepEqual(input.presets[0].settings.seed, "1234");
});
test("update is case insensitive and never creates duplicate presets", () => {
  const original = one("Quality");
  const updated = presets.upsert(original, "QUALITY", {...sample(), top_k: 64});
  assert.equal(updated.presets.length, 1);
  assert.equal(updated.presets[0].settings.top_k, 64);
  assert.equal(original.presets[0].settings.top_k, 20);
});
test("remove only the named preset", () => {
  const doc = presets.upsert(one("A"), "B", sample());
  assert.deepEqual(presets.remove(doc, "a").presets.map((p) => p.name), ["B"]);
  assert.equal(doc.presets.length, 2);
  assert.throws(() => presets.remove(doc, "missing"), /not found/);
});
test("reject unknown fields containing credentials at any depth", () => {
  assert.throws(() => presets.validate({...one(), api_key: "secret"}), /unexpected/);
  assert.throws(() => presets.validate({...one(), presets: [{name: "A", settings: {...sample(), api_key: "secret"}}]}), /unexpected/);
  assert.throws(() => presets.validate({...one(), presets: [{name: "A", settings: sample(), token: "secret"}]}), /unexpected/);
});
test("reject corrupt and future schema versions", () => {
  for (const bad of [null, [], {}, {format: "another", version: 1, presets: []},
    {format: presets.FORMAT, version: 2, presets: []},
    {format: presets.FORMAT, version: 1, presets: "a"}]) {
    assert.throws(() => presets.validate(bad));
  }
});
test("reject non-JSON numerical values", () => {
  for (const value of [NaN, Infinity, -Infinity, "0.1", null]) {
    assert.throws(() => presets.settingsOf({...sample(), temperature: value}));
  }
});
test("numeric bounds are enforced, including integral controls", () => {
  for (const [key, value] of [["temperature", -1], ["temperature", 3], ["top_p", 0],
    ["top_k", 0], ["top_k", 65], ["top_k", 2.5], ["min_p", 1.01],
    ["repetition_penalty", 0], ["presence_penalty", -1], ["frequency_penalty", 3],
    ["penalty_last_n", 0], ["penalty_last_n", 4097]]) {
    assert.throws(() => presets.settingsOf({...sample(), [key]: value}), undefined, `${key}=${value}`);
  }
});
test("optional integer inputs reject unsafe values", () => {
  for (const val of [-1, 0, "0", "-1", "1.2", " 4", "3 ", 2147483648, "1e5", {}, null]) {
    assert.throws(() => presets.settingsOf({...sample(), seed: val}));
    assert.throws(() => presets.settingsOf({...sample(), max: val}));
  }
  assert.equal(presets.settingsOf({...sample(), seed: 123}).seed, "123");
});
test("reject invalid thinking or switch types", () => {
  assert.throws(() => presets.settingsOf({...sample(), thinking: "xhigh"}));
  assert.throws(() => presets.settingsOf({...sample(), mcp: "true"}));
});
test("reject missing settings values", () => {
  const s = sample(); delete s.top_k;
  assert.throws(() => presets.settingsOf(s), /missing/);
});
test("names are trimmed and validated", () => {
  assert.equal(one("  Quality  ").presets[0].name, "Quality");
  for (const name of ["", "  ", "x".repeat(61), "bad\nname", 18]) {
    assert.throws(() => one(name));
  }
});
test("names reject duplicates ignoring case", () => {
  const doc = one("Clean");
  assert.throws(() => presets.validate({...doc, presets: [...doc.presets,
    {name: "CLEAN", settings: sample()}]}), /Duplicate/);
});
test("max 50 presets without corrupting input", () => {
  let doc = presets.empty();
  for (let i = 1; i <= 50; i++) doc = presets.upsert(doc, `Profile ${i}`, sample());
  assert.equal(doc.presets.length, 50);
  assert.throws(() => presets.upsert(doc, "Profile 51", sample()), /Maximum/);
  assert.equal(doc.presets.length, 50);
});
test("prototype-pollution shaped JSON keys are rejected", () => {
  const payload = JSON.parse('{"format":"strata-sampling-presets","version":1,"presets":[],"__proto__":{"polluted":true}}');
  assert.throws(() => presets.validate(payload), /unexpected/);
  assert.equal({}.polluted, undefined);
});
test("settings are independent copies", () => {
  const original = sample();
  const doc = one("One", original);
  original.temperature = 0;
  assert.equal(doc.presets[0].settings.temperature, 0.6);
  doc.presets[0].settings.temperature = 1;
  assert.equal(original.temperature, 0);
});
