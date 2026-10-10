// Portable, browser-local sampling presets. No credentials, server state, or model paths are serialized.
// The small, DOM-free module is also directly testable with Node.js.
"use strict";
(function (root, make) {
  const api = make();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.StrataPresets = api;
})(typeof window !== "undefined" ? window : null, function () {
  const FORMAT = "strata-sampling-presets";
  const VERSION = 3;
  const MAX_PRESETS = 50;
  const MAX_NAME = 60;
  const LEGACY_FIELDS = [
    "thinking", "temperature", "top_p", "top_k", "min_p", "repetition_penalty",
    "presence_penalty", "frequency_penalty", "penalty_last_n", "max", "seed",
    "show", "esp", "mcp"
  ];
  const V2_FIELDS = [...LEGACY_FIELDS, "stop"];
  const FIELDS = [...V2_FIELDS, "format", "schema_name", "schema_text"];
  const LIMITS = {
    temperature: [0, 2], top_p: [0.001, 1], top_k: [1, 64], min_p: [0, 1],
    repetition_penalty: [0.5, 3], presence_penalty: [0, 2],
    frequency_penalty: [0, 2], penalty_last_n: [1, 4096]
  };

  function record(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) &&
      (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
  }
  function keysExact(value, expected, label) {
    if (!record(value)) throw new Error(label + ": expected an object");
    const keys = Object.keys(value);
    if (keys.length !== expected.length || keys.some((key) => !expected.includes(key))) {
      throw new Error(label + ": unexpected or missing fields");
    }
  }
  function nameOf(value) {
    if (typeof value !== "string") throw new Error("Preset name must be text");
    const name = value.trim().normalize("NFC");
    if (!name || name.length > MAX_NAME || /[\u0000-\u001f\u007f]/.test(name)) {
      throw new Error("Preset name must have 1–60 characters and no control characters");
    }
    return name;
  }
  function optionalPositiveInteger(value, field) {
    if (value === "") return "";
    if (typeof value !== "string" && typeof value !== "number") {
      throw new Error(field + ": expected a positive integer or empty value");
    }
    const str = String(value);
    if (!/^[1-9]\d*$/.test(str) || !Number.isSafeInteger(Number(str)) || Number(str) > 2147483647) {
      throw new Error(field + ": expected an integer between 1 and 2147483647");
    }
    return str;
  }
  function settingsOf(value, sourceVersion = VERSION) {
    keysExact(value, sourceVersion === 1 ? LEGACY_FIELDS : sourceVersion === 2 ? V2_FIELDS : FIELDS,
      "Sampling settings");
    const clean = {};
    for (const field of FIELDS) {
      const item = sourceVersion < 2 && field === "stop" ? [] :
        sourceVersion < 3 && ["format", "schema_name", "schema_text"].includes(field) ?
          ({format: "text", schema_name: "", schema_text: ""})[field] : value[field];
      if (field === "stop") {
        if (!Array.isArray(item) || item.length > 16 || item.some((s) => typeof s !== "string" ||
            !s.length || s.length > 256) || new Set(item).size !== item.length ||
            item.reduce((n, s) => n + s.length, 0) > 2048) {
          throw new Error("stop: expected 0–16 unique nonempty strings, each at most 256 characters");
        }
        clean.stop = [...item];
        continue;
      } else if (["format", "schema_name", "schema_text"].includes(field)) {
        // Validate all three together below, so name/schema checks are only mandatory in schema mode.
        clean[field] = item;
        continue;
      } else if (field === "thinking") {
        if (!["none", "low", "medium", "high"].includes(item)) {
          throw new Error("Thinking: unsupported mode");
        }
      } else if (["show", "esp", "mcp"].includes(field)) {
        if (typeof item !== "boolean") throw new Error(field + ": expected a boolean");
      } else if (field === "max" || field === "seed") {
        clean[field] = optionalPositiveInteger(item, field);
        continue;
      } else {
        const [min, max] = LIMITS[field];
        if (typeof item !== "number" || !Number.isFinite(item) || item < min || item > max ||
            (["top_k", "penalty_last_n"].includes(field) && !Number.isInteger(item))) {
          throw new Error(field + ": value outside supported range");
        }
      }
      clean[field] = item;
    }
    // Keep a single canonical definition of supported JSON schema settings for API requests and exported presets.
    Object.assign(clean, StrataStructuredSettings(clean));
    return clean;
  }
  function StrataStructuredSettings(value) {
    // presets.js is also used independently by Node; do not depend on script load order.
    const format = value.format, schema_name = value.schema_name, schema_text = value.schema_text;
    if (!["text", "json_object", "json_schema"].includes(format) ||
        typeof schema_name !== "string" || typeof schema_text !== "string" ||
        schema_name.length > 64 || schema_text.length > 32768 ||
        /[\u0000-\u001f\u007f]/.test(schema_name)) {
      throw new Error("Invalid structured output settings");
    }
    if (format === "json_schema") {
      if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(schema_name)) throw new Error("Invalid schema name");
      let schema;
      try { schema = JSON.parse(schema_text); } catch (_) { throw new Error("Invalid schema JSON"); }
      if (!schema || typeof schema !== "object" || Array.isArray(schema) || schema.type !== "object") {
        throw new Error("JSON Schema root must be type object");
      }
      if (new TextEncoder().encode(schema_text).byteLength > 65536) {
        throw new Error("JSON Schema exceeds 65536 UTF-8 bytes");
      }
      function inspect(node, depth) {
        if (depth > 32) throw new Error("JSON Schema exceeds 32 nesting levels");
        if (node && typeof node === "object") {
          for (const [key, item] of Object.entries(node)) {
            if (["__proto__", "constructor", "prototype"].includes(key)) throw new Error("Forbidden schema field");
            if (["$ref", "$dynamicRef"].includes(key) && (typeof item !== "string" || !item.startsWith("#"))) {
              throw new Error("Only local JSON Schema references are permitted");
            }
            inspect(item, depth + 1);
          }
        }
      }
      inspect(schema, 0);
    }
    return {format, schema_name, schema_text};
  }
  function empty() { return {format: FORMAT, version: VERSION, presets: []}; }
  function validate(value) {
    keysExact(value, ["format", "version", "presets"], "Preset document");
    if (value.format !== FORMAT || ![1, 2, VERSION].includes(value.version)) {
      throw new Error("Unsupported preset document format or version");
    }
    if (!Array.isArray(value.presets) || value.presets.length > MAX_PRESETS) {
      throw new Error("Preset document must contain at most 50 entries");
    }
    const seen = new Set();
    const presets = value.presets.map((preset) => {
      keysExact(preset, ["name", "settings"], "Preset");
      const name = nameOf(preset.name);
      const key = name.toLocaleLowerCase();
      if (seen.has(key)) throw new Error("Duplicate preset name: " + name);
      seen.add(key);
      return {name, settings: settingsOf(preset.settings, value.version)};
    });
    return {format: FORMAT, version: VERSION, presets};
  }
  function upsert(document, name, settings) {
    const doc = validate(document);
    const title = nameOf(name);
    const item = {name: title, settings: settingsOf(settings)};
    const index = doc.presets.findIndex((p) => p.name.toLocaleLowerCase() === title.toLocaleLowerCase());
    if (index >= 0) doc.presets[index] = item;
    else {
      if (doc.presets.length >= MAX_PRESETS) throw new Error("Maximum of 50 presets reached");
      doc.presets.push(item);
    }
    doc.presets.sort((a, b) => a.name.localeCompare(b.name));
    return validate(doc);
  }
  function remove(document, name) {
    const doc = validate(document);
    const title = nameOf(name).toLocaleLowerCase();
    const next = doc.presets.filter((p) => p.name.toLocaleLowerCase() !== title);
    if (next.length === doc.presets.length) throw new Error("Selected preset was not found");
    return validate({...doc, presets: next});
  }
  return Object.freeze({FORMAT, VERSION, MAX_PRESETS, MAX_NAME, FIELDS, empty, validate, settingsOf, upsert, remove});
});
