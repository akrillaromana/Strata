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
  const ARCHIVE_FORMAT = "strata-chat-history";
  const MAX_ARCHIVE_BYTES = 32 * 1024 * 1024;

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

  // A portable archive contains conversation data only. It must not accidentally export
  // browser settings, API credentials, model paths or new fields added to the app later.
  // Conversations themselves may contain sensitive text/tool results: the UI warns on export.
  const MESSAGE_FIELDS = Object.freeze({
    time: "number", reasoning: "string", thinkSecs: "number", error: "string",
    meta: "string", stopped: "boolean", limit: "number"
  });
  const TOOL_FIELDS = Object.freeze({
    id: "string", name: "string", tool: "string", server: "string", state: "string",
    result: "string", at: "number", rat: "number", round: "number", ms: "number",
    chars: "number", ok: "boolean", truncated: "boolean", open: "boolean",
    skipped: "boolean"
  });
  function copyFields(input, spec) {
    const result = {};
    for (const [key, type] of Object.entries(spec)) {
      if (!Object.hasOwn(input, key)) continue;
      if (typeof input[key] !== type || (type === "number" && !Number.isFinite(input[key]))) {
        throw new Error(`Invalid archived field: ${key}`);
      }
      result[key] = input[key];
    }
    return result;
  }
  function archiveMessage(message) {
    if (!validMessage(message)) throw new Error("Invalid archived message");
    const result = {role: message.role, text: message.text, ...copyFields(message, MESSAGE_FIELDS)};
    if (message.images !== undefined) {
      if (!Array.isArray(message.images)) throw new Error("Invalid image attachments");
      result.images = message.images.map((im) => {
        if (!im || typeof im !== "object" || Array.isArray(im) ||
            typeof im.name !== "string" || (im.kind !== undefined && im.kind !== "image") ||
            (im.url !== undefined &&
            (typeof im.url !== "string" || !/^data:image\/(?:png|jpeg|gif|webp|avif);base64,[a-z\d+/=]+$/i.test(im.url)))) {
          throw new Error("Only embedded, safe image attachments can be archived");
        }
        return {kind: "image", name: im.name, ...(im.url === undefined ? {} : {url: im.url})};
      });
    }
    if (message.files !== undefined) {
      if (!Array.isArray(message.files)) throw new Error("Invalid text attachments");
      result.files = message.files.map((f) => {
        if (!f || typeof f !== "object" || Array.isArray(f) || typeof f.name !== "string" ||
            (f.kind !== undefined && f.kind !== "file") ||
            (f.text !== undefined && typeof f.text !== "string")) {
          throw new Error("Invalid archived text attachment");
        }
        return {kind: "file", name: f.name, ...(f.text === undefined ? {} : {text: f.text})};
      });
    }
    if (message.tools !== undefined) {
      if (!Array.isArray(message.tools)) throw new Error("Invalid archived tool calls");
      result.tools = message.tools.map((tool) => {
        if (!tool || typeof tool !== "object" || Array.isArray(tool)) throw new Error("Invalid tool call");
        const item = copyFields(tool, TOOL_FIELDS);
        if (Object.hasOwn(tool, "arguments")) {
          if (typeof tool.arguments !== "string" &&
              (!tool.arguments || typeof tool.arguments !== "object" || Array.isArray(tool.arguments))) {
            throw new Error("Invalid tool arguments");
          }
          item.arguments = typeof tool.arguments === "string" ? tool.arguments : copy(tool.arguments);
        }
        return item;
      });
    }
    return result;
  }
  function portable(state) {
    const clean = validate(state);
    return {version: VERSION, active: clean.active, chats: clean.chats.map((chat) => ({
      id: chat.id, title: chat.title, updated: chat.updated,
      messages: chat.messages.map(archiveMessage)
    }))};
  }
  function byteLength(text) { return new TextEncoder().encode(text).byteLength; }
  function exportArchive(state) {
    const doc = {format: ARCHIVE_FORMAT, version: VERSION, exportedAt: new Date().toISOString(),
                 state: portable(state)};
    const text = JSON.stringify(doc, null, 2);
    if (byteLength(text) > MAX_ARCHIVE_BYTES) throw new Error("Chat archive exceeds 32 MiB");
    return text;
  }
  function importArchive(text) {
    if (typeof text !== "string" || byteLength(text) > MAX_ARCHIVE_BYTES) {
      throw new Error("Invalid or oversized chat archive (32 MiB maximum)");
    }
    const doc = JSON.parse(text);
    if (!doc || typeof doc !== "object" || Array.isArray(doc) ||
        Object.keys(doc).sort().join(",") !== "exportedAt,format,state,version" ||
        doc.format !== ARCHIVE_FORMAT || doc.version !== VERSION ||
        typeof doc.exportedAt !== "string" || !Number.isFinite(Date.parse(doc.exportedAt))) {
      throw new Error("Unsupported chat archive format");
    }
    const state = validate(doc.state);
    if (Object.keys(state).sort().join(",") !== "active,chats,version") {
      throw new Error("Unknown chat storage fields");
    }
    // Reject unexpected archive-level fields, including hidden credentials. Tool arguments
    // and message text are intentionally preserved; the user must review exported chats.
    for (const chat of state.chats) {
      if (Object.keys(chat).sort().join(",") !== "id,messages,title,updated") {
        throw new Error("Unknown conversation fields");
      }
      for (const message of chat.messages) {
        const fields = new Set(["role", "text", "images", "files", "tools", ...Object.keys(MESSAGE_FIELDS)]);
        if (Object.keys(message).some((key) => !fields.has(key))) throw new Error("Unknown message fields");
        for (const image of message.images || []) {
          if (!image || Object.keys(image).some((key) => !["kind", "name", "url"].includes(key))) {
            throw new Error("Unknown image attachment fields");
          }
        }
        for (const file of message.files || []) {
          if (!file || Object.keys(file).some((key) => !["kind", "name", "text"].includes(key))) {
            throw new Error("Unknown text attachment fields");
          }
        }
        for (const tool of message.tools || []) {
          if (!tool || Object.keys(tool).some((key) => key !== "arguments" && !Object.hasOwn(TOOL_FIELDS, key))) {
            throw new Error("Unknown tool fields");
          }
        }
      }
    }
    return validate(portable(state));
  }
  return Object.freeze({VERSION, MAX_CHATS, MAX_ARCHIVE_BYTES, validate, init, active, update, create,
                        select, clear, removeChat, removeMessage, exportArchive, importArchive});
});
