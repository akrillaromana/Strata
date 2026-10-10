"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const structured = require("./structured_output.js");
const presets = require("./presets.js");
const jsonSettings = {format: "json_schema", schema_name: "answer", schema_text: JSON.stringify({
  type: "object", properties: {answer: {type: "string"}}, required: ["answer"], additionalProperties: false
})};
const sample = () => ({thinking: "high", temperature: .6, top_p: .95, top_k: 20, min_p: 0,
  repetition_penalty: 1, presence_penalty: 0, frequency_penalty: 0, penalty_last_n: 64,
  max: "", seed: "", stop: [], show: true, esp: false, mcp: true, ...structured.DEFAULT});

test("text requests do not include response_format", () => {
  assert.equal(structured.requestFormat(structured.DEFAULT), undefined);
  assert.equal(structured.responsesFormat(structured.DEFAULT), undefined);
});
test("JSON object requests map to both APIs", () => {
  const s = {...structured.DEFAULT, format: "json_object"};
  assert.deepEqual(structured.requestFormat(s), {type: "json_object"});
  assert.deepEqual(structured.responsesFormat(s), {type: "json_object"});
});
test("JSON Schema maps to OpenAI Chat and Responses formats", () => {
  const chat = structured.requestFormat(jsonSettings);
  assert.equal(chat.type, "json_schema");
  assert.equal(chat.json_schema.strict, true);
  assert.equal(chat.json_schema.schema.properties.answer.type, "string");
  assert.deepEqual(structured.responsesFormat(jsonSettings), {type: "json_schema", ...chat.json_schema});
});
test("reject malformed and oversized schema before sending", () => {
  const fails = ["", "[]", "null", "{}", '{"type":"array"}', '{"type":', "x".repeat(32769),
    JSON.stringify({type: "object", properties: {x: {$ref: "https://outside.example/x"}}}),
    JSON.stringify({type: "object", __proto__: null, properties: {x: JSON.parse('{"__proto__":{}}')}})];
  for (const schema_text of fails) {
    assert.throws(() => structured.requestFormat({...jsonSettings, schema_text}), undefined, schema_text.slice(0, 24));
  }
});
test("reject invalid field names and unexpected credentials", () => {
  for (const schema_name of ["", "hello world", "a".repeat(65), "bad\nname"]) {
    assert.throws(() => structured.requestFormat({...jsonSettings, schema_name}));
  }
  assert.throws(() => structured.requestFormat({...jsonSettings, api_key: "secret"}));
});
test("v2 presets upgrade to v3 retaining stop and adding text output", () => {
  const v2 = sample();
  for (const name of ["format", "schema_name", "schema_text"]) delete v2[name];
  v2.stop = ["<DONE>"];
  const migrated = presets.validate({format: presets.FORMAT, version: 2,
    presets: [{name: "Legacy v2", settings: v2}]});
  assert.equal(migrated.version, 3);
  assert.equal(migrated.presets[0].settings.format, "text");
  assert.deepEqual(migrated.presets[0].settings.stop, ["<DONE>"]);
});
test("v3 preset retains the schema without changing the active request", () => {
  const doc = presets.upsert(presets.empty(), "Schema", {...sample(), ...jsonSettings});
  const restored = presets.validate(JSON.parse(JSON.stringify(doc)));
  assert.deepEqual(restored, doc);
  const {format, schema_name, schema_text} = restored.presets[0].settings;
  assert.deepEqual(structured.requestFormat({format, schema_name, schema_text}),
    structured.requestFormat(jsonSettings));
  assert.throws(() => presets.upsert(doc, "Bad", {...sample(), format: "wrong"}));
  assert.throws(() => presets.upsert(doc, "Remote", {...sample(), format: "json_schema",
    schema_name: "remote", schema_text: '{"type":"object","$ref":"https://example.com/schema"}'}));
});
