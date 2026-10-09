// Browser-local conversation management. No server history, credentials or model paths.
// Pure functions: the web page owns persistence and must write before switching its active state.
(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.StrataChats = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";
  const VERSION = 1;
  const MAX_CHATS = 100;
  const MAX_TITLE = 100;

  function copy(value) { return JSON.parse(JSON.stringify(value)); }
  function validMessage(value) {
    return value && typeof value === "object" && !Array.isArray(value) &&
      (value.role === "user" || value.role === "assistant") && typeof value.text === "string";
  }
  function validate(state) {
    if (!state || typeof state !== "object" || Array.isArray(state) || state.version !== VERSION ||
        !Array.isArray(state.chats) || state.chats.length < 1 || state.chats.length > MAX_CHATS ||
        typeof state.active !== "string") throw new Error("Invalid chat storage format");
    const ids = new Set();
    for (const chat of state.chats) {
      if (!chat || typeof chat !== "object" || typeof chat.id !== "string" || !chat.id ||
          typeof chat.title !== "string" || chat.title.length > MAX_TITLE ||
          !Number.isFinite(chat.updated) || !Array.isArray(chat.messages) ||
          !chat.messages.every(validMessage) || ids.has(chat.id)) {
        throw new Error("Invalid conversation entry");
      }
      ids.add(chat.id);
    }
    if (!ids.has(state.active)) throw new Error("Active conversation not found");
    return copy(state);
  }
  function makeId() {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
    return `chat-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
  function titleOf(messages) {
    const first = messages.find((m) => m.role === "user" && m.text.trim());
    if (!first) return "New chat";
    return first.text.trim().replace(/\s+/g, " ").slice(0, MAX_TITLE);
  }
  function makeChat(messages = [], id = makeId(), now = Date.now()) {
    if (!Array.isArray(messages) || !messages.every(validMessage)) throw new Error("Invalid messages");
    return {id, title: titleOf(messages), updated: now, messages: copy(messages)};
  }
  function init(saved, legacy = []) {
    if (saved !== null && saved !== undefined) return validate(saved);
    const messages = Array.isArray(legacy) && legacy.every(validMessage) ? legacy : [];
    const chat = makeChat(messages);
    return {version: VERSION, active: chat.id, chats: [chat]};
  }
  function active(state) {
    const clean = validate(state);
    return clean.chats.find((c) => c.id === clean.active);
  }
  function update(state, messages) {
    const clean = validate(state);
    if (!Array.isArray(messages) || !messages.every(validMessage)) throw new Error("Invalid messages");
    const chat = clean.chats.find((c) => c.id === clean.active);
    chat.messages = copy(messages);
    chat.title = titleOf(messages);
    chat.updated = Date.now();
    return clean;
  }
  function create(state, id = makeId()) {
    const clean = validate(state);
    if (clean.chats.some((c) => c.id === id)) throw new Error("Duplicate conversation ID");
    if (clean.chats.length >= MAX_CHATS) throw new Error("Maximum 100 conversations reached");
    clean.chats.push(makeChat([], id));
    clean.active = id;
    return clean;
  }
  function select(state, id) {
    const clean = validate(state);
    if (!clean.chats.some((c) => c.id === id)) throw new Error("Conversation not found");
    clean.active = id;
    return clean;
  }
  function clear(state) { return update(state, []); }
  function removeChat(state, id) {
    const clean = validate(state);
    const index = clean.chats.findIndex((c) => c.id === id);
    if (index < 0) throw new Error("Conversation not found");
    clean.chats.splice(index, 1);
    if (!clean.chats.length) {
      const fresh = makeChat();
      clean.chats.push(fresh);
    }
    if (clean.active === id) clean.active = clean.chats[Math.max(0, index - 1)].id;
    return clean;
  }
  function removeMessage(state, index, withAnswer = false) {
    const clean = validate(state);
    const chat = clean.chats.find((c) => c.id === clean.active);
    if (!Number.isInteger(index) || index < 0 || index >= chat.messages.length) {
      throw new Error("Message index out of bounds");
    }
    let count = 1;
    if (withAnswer && chat.messages[index].role === "user") {
      for (let j = index + 1; j < chat.messages.length && chat.messages[j].role !== "user"; ++j) ++count;
    }
    chat.messages.splice(index, count);
    chat.title = titleOf(chat.messages);
    chat.updated = Date.now();
    return clean;
  }
  return Object.freeze({VERSION, MAX_CHATS, validate, init, active, update, create, select, clear, removeChat, removeMessage});
});
