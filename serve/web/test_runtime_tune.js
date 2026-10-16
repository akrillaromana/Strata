"use strict";
const assert = require("assert");
const tune = require("./runtime_tune.js");

assert.deepStrictEqual(tune.normalize({pcie_frac: 0.2, spec_min_p: 1}), {pcie_frac: 0.2, spec_min_p: 1});
assert.deepStrictEqual(tune.normalize({pcie_frac: -1, spec_min_p: 2}), {pcie_frac: null, spec_min_p: null});
assert.deepStrictEqual(tune.request({pcie_frac: null, spec_min_p: 0.9}), {spec_min_p: 0.9});
assert.deepStrictEqual(tune.effective({pcie_frac: null, spec_min_p: 1}, {pcie_frac: 0.26, spec_min_p: 0.9}),
                       {pcie_frac: 0.26, spec_min_p: 1});
assert.strictEqual(tune.valueText(0.20), "0.2");
assert.strictEqual(tune.valueText(1), "1");
assert.strictEqual(tune.valueText(undefined), "–");
console.log("runtime_tune: OK");
