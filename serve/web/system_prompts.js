// Browser-local system instructions and named templates. This module is DOM-free and tested with Node.
"use strict";
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.StrataSystemPrompts = api;
})(typeof window !== "undefined" ? window : null, function () {
  const FORMAT = "strata-system-prompts";
  const VERSION = 1;
  const LIMIT = 50;
  const TEXT_LIMIT = 32768;
  const TOTAL_LIMIT = 131072;

  function isRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) &&
      (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
  }
  function onlyKeys(value, expected, what) {
    if (!isRecord(value) || Object.keys(value).length !== expected.length ||
        Object.keys(value).some((key) => !expected.includes(key))) {
      throw new Error(what + ": missing or unrecognized fields");
    }
  }
  function nameOf(value) {
    if (typeof value !== "string") throw new Error("Name must be text");
    const result = value.trim().normalize("NFC");
    if (!result || result.length > 60 || /[\u0000-\u001f\u007f]/.test(result)) {
      throw new Error("Name must be 1–60 characters with no control characters");
    }
    return result;
  }
  function stateOf(value) {
    onlyKeys(value, ["enabled", "priority", "text"], "System instruction");
    if (typeof value.enabled !== "boolean" || !["system", "user"].includes(value.priority) ||
        typeof value.text !== "string" || value.text.length > TEXT_LIMIT || value.text.includes("\0")) {
      throw new Error("Invalid system instruction (text limit: 32768 characters)");
    }
    if (value.enabled && !value.text.trim()) throw new Error("Enabled instruction must contain text");
    return {enabled: value.enabled, priority: value.priority, text: value.text};
  }
  function inactive() { return {enabled: false, priority: "system", text: ""}; }
  function empty() { return {format: FORMAT, version: VERSION, presets: []}; }
  function validate(input) {
    onlyKeys(input, ["format", "version", "presets"], "System prompt document");
    if (input.format !== FORMAT || input.version !== VERSION || !Array.isArray(input.presets) ||
        input.presets.length > LIMIT) throw new Error("Unsupported system prompt document");
    const seen = new Set();
    let total = 0;
    const presets = input.presets.map((preset) => {
      onlyKeys(preset, ["name", "settings"], "System prompt template");
      const name = nameOf(preset.name);
      const key = name.toLocaleLowerCase();
      if (seen.has(key)) throw new Error("Duplicate template name: " + name);
      seen.add(key);
      const settings = stateOf(preset.settings);
      total += settings.text.length;
      if (total > TOTAL_LIMIT) throw new Error("Stored instructions exceed 131072 characters in total");
      return {name, settings};
    });
    return {format: FORMAT, version: VERSION, presets};
  }
  function upsert(doc, title, settings) {
    const checked = validate(doc);
    const name = nameOf(title);
    const item = {name, settings: stateOf(settings)};
    const idx = checked.presets.findIndex((p) => p.name.toLocaleLowerCase() === name.toLocaleLowerCase());
    if (idx >= 0) checked.presets[idx] = item;
    else {
      if (checked.presets.length === LIMIT) throw new Error("Maximum of 50 templates reached");
      checked.presets.push(item);
    }
    checked.presets.sort((a, b) => a.name.localeCompare(b.name));
    return validate(checked);
  }
  function remove(doc, title) {
    const checked = validate(doc);
    const name = nameOf(title).toLocaleLowerCase();
    const presets = checked.presets.filter((item) => item.name.toLocaleLowerCase() !== name);
    if (presets.length === checked.presets.length) throw new Error("Template not found");
    return validate({...checked, presets});
  }
  function toMessages(original, state) {
    const checked = stateOf(state);
    if (!Array.isArray(original)) throw new Error("Messages must be an array");
    if (!checked.enabled) return [...original];
    // 'system' has template-level priority; 'user' is a normal message before the conversation.
    // Never change history or add the instruction to chat storage.
    return [{role: checked.priority, content: checked.text}, ...original];
  }
  return Object.freeze({FORMAT, VERSION, LIMIT, TEXT_LIMIT, inactive, empty, validate,
                        stateOf, upsert, remove, toMessages});
});
