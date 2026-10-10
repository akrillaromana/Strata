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

// Iteration 007: portable history and attachment-preserving local storage.
test("portable archive contains all conversations, chosen chat and text attachments", () => {
  let state = chats.init(null, [user("A")]);
  const first = state.active;
  state = chats.create(state, "second");
  state = chats.update(state, [{role: "user", text: "With file", time: 125,
    files: [{kind: "file", name: "note.txt", text: "actual attached content"}]}]);
  const restored = chats.importArchive(chats.exportArchive(state));
  assert.deepEqual(restored, state);
  assert.equal(restored.active, "second");
  assert.equal(restored.chats.find((c) => c.id === first).messages[0].text, "A");
  assert.equal(chats.active(restored).messages[0].files[0].text, "actual attached content");
});

test("portable archive keeps full embedded raster images", () => {
  const url = "data:image/png;base64,iVBORw0KGgo=";
  const state = chats.init(null, [{role: "user", text: "image", images: [
    {kind: "image", name: "p.png", url}
  ]}]);
  assert.equal(chats.active(chats.importArchive(chats.exportArchive(state)))
    .messages[0].images[0].url, url);
});

test("portable archive retains reasoning, output metadata and tool results", () => {
  const m = {role: "assistant", text: "Result", time: 100, reasoning: "steps", thinkSecs: 1.2,
    meta: "24 tokens", stopped: false, tools: [{id: "call1", name: "file_read", tool: "read",
      state: "done", round: 1, arguments: {path: "sample.txt"}, result: "data", ok: true,
      at: 0, ms: 42}]};
  const state = chats.init(null, [user("Request"), m]);
  const imported = chats.importArchive(chats.exportArchive(state));
  assert.deepEqual(chats.active(imported).messages[1], m);
});

test("portable archive never includes unrelated browser settings or arbitrary message fields", () => {
  const m = {...user("Question"), apiKey: "should-not-export"};
  const state = chats.init(null, [m]);
  state.modelPath = "private-model-folder";
  state.chats[0].privatePassword = "password";
  const exported = chats.exportArchive(state);
  assert.doesNotMatch(exported, /should-not-export|private-model-folder|privatePassword|password/);
  assert.equal(chats.importArchive(exported).chats[0].messages[0].text, "Question");
});

test("malformed and future archives are rejected", () => {
  const state = chats.init(null, [user("Unchanged")]);
  const baseline = structuredClone(state);
  const archive = JSON.parse(chats.exportArchive(state));
  for (const bad of [
    {...archive, version: 2},
    {...archive, format: "strata-sampling-presets"},
    {...archive, api_key: "secret"},
    {...archive, state: {...archive.state, api_key: "secret"}},
    {...archive, state: {...archive.state, active: "nonexistent"}},
  ]) assert.throws(() => chats.importArchive(JSON.stringify(bad)));
  assert.throws(() => chats.importArchive("not-json"));
  assert.deepEqual(state, baseline);
});

test("import rejects injected chat, message, tool or attachment properties", () => {
  const state = chats.init(null, [user("A")]);
  const doc = JSON.parse(chats.exportArchive(state));
  const tamper = (edit) => {
    const clone = structuredClone(doc);
    edit(clone.state.chats[0].messages[0], clone.state.chats[0]);
    assert.throws(() => chats.importArchive(JSON.stringify(clone)));
  };
  tamper((msg, chat) => { chat.admin = true; });
  tamper((msg) => { msg.api_key = "secret"; });
  tamper((msg) => { msg.images = [{kind: "image", name: "bad.svg", url: "javascript:alert(1)"}]; });
  tamper((msg) => { msg.images = [{kind: "image", name: "bad.svg", url: "https://tracker.invalid/a"}]; });
  tamper((msg) => { msg.files = [{kind: "file", name: "a", text: "x", password: "secret"}]; });
  tamper((msg) => { msg.tools = [{state: "done", unexpected: "secret"}]; });
});

test("archive enforces the portable size ceiling", () => {
  const state = chats.init(null, [user("x".repeat(chats.MAX_ARCHIVE_BYTES))]);
  assert.throws(() => chats.exportArchive(state), /32 MiB/);
  assert.throws(() => chats.importArchive("x".repeat(chats.MAX_ARCHIVE_BYTES + 1)), /32 MiB/);
});
