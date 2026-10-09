"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const chats = require("./chat_sessions.js");

const user = (text) => ({role: "user", text, time: 123});
const answer = (text) => ({role: "assistant", text, time: 124, reasoning: "internal"});
const legacy = [user("First old question"), answer("First answer")];

test("migrates an existing single chat without modifying its messages", () => {
  const old = structuredClone(legacy);
  const state = chats.init(null, old);
  assert.deepEqual(chats.active(state).messages, old);
  assert.equal(chats.active(state).title, "First old question");
  old[0].text = "modified";
  assert.equal(chats.active(state).messages[0].text, "First old question");
});

test("starting a new chat preserves the old one and keeps both selectable", () => {
  let state = chats.init(null, legacy);
  const original = state.active;
  state = chats.create(state, "new-chat");
  assert.equal(state.chats.length, 2);
  assert.equal(chats.active(state).messages.length, 0);
  state = chats.update(state, [user("Second conversation")]);
  assert.equal(chats.active(state).title, "Second conversation");
  state = chats.select(state, original);
  assert.deepEqual(chats.active(state).messages, legacy);
});

test("clearing one chat never empties other conversations", () => {
  let state = chats.init(null, legacy);
  const original = state.active;
  state = chats.create(state, "second");
  state = chats.update(state, [user("Keep")]);
  state = chats.select(state, original);
  state = chats.clear(state);
  assert.equal(chats.active(state).messages.length, 0);
  state = chats.select(state, "second");
  assert.equal(chats.active(state).messages[0].text, "Keep");
});

test("delete one answer independently", () => {
  let state = chats.init(null, [user("question"), answer("answer")]);
  state = chats.removeMessage(state, 1);
  assert.deepEqual(chats.active(state).messages.map((m) => m.role), ["user"]);
});

test("delete user message plus contiguous responses but not the next turn", () => {
  let state = chats.init(null, [user("A"), answer("A1"), answer("A2"), user("B"), answer("B1")]);
  state = chats.removeMessage(state, 0, true);
  assert.deepEqual(chats.active(state).messages.map((m) => m.text), ["B", "B1"]);
});

test("delete only user message leaves answer if explicitly chosen", () => {
  let state = chats.init(null, legacy);
  state = chats.removeMessage(state, 0, false);
  assert.equal(chats.active(state).messages[0].role, "assistant");
});

test("deleting active chat chooses an existing chat", () => {
  let state = chats.init(null, legacy);
  const first = state.active;
  state = chats.create(state, "new");
  state = chats.removeChat(state, "new");
  assert.equal(state.active, first);
  assert.equal(state.chats.length, 1);
});

test("deleting the last chat creates a clean new chat", () => {
  let state = chats.init(null, legacy);
  state = chats.removeChat(state, state.active);
  assert.equal(state.chats.length, 1);
  assert.equal(chats.active(state).messages.length, 0);
  assert.equal(chats.active(state).title, "New chat");
});

test("invalid selection or deletion never mutates the original state", () => {
  const state = chats.init(null, legacy);
  const prior = structuredClone(state);
  assert.throws(() => chats.select(state, "missing"));
  assert.throws(() => chats.removeMessage(state, -1));
  assert.throws(() => chats.removeMessage(state, 3000));
  assert.throws(() => chats.removeChat(state, "missing"));
  assert.deepEqual(state, prior);
});

test("duplicate identifiers are rejected", () => {
  const state = chats.init(null, []);
  assert.throws(() => chats.create(state, state.active));
});

test("a malformed persisted document is rejected without overwriting it", () => {
  assert.throws(() => chats.init({version: 99, chats: [], active: "x"}));
  assert.throws(() => chats.init({version: 1, chats: [{id: "x", title: "ok", updated: 0,
    messages: [{role: "system", text: "secret"}]}], active: "x"}));
});

test("conversation titles are bounded and whitespace normalized", () => {
  const state = chats.init(null, [user("a  \n  b" + "x".repeat(200))]);
  assert.equal(chats.active(state).title.length, 100);
  assert.equal(chats.active(state).title.slice(0, 3), "a b");
});

test("limits conversation count and retains existing data on failure", () => {
  let state = chats.init(null, []);
  for (let i = 1; i < 100; ++i) state = chats.create(state, `chat-${i}`);
  assert.equal(state.chats.length, 100);
  assert.throws(() => chats.create(state, "overflow"));
  assert.equal(state.chats.length, 100);
});

test("JSON round-trip retains active selection and messages", () => {
  let state = chats.init(null, legacy);
  state = chats.create(state, "target");
  state = chats.update(state, [user("Retained")]);
  assert.deepEqual(chats.init(JSON.parse(JSON.stringify(state))), state);
});
