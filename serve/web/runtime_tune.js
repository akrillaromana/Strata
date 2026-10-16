// Browser-local per-request Strata engine tuning. It never writes the run-config JSON.
"use strict";
(function (root, make) {
  const api = make();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.StrataRuntimeTune = api;
})(typeof window !== "undefined" ? window : null, function () {
  const KEYS = ["pcie_frac", "spec_min_p"];
  const EMPTY = Object.freeze({pcie_frac: null, spec_min_p: null});

  function finite01(value) {
    return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1;
  }
  function normalize(value) {
    const clean = {...EMPTY};
    if (!value || typeof value !== "object" || Array.isArray(value)) return clean;
    for (const key of KEYS) {
      const v = value[key];
      if (v === null || v === undefined || v === "") clean[key] = null;
      else if (finite01(v)) clean[key] = v;
    }
    return clean;
  }
  function request(value) {
    const clean = normalize(value), out = {};
    for (const key of KEYS) if (clean[key] !== null) out[key] = clean[key];
    return out;
  }
  function effective(overrides, modelDefaults) {
    const over = normalize(overrides), base = modelDefaults && typeof modelDefaults === "object" ? modelDefaults : {};
    const out = {};
    for (const key of KEYS) {
      if (over[key] !== null) out[key] = over[key];
      else if (finite01(base[key])) out[key] = base[key];
    }
    return out;
  }
  function valueText(value) {
    if (!finite01(value)) return "–";
    return Number(value).toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  }
  return Object.freeze({KEYS, EMPTY, normalize, request, effective, valueText});
});
