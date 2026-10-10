// Browser-side JSON output settings and bounded schema validation.
// This is a request builder, NOT a grammar-constrained decoder: the server validates
// a buffered answer and reports an error if the model violates the contract.
"use strict";
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.StrataStructured = api;
})(typeof window !== "undefined" ? window : null, function () {
  const DEFAULT = Object.freeze({format: "text", schema_name: "", schema_text: ""});
  const MAX_SCHEMA_CHARS = 32768;
  const MODES = ["text", "json_object", "json_schema"];
  function plain(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) &&
      (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
  }
  function inspect(node, depth = 0) {
    if (depth > 32) throw new Error("JSON Schema is too deeply nested (maximum 32 levels)");
    if (node && typeof node === "object") {
      if (Object.prototype.hasOwnProperty.call(node, "__proto__") ||
          Object.prototype.hasOwnProperty.call(node, "constructor") ||
          Object.prototype.hasOwnProperty.call(node, "prototype")) {
        throw new Error("JSON Schema contains a forbidden key");
      }
      for (const [key, value] of Object.entries(node)) {
        if ((key === "$ref" || key === "$dynamicRef") &&
            (typeof value !== "string" || !value.startsWith("#"))) {
          throw new Error("Only local JSON Schema references (#...) are permitted");
        }
        inspect(value, depth + 1);
      }
    }
  }
  function settingsOf(value) {
    if (!plain(value) || Object.keys(value).some((key) => !["format", "schema_name", "schema_text"].includes(key))) {
      throw new Error("Invalid structured output settings");
    }
    const format = value.format;
    const schema_name = value.schema_name;
    const schema_text = value.schema_text;
    if (!MODES.includes(format) || typeof schema_name !== "string" || typeof schema_text !== "string") {
      throw new Error("Invalid JSON format or schema fields");
    }
    if (schema_name.length > 64 || schema_text.length > MAX_SCHEMA_CHARS || /[\u0000-\u001f\u007f]/.test(schema_name)) {
      throw new Error("Schema name must be at most 64 characters; schema at most 32768 characters");
    }
    if (format === "json_schema") {
      if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(schema_name)) {
        throw new Error("JSON Schema needs a name of 1–64 letters, digits, underscores or dashes");
      }
      if (!schema_text.trim()) throw new Error("Enter a JSON Schema object");
      let schema;
      try { schema = JSON.parse(schema_text); } catch (e) { throw new Error("JSON Schema is not valid JSON: " + e.message); }
      if (!plain(schema) || schema.type !== "object") {
        throw new Error("JSON Schema root must be an object with type: object");
      }
      if (new TextEncoder().encode(schema_text).byteLength > 65536) {
        throw new Error("JSON Schema exceeds 65536 UTF-8 bytes");
      }
      inspect(schema);
    }
    return {format, schema_name, schema_text};
  }
  function requestFormat(settings) {
    const s = settingsOf(settings);
    if (s.format === "text") return undefined;
    if (s.format === "json_object") return {type: "json_object"};
    return {type: "json_schema", json_schema: {
      name: s.schema_name, strict: true, schema: JSON.parse(s.schema_text)
    }};
  }
  function responsesFormat(settings) {
    const result = requestFormat(settings);
    if (!result) return undefined;
    if (result.type === "json_object") return result;
    return {type: "json_schema", ...result.json_schema};
  }
  return Object.freeze({DEFAULT, MAX_SCHEMA_CHARS, settingsOf, requestFormat, responsesFormat});
});
