// Run with: node --test serve/web/test_system_prompts.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const prompts = require("./system_prompts.js");
const make = (enabled = true, priority = "system", text = "Be concise") => ({enabled, priority, text});

test("no active system instructions by default", () => {
  assert.deepEqual(prompts.inactive(), make(false, "system", ""));
  const chat = [{role: "user", content: "hi"}];
  assert.deepEqual(prompts.toMessages(chat, prompts.inactive()), chat);
  assert.notStrictEqual(prompts.toMessages(chat, prompts.inactive()), chat);
});
test("system priority prepends a system role without mutating chat", () => {
  const chat = [{role: "user", content: "hello"}];
  assert.deepEqual(prompts.toMessages(chat, make()), [
    {role: "system", content: "Be concise"}, ...chat]);
  assert.equal(chat.length, 1);
});
test("user priority produces an ordinary user message before chat", () => {
  const chat = [{role: "user", content: "hi"}];
  assert.deepEqual(prompts.toMessages(chat, make(true, "user")), [
    {role: "user", content: "Be concise"}, ...chat]);
});
test("validate active state including required text", () => {
  for (const bad of [make(true, "system", " "), make(true, "developer"),
    make(true, "system", "x".repeat(32769)), make(true, "system", "x\0"),
    {enabled: "false", priority: "system", text: "hi"}, {...make(), api_key: "SECRET"}]) {
    assert.throws(() => prompts.stateOf(bad));
  }
  assert.deepEqual(prompts.stateOf(make(false, "system", "")), make(false, "system", ""));
});
test("named templates can be saved, replaced, and deleted", () => {
  const first = prompts.upsert(prompts.empty(), " Task ", make());
  assert.equal(first.presets[0].name, "Task");
  const next = prompts.upsert(first, "TASK", make(true, "user", "Careful"));
  assert.equal(next.presets.length, 1);
  assert.equal(next.presets[0].settings.text, "Careful");
  assert.equal(first.presets[0].settings.text, "Be concise");
  assert.deepEqual(prompts.remove(next, "task"), prompts.empty());
});
test("template document survives export/import round trip", () => {
  const doc = prompts.upsert(prompts.empty(), "Режим", make(true, "system", "Точно."));
  assert.deepEqual(prompts.validate(JSON.parse(JSON.stringify(doc))), doc);
});
test("reject malformed templates and secret-bearing extra fields", () => {
  const good = prompts.upsert(prompts.empty(), "Safe", make());
  for (const bad of [null, [], {...good, api_key: "SECRET"},
    {...good, version: 2}, {...good, presets: [{name: "X", settings: {...make(), token: "SECRET"}}]},
    {...good, presets: [...good.presets, ...good.presets]},
    JSON.parse('{"format":"strata-system-prompts","version":1,"presets":[],"__proto__":{"polluted":true}}')]) {
    assert.throws(() => prompts.validate(bad));
  }
  assert.equal({}.polluted, undefined);
});
test("bounds on count and cumulative text", () => {
  let doc = prompts.empty();
  for (let i = 0; i < 50; i++) doc = prompts.upsert(doc, `Template ${i}`, make());
  assert.throws(() => prompts.upsert(doc, "51", make()));
  let huge = prompts.empty();
  for (let i = 0; i < 5; i++) {
    if (i < 4) huge = prompts.upsert(huge, `Large ${i}`, make(true, "system", "x".repeat(32768)));
    else assert.throws(() => prompts.upsert(huge, "Too large", make(true, "system", "x")));
  }
});
test("names reject duplicates and control characters", () => {
  assert.throws(() => prompts.upsert(prompts.empty(), "bad\nname", make()));
  assert.throws(() => prompts.upsert(prompts.empty(), "x".repeat(61), make()));
  const doc = prompts.upsert(prompts.empty(), "abc", make());
  assert.throws(() => prompts.validate({...doc, presets: [...doc.presets,
    {name: "ABC", settings: make()}]}));
});
