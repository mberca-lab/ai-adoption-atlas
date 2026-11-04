const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const root = path.resolve(__dirname, "..");

function adapter({ missing = false, demo = false, segments = null } = {}) {
  const context = {
    window: { Atlas: { params: new URLSearchParams(demo ? "demo=1" : "") } },
    console: { info() {}, warn() {} },
    fetch: async url => {
      if (url.endsWith("manifest.json")) {
        return { ok: true, json: async () => ({ files: ["trust_trends.json", "modelling.json", "segments.json"] }) };
      }
      if (missing && url.endsWith("segments.json")) return { ok: false };
      const file = path.basename(url);
      if (file === "segments.json") {
        return { ok: true, json: async () => segments || ({
          meta: { status: "final" },
          classes: [{ id: 1, label: "Test-only class", share: 1 }],
          rules: [{ basket: "B24", lhs: "Test A", rhs: "Test B", lift: 2 }],
          items: [{ basket: "B24", item: "Test A", support: 0.1 }]
        }) };
      }
      return { ok: true, json: async () => JSON.parse(readFileSync(path.join(root, "site_data", file), "utf8")) };
    }
  };
  vm.createContext(context);
  vm.runInContext(readFileSync(path.join(root, "site", "js", "data.js"), "utf8"), context);
  return context.window.Atlas;
}

test("wide exports load mix-adjusted series and four experience bands", async () => {
  const data = await adapter().loadData();
  assert.equal(data.anyFixture, false);
  assert.equal(data.std.use.length, 4);
  assert.equal(data.std.use.find(p => p.year === 2025).pct, 82);
  assert.equal(data.std.use.find(p => p.year === 2026).series, "B");
  assert.equal(data.experience.bands.length, 4);
  assert.equal(data.facts.use_distrust_2025, "31%");
  assert.equal(data.trend.trust.some(p => p.year === 2026), false);
});

test("missing results reject rather than inventing public findings", async () => {
  await assert.rejects(adapter({ missing: true }).loadData(), /Missing segments.json/);
});

test("explicit development demo remains clearly labelled", async () => {
  const data = await adapter({ missing: true, demo: true }).loadData();
  assert.equal(data.anyFixture, true);
  assert.equal(data.sectionStatus.segments, "fixture");
  assert.equal(data.segments.status, "provisional");
});

test("higher-order lift is not projected onto pairwise edges or null profiles onto zeros", async () => {
  const data = await adapter({ segments: {
    meta: { status: "final" },
    classes: [{ id: 1, label: "Test-only class", share: 1, trust_pct: 0.5,
      profile: [{ label: "Unknown", value: null }] }],
    rules: [
      { basket: "B24", lhs: "{A,B}", rhs: "{C}", lift: 12 },
      { basket: "B24", lhs: "{A}", rhs: "{C}", lift: 2 }
    ]
  } }).loadData();
  assert.equal(data.segments.baskets[0].links.length, 1);
  assert.equal(data.segments.baskets[0].links[0].lift, 2);
  assert.equal(data.segments.classes[0].profile.length, 0);
  assert.equal(data.segments.classes[0].trust_pct, 0.5);
});
