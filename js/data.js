/* =============================================================================
   AI Adoption Atlas — DATA ADAPTER (the only place charts get numbers from)
   -----------------------------------------------------------------------------
   Loads, in order of preference:
       data/<name>.json            (copied into site/ at build: tools/copy-data.ps1)
       ../site_data/<name>.json    (local preview from the project root)
   for name in trust_trends, modelling, segments.

   If a file is missing or unreadable, that dataset falls back to DEV_FIXTURES
   (below). Fixture use is tracked per dataset in Atlas.data.status and the UI
   shows an "Illustrative data" badge on every affected chart and a global pill.

   The normalisers accept the column names used by the analysis scripts
   (outputs/STAGE/tables/NAME.csv and scripts/03_modelling.py) and a few aliases.
   See site/README.md for the expected JSON contract.
   ========================================================================== */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});
  const FILES = ["trust_trends", "modelling", "segments"];
  const BASES = ["data/", "../site_data/"];

  /* ===========================================================================
     !!! DEV_FIXTURES — ILLUSTRATIVE ONLY — INVENTED NUMBERS — NOT RESULTS !!!
     Used ONLY when the matching JSON file is missing. Shapes mirror the real
     contract so the layout can be developed. Never quote these numbers.
     ======================================================================== */
  const DEV_FIXTURES = (function () {
    const wilson = (pct, n) => {
      const p = pct / 100, z = 1.96, d = 1 + z * z / n;
      const c = (p + z * z / (2 * n)) / d, h = (z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / d;
      return [+(100 * (c - h)).toFixed(1), +(100 * (c + h)).toFixed(1)];
    };
    const row = (outcome, population, year, pct, n) => {
      const [lo, hi] = wilson(pct, n);
      return { outcome, population, year, series: year === 2026 ? "B (2026, series break)" : "A (2023-2025)", pct, lo, hi, n };
    };
    const raw = [
      row("use", "P1", 2023, 45, 60000), row("use", "P1", 2024, 62, 45000), row("use", "P1", 2025, 80, 25000), row("use", "P1", 2026, 85, 13000),
      row("plan", "P1", 2023, 26, 60000), row("plan", "P1", 2024, 14, 45000), row("plan", "P1", 2025, 5, 25000),
      row("fav", "P2", 2023, 84, 29000), row("fav", "P2", 2024, 76, 29000), row("fav", "P2", 2025, 72, 20000), row("fav", "P2", 2026, 62, 11000),
      row("trust", "P2", 2023, 45, 29000), row("trust", "P2", 2024, 42, 29000), row("trust", "P2", 2025, 37, 20000),
      row("distrust", "P2", 2023, 25, 29000), row("distrust", "P2", 2024, 31, 29000), row("distrust", "P2", 2025, 38, 20000)
    ];
    const std = raw.filter(r => r.year < 2026).map(r => ({ outcome: r.outcome, year: r.year, std_pct: r.pct + (r.outcome === "use" ? -1 : 0.5), lo: r.lo - 0.4, hi: r.hi + 0.4 }));
    const bands = ["0-4 yrs", "5-9 yrs", "10-19 yrs", "20+ yrs"];
    const exp = { trust: [[50, 47, 44, 40], [47, 43, 40, 35], [44, 39, 35, 30]], distrust: [[20, 23, 27, 31], [26, 29, 33, 38], [31, 35, 40, 46]], fav: [[88, 86, 84, 80], [81, 78, 75, 70], [78, 74, 70, 64]] };
    const expRows = [];
    Object.keys(exp).forEach(o => exp[o].forEach((vals, yi) => vals.forEach((pct, bi) => {
      const n = 4000 + 1000 * bi; const [lo, hi] = wilson(pct, n);
      expRows.push({ outcome: o, exp_band: bands[bi], year: 2023 + yi, pct, lo, hi, n });
    })));

    const models = ["logit", "lgbm", "rf"];
    const metrics = [], diffs = [], calib = [], shap = [];
    const baseAuc = { fav: { D: 0.62, B: 0.68 }, trust: { D: 0.60, B: 0.65 } };
    const bump = { logit: 0, lgbm: 0.006, rf: -0.004 };
    Object.keys(baseAuc).forEach(oc => ["D", "B"].forEach(fs => models.forEach(m => {
      const auc = +(baseAuc[oc][fs] + bump[m]).toFixed(3);
      metrics.push({ outcome: oc, scheme: "temporal_2324to25", feature_set: fs, model: m, n_train: 50000, n_test: 20000, prevalence_test: oc === "fav" ? 0.72 : 0.37, auc, auc_lo: +(auc - 0.008).toFixed(3), auc_hi: +(auc + 0.008).toFixed(3), log_loss: 0.6 - auc / 10, brier: 0.22 - auc / 20 });
      if (m !== "logit") diffs.push({ outcome: oc, scheme: "temporal_2324to25", feature_set: fs, model: m, d_auc: bump[m], d_auc_lo: bump[m] - 0.004, d_auc_hi: bump[m] + 0.004, d_log_loss: -bump[m] / 5, d_log_loss_rel: -bump[m] / 3, verdict: "illustrative: no gain that matters" });
    })));
    ["fav", "trust"].forEach(oc => ["logit", "lgbm"].forEach(m => {
      for (let b = 0; b < 10; b++) {
        const mp = 0.05 + b * 0.1, wob = (m === "lgbm" ? 0.025 : -0.015) * Math.sin(b);
        const ob = Math.min(0.98, Math.max(0.02, mp + wob));
        calib.push({ outcome: oc, model: m, bin: b + 1, n: 1500, mean_pred: +mp.toFixed(3), observed: +ob.toFixed(3), obs_lo: +(ob - 0.025).toFixed(3), obs_hi: +(ob + 0.025).toFixed(3) });
      }
    }));
    const feats = [["years_code", "Years of coding"], ["ai_task_write", "Uses AI to write code"], ["region", "Region"], ["role_family", "Role family"], ["org_size", "Organisation size"], ["age_band", "Age band"], ["ai_freq", "AI use frequency"], ["remote", "Remote / hybrid"], ["edu", "Education"], ["learn_ai", "Learns with AI"]];
    ["fav", "trust"].forEach(oc => ["logit", "lgbm"].forEach(m => feats.forEach(([f, label], i) => {
      const v = +(0.32 / (i + 1.3) + (m === "lgbm" ? 0.006 : 0)).toFixed(4);
      shap.push({ outcome: oc, model: m, feature: f, label, mean_abs_shap: v, shap_lo: +(v * 0.82).toFixed(4), shap_hi: +(v * 1.18).toFixed(4), mean_rank: i + 1, rank_lo: Math.max(1, i), rank_hi: i + 2, p_top3: Math.max(0, 1 - i * 0.3), p_top5: Math.max(0, 1 - i * 0.15), n_boot: 200 });
    })));

    const seg = [
      { id: 1, label: "Daily integrators", share: 0.31, trust_pct: 58, fav_pct: 91, description: "Use AI most days, across many tasks, and broadly trust it.", profile: [["Uses AI daily", 0.86], ["Uses AI for writing code", 0.92], ["Favourable", 0.91], ["Trusts accuracy", 0.58]] },
      { id: 2, label: "Pragmatic sceptics", share: 0.27, trust_pct: 24, fav_pct: 70, description: "Use AI routinely but double-check everything.", profile: [["Uses AI daily", 0.55], ["Uses AI for writing code", 0.78], ["Favourable", 0.70], ["Trusts accuracy", 0.24]] },
      { id: 3, label: "Cautious newcomers", share: 0.18, trust_pct: 46, fav_pct: 80, description: "Early in their careers and trying AI for learning.", profile: [["Uses AI daily", 0.34], ["Uses AI for learning", 0.81], ["Favourable", 0.80], ["Trusts accuracy", 0.46]] },
      { id: 4, label: "Seasoned holdouts", share: 0.14, trust_pct: 12, fav_pct: 38, description: "Long-tenured developers who rarely use AI tools.", profile: [["Uses AI daily", 0.08], ["Uses AI for writing code", 0.22], ["Favourable", 0.38], ["Trusts accuracy", 0.12]] },
      { id: 5, label: "Agent explorers", share: 0.10, trust_pct: 52, fav_pct: 88, description: "Heavy users experimenting with agents and many tools.", profile: [["Uses agents", 0.74], ["Uses 4+ tools", 0.69], ["Favourable", 0.88], ["Trusts accuracy", 0.52]] }
    ].map(s => ({ ...s, share_lo: s.share - 0.015, share_hi: s.share + 0.015, profile: s.profile.map(([label, value]) => ({ label, value })) }));

    const net = (basket, year, description, items, pairs) => ({
      basket, year, description,
      items: items.map(([item, vendor, support]) => ({ basket, year, item, vendor, support })),
      rules: pairs.map(([a, b, lift, support]) => ({ basket, a, b, lift, lift_lo: +(lift * 0.92).toFixed(2), lift_hi: +(lift * 1.08).toFixed(2), support, confidence: +(Math.min(0.95, support * lift * 3)).toFixed(2) }))
    });
    const baskets = [
      net("B23", 2023, "2023 AI search/chat + developer tools", [["ChatGPT", "OpenAI", 0.86], ["GitHub Copilot", "Microsoft", 0.37], ["Bing AI", "Microsoft", 0.22], ["Google Bard", "Google", 0.12], ["Tabnine", "Other", 0.06], ["AWS CodeWhisperer", "Amazon", 0.04], ["Codeium", "Other", 0.03], ["Phind", "Other", 0.05], ["WolframAlpha", "Other", 0.05], ["Visual Studio IntelliCode", "Microsoft", 0.09], ["Perplexity", "Other", 0.03]],
        [["Bing AI", "Google Bard", 2.4, 0.06], ["Tabnine", "Codeium", 3.1, 0.012], ["AWS CodeWhisperer", "Codeium", 2.8, 0.011], ["GitHub Copilot", "Visual Studio IntelliCode", 1.9, 0.06], ["Phind", "Perplexity", 3.4, 0.011], ["Bing AI", "WolframAlpha", 1.7, 0.02], ["Google Bard", "WolframAlpha", 2.0, 0.015], ["AWS CodeWhisperer", "Tabnine", 2.6, 0.012], ["GitHub Copilot", "Tabnine", 1.4, 0.03], ["Phind", "Google Bard", 1.6, 0.012], ["ChatGPT", "Phind", 1.25, 0.05]]),
      net("B24", 2024, "2024 AI search & developer tools", [["ChatGPT", "OpenAI", 0.84], ["GitHub Copilot", "Microsoft", 0.45], ["Google Gemini", "Google", 0.23], ["Bing AI", "Microsoft", 0.17], ["Claude", "Anthropic", 0.09], ["Perplexity", "Other", 0.07], ["Codeium", "Other", 0.06], ["Tabnine", "Other", 0.05], ["Phind", "Other", 0.05], ["AWS CodeWhisperer", "Amazon", 0.04], ["Visual Studio IntelliCode", "Microsoft", 0.1], ["Meta AI", "Meta", 0.04]],
        [["Claude", "Perplexity", 2.9, 0.025], ["Google Gemini", "Bing AI", 2.1, 0.08], ["Codeium", "Tabnine", 2.7, 0.012], ["GitHub Copilot", "Visual Studio IntelliCode", 1.8, 0.07], ["Phind", "Perplexity", 3.2, 0.012], ["Claude", "Google Gemini", 1.6, 0.04], ["Meta AI", "Google Gemini", 2.2, 0.02], ["AWS CodeWhisperer", "Codeium", 2.5, 0.01], ["Perplexity", "Google Gemini", 1.7, 0.03], ["Claude", "Phind", 2.0, 0.011]]),
      net("B26", 2026, "2026 AI coding agents/assistants + LLM providers", [["Anthropic", "Anthropic", 0.82], ["OpenAI", "OpenAI", 0.78], ["Google", "Google", 0.48], ["GitHub Copilot", "Microsoft", 0.52], ["Cursor", "Other", 0.33], ["Claude Code", "Anthropic", 0.41], ["Codex CLI", "OpenAI", 0.18], ["Gemini CLI", "Google", 0.14], ["Windsurf", "Other", 0.07], ["Mistral", "Other", 0.08], ["DeepSeek", "Other", 0.11], ["Ollama", "Other", 0.13]],
        [["Claude Code", "Anthropic", 1.5, 0.39], ["Codex CLI", "OpenAI", 1.3, 0.17], ["Gemini CLI", "Google", 1.9, 0.13], ["Ollama", "Mistral", 3.1, 0.03], ["DeepSeek", "Ollama", 2.6, 0.04], ["Cursor", "Windsurf", 1.8, 0.04], ["Claude Code", "Codex CLI", 1.6, 0.11], ["Gemini CLI", "Codex CLI", 2.4, 0.06], ["Mistral", "DeepSeek", 2.7, 0.025], ["Cursor", "Claude Code", 1.25, 0.17], ["GitHub Copilot", "OpenAI", 1.2, 0.48]])
    ];

    return {
      trust_trends: {
        meta: { fixture: true, note: "ILLUSTRATIVE DEV FIXTURE — invented numbers", sample_sizes: [{ year: 2023, n: 89000 }, { year: 2024, n: 65000 }, { year: 2025, n: 49000 }, { year: 2026, n: 29000 }] },
        raw_by_year: raw, standardised_by_year: std, experience_gradient: expRows
      },
      modelling: {
        meta: { fixture: true, margin_that_matters: { d_auc: 0.01, rel_log_loss: 0.01 }, outcomes: { fav: "AI favourable (illustrative)", trust: "Trusts AI accuracy (illustrative)" }, feature_sets: { D: "demographics/context only", B: "D + AI-usage tasks" } },
        model_metrics: metrics, diff_vs_logit: diffs, calibration_bins: calib, shap_drivers: shap
      },
      segments: {
        meta: { fixture: true, status: "provisional" },
        classes: seg,
        rules: baskets
      }
    };
  })();
  A.DEV_FIXTURES = DEV_FIXTURES;

  /* ---------------------------- loading ---------------------------------- */
  async function fetchJSON(name, manifest) {
    // With a manifest (written by tools/copy-data.ps1) only listed files are requested,
    // so missing datasets never produce 404s in the console.
    const bases = manifest ? (manifest.includes(name) ? ["data/"] : []) : BASES;
    for (const base of bases) {
      try {
        const res = await fetch(base + name + ".json", { cache: "no-cache" });
        if (!res.ok) continue;
        const json = await res.json();
        if (json && typeof json === "object") return { json, from: base + name + ".json" };
      } catch (e) { /* try next base (file:// or missing) */ }
    }
    return null;
  }

  /* ---------------------------- helpers ---------------------------------- */
  const num = v => (v === null || v === undefined || v === "" || isNaN(+v) ? null : +v);
  const pick = (o, keys) => { for (const k of keys) if (o && o[k] !== undefined && o[k] !== null) return o[k]; return undefined; };
  function findArray(obj, keys, test) {
    if (!obj) return [];
    for (const k of keys) {
      const v = k.split(".").reduce((o, p) => (o ? o[p] : undefined), obj);
      if (Array.isArray(v) && v.length) return v;
    }
    if (test) { // deep scan for the first array of objects passing `test`
      const seen = new Set();
      const walk = o => {
        if (!o || typeof o !== "object" || seen.has(o)) return null; seen.add(o);
        if (Array.isArray(o)) { if (o.length && typeof o[0] === "object" && test(o[0])) return o; return null; }
        for (const k of Object.keys(o)) { const r = walk(o[k]); if (r) return r; }
        return null;
      };
      return walk(obj) || [];
    }
    return [];
  }
  // proportions may be 0–1 or 0–100: return a scaler that maps to percent
  function pctScaler(rows, fields) {
    let max = 0;
    rows.forEach(r => fields.forEach(f => { const v = num(r[f]); if (v !== null) max = Math.max(max, Math.abs(v)); }));
    return max > 0 && max <= 1.0001 ? 100 : 1;
  }
  const OUTCOME_ALIAS = { using: "use", use_ai: "use", ai_use: "use", plan_to_use: "plan", planning: "plan", favourable: "fav", favorable: "fav", ai_sent_favorable: "fav", trust_accuracy: "trust", trust5: "trust" };
  const normOutcome = o => { const k = String(o || "").toLowerCase().trim(); return OUTCOME_ALIAS[k] || k; };

  /* ------------------------- normalise trust_trends ----------------------- */
  // trust_trends.json may arrive in "wide" form: series:[{name, series_group, labels, values, ci_low, ci_high, n}]
  // name patterns: <o>_raw_2023_2025 | <o>_raw_2026 | <o>_standardised | <o>_by_experience_<band> | other extras
  function wideToLong(js) {
    if (!js || !Array.isArray(js.series) || !js.series.length || !Array.isArray(js.series[0].labels)) return js;
    const out = { meta: Object.assign({ attribution: js.attribution, caveats: js.caveats, generated: js.generated }, js.meta || {}), followup: js.followup || null, raw_by_year: [], standardised_by_year: [], experience_gradient: [], extras: {} };
    js.series.forEach(s => {
      const name = String(s.name || ""), desc = String(s.description || "");
      const at = (arr, i) => (Array.isArray(arr) ? arr[i] : null);
      const rows = (s.labels || []).map((l, i) => ({ label: l, year: /^\d{4}$/.test(String(l)) ? +l : null, value: at(s.values, i), lo: at(s.ci_low, i), hi: at(s.ci_high, i), n: at(s.n, i) }));
      let m;
      if ((m = name.match(/^(.+?)_raw_\d{4}/))) {
        const pop = (desc.match(/\b(P\d)\b/) || [])[1] || null;
        rows.filter(r => r.year).forEach(r => out.raw_by_year.push({ outcome: m[1], population: pop, year: r.year, series: s.series_group || (r.year >= 2026 ? "B" : "A"), pct: r.value, lo: r.lo, hi: r.hi, n: r.n }));
      } else if ((m = name.match(/^(.+?)_standardi[sz]ed(?:_\d{4}(?:_\d{4})?)?$/))) {
        rows.filter(r => r.year).forEach(r => out.standardised_by_year.push({ outcome: m[1], year: r.year, std_pct: r.value, lo: r.lo, hi: r.hi, n: r.n }));
      } else if ((m = name.match(/^(.+?)_by_experience_(.+)$/))) {
        const band = (desc.match(/(\d+\s*(?:[-–]\s*\d+|\+)\s*yrs)/) || [])[1] || m[2];
        rows.filter(r => r.year).forEach(r => out.experience_gradient.push({ outcome: m[1], exp_band: band.replace(/\s+/g, " "), year: r.year, pct: r.value, lo: r.lo, hi: r.hi, n: r.n }));
      } else out.extras[name] = { description: desc, group: s.series_group, rows };
    });
    return out;
  }

  function normTrends(js) {
    js = wideToLong(js);
    const rawRows = findArray(js, ["raw_by_year", "raw", "by_year", "trends", "series", "tables.raw_by_year"],
      r => "year" in r && "outcome" in r && ("pct" in r || "value" in r || "prop" in r));
    const sc = pctScaler(rawRows, ["pct", "value", "prop", "lo", "hi"]);
    const toPt = r => ({
      outcome: normOutcome(r.outcome), population: r.population || null, year: +r.year,
      series: String(r.series || (+r.year >= 2026 ? "B" : "A")).trim().charAt(0).toUpperCase() === "B" ? "B" : "A",
      pct: num(pick(r, ["pct", "value", "prop"])) === null ? null : num(pick(r, ["pct", "value", "prop"])) * sc, lo: num(pick(r, ["lo", "ci_lo", "lower"])) !== null ? num(pick(r, ["lo", "ci_lo", "lower"])) * sc : null,
      hi: num(pick(r, ["hi", "ci_hi", "upper"])) !== null ? num(pick(r, ["hi", "ci_hi", "upper"])) * sc : null, n: num(r.n)
    });
    const trend = {};
    rawRows.map(toPt).filter(p => p.pct !== null && !isNaN(p.pct)).forEach(p => {
      // keep primary populations: use/plan from P1, sentiment from P2 when several exist
      (trend[p.outcome] = trend[p.outcome] || []).push(p);
    });
    Object.keys(trend).forEach(k => {
      const pref = ["use", "plan"].includes(k) ? "P1" : "P2";
      const byYear = new Map();
      trend[k].forEach(p => { const cur = byYear.get(p.year); if (!cur || (p.population === pref && cur.population !== pref)) byYear.set(p.year, p); });
      trend[k] = [...byYear.values()].sort((a, b) => a.year - b.year);
    });

    const stdRows = findArray(js, ["standardised_by_year", "standardized_by_year", "std_by_year", "standardised"],
      r => "year" in r && "outcome" in r && ("std_pct" in r));
    const ssc = pctScaler(stdRows, ["std_pct", "lo", "hi"]);
    const std = {};
    stdRows.forEach(r => {
      const o = normOutcome(r.outcome), v = num(pick(r, ["std_pct", "pct", "value"]));
      if (v === null) return;
      (std[o] = std[o] || []).push({ outcome: o, year: +r.year, series: +r.year >= 2026 ? "B" : "A", pct: v * ssc, lo: num(r.lo) !== null ? num(r.lo) * ssc : null, hi: num(r.hi) !== null ? num(r.hi) * ssc : null, n: num(r.n) });
    });
    Object.values(std).forEach(a => a.sort((x, y) => x.year - y.year));

    const expRaw = findArray(js, ["experience_gradient", "by_experience", "experience", "gradient"],
      r => "year" in r && ("exp_band" in r || "band" in r || "experience" in r));
    const esc = pctScaler(expRaw, ["pct", "value", "prop", "lo", "hi"]);
    const expRows = expRaw.map(r => ({
      outcome: normOutcome(r.outcome || "trust"), band: String(pick(r, ["exp_band", "band", "experience", "level"])), year: +r.year,
      pct: num(pick(r, ["pct", "value", "prop", "adj_pct", "std_pct"])) === null ? null : num(pick(r, ["pct", "value", "prop", "adj_pct", "std_pct"])) * esc,
      lo: num(pick(r, ["lo", "ci_lo"])) !== null ? num(pick(r, ["lo", "ci_lo"])) * esc : null,
      hi: num(pick(r, ["hi", "ci_hi"])) !== null ? num(pick(r, ["hi", "ci_hi"])) * esc : null, n: num(r.n)
    })).filter(r => r.pct !== null && !isNaN(r.pct) && r.year < 2026);
    const bandOrder = b => { const m = String(b).match(/\d+/); return m ? +m[0] : 999; };
    const bands = [...new Set(expRows.map(r => r.band))].sort((a, b) => bandOrder(a) - bandOrder(b));

    const meta = js.meta || {};
    const sizes = findArray(meta, ["sample_sizes"]).length ? meta.sample_sizes : findArray(js, ["sample_sizes", "n_by_year"]);
    return { trend, std: Object.keys(std).length ? std : null, experience: { bands, rows: expRows }, meta, sizes, extras: js.extras || {}, followup: js.followup || null };
  }

  /* ------------------------- normalise modelling -------------------------- */
  function normModelling(js) {
    const meta = js.meta || {};
    return {
      meta,
      stability: js.primary_stability || null,
      margin: num(pick(meta.margin_that_matters || {}, ["d_auc"])),
      metrics: findArray(js, ["model_metrics", "metrics"]).map(r => ({ ...r, auc: num(r.auc), auc_lo: num(r.auc_lo), auc_hi: num(r.auc_hi) })).filter(r => r.auc !== null),
      diffs: findArray(js, ["diff_vs_logit", "diffs"]),
      calibration: findArray(js, ["calibration_bins", "calibration"]).map(r => ({ ...r, mean_pred: num(r.mean_pred), observed: num(r.observed), obs_lo: num(r.obs_lo), obs_hi: num(r.obs_hi) })).filter(r => r.mean_pred !== null && r.observed !== null),
      shap: findArray(js, ["shap_drivers", "drivers"]).map(r => ({ ...r, label: r.label || r.feature, mean_abs_shap: num(r.mean_abs_shap), shap_lo: num(r.shap_lo), shap_hi: num(r.shap_hi) })).filter(r => r.mean_abs_shap !== null)
    };
  }

  /* ------------------------- normalise segments --------------------------- */
  function parseRuleSide(s) { return String(s || "").replace(/[{}]/g, "").split(",").map(x => x.trim()).filter(Boolean); }
  function normSegments(js) {
    const meta = js.meta || {};
    const clsRaw = findArray(js, ["classes", "segments", "archetypes", "lca.classes", "lca.profiles"],
      r => ("share" in r || "prevalence" in r || "size" in r) && ("label" in r || "name" in r || "class" in r));
    const shScale = pctScaler(clsRaw, ["share", "prevalence", "size"]) === 100 ? 1 : 0.01; // store shares as 0–1
    const classes = clsRaw.map((c, i) => {
      const share = num(pick(c, ["share", "prevalence", "size"]));
      const prof = Array.isArray(c.profile) ? c.profile : Array.isArray(c.indicators) ? c.indicators : c.profile && typeof c.profile === "object" ? Object.entries(c.profile).map(([label, value]) => ({ label, value })) : [];
      const pScale = pctScaler(prof, ["value", "prob", "p"]) === 100 ? 1 : 0.01;
      const tp = num(pick(c, ["trust_pct", "trust"])), fp = num(pick(c, ["fav_pct", "fav"]));
      return {
        id: pick(c, ["id", "class"]) ?? i + 1, label: String(pick(c, ["label", "name"]) ?? `Class ${i + 1}`),
        share: share === null ? null : share * shScale, share_lo: num(c.share_lo) !== null ? num(c.share_lo) * shScale : null, share_hi: num(c.share_hi) !== null ? num(c.share_hi) * shScale : null,
        n: num(c.n), description: c.description || c.summary || "",
        trust_pct: tp === null ? null : c.trust_pct != null ? tp : tp <= 1 ? tp * 100 : tp,
        fav_pct: fp === null ? null : c.fav_pct != null ? fp : fp <= 1 ? fp * 100 : fp,
        profile: prof.map(p => {
          const value = num(pick(p, ["value", "prob", "p"]));
          return { label: String(pick(p, ["label", "indicator_label", "category", "name"]) ?? ""), value: value === null ? null : value * pScale };
        }).filter(p => p.value !== null && p.label)
      };
    }).filter(c => c.share !== null).sort((a, b) => b.share - a.share);

    // tool networks: one entry per basket (year)
    const baskets = [];
    const rulesArr = findArray(js, ["rules", "networks", "tool_rules", "apriori", "rules.baskets"]);
    const looksNested = rulesArr.length && (rulesArr[0].rules || rulesArr[0].edges || rulesArr[0].links);
    const groups = new Map();
    const addGroup = id => { if (!groups.has(id)) groups.set(id, { id, year: null, description: "", items: [], rules: [] }); return groups.get(id); };
    if (looksNested) {
      rulesArr.forEach(b => { const g = addGroup(b.basket || b.id || b.year); g.year = num(b.year); g.description = b.description || ""; g.items = b.items || b.nodes || []; g.rules = b.rules || b.edges || b.links || []; });
    } else {
      rulesArr.forEach(r => addGroup(r.basket || r.year || "all").rules.push(r));
      findArray(js, ["items", "item_support", "nodes"]).forEach(it => addGroup(it.basket || it.year || "all").items.push(it));
    }
    groups.forEach(g => {
      const basketMeta = (meta.baskets || []).find(b => String(b.basket) === String(g.id));
      if (basketMeta) {
        g.description = g.description || basketMeta.description || "";
        g.year = g.year || num(basketMeta.year);
        g.n = num(basketMeta.n_baskets);
      }
      const pairMap = new Map();
      g.rules.forEach(r => {
        let as = r.a !== undefined ? [r.a] : r.source !== undefined ? [r.source] : parseRuleSide(r.lhs);
        let bs = r.b !== undefined ? [r.b] : r.target !== undefined ? [r.target] : parseRuleSide(r.rhs);
        if ((!as.length || !bs.length) && r.rule) { const [l, rr] = String(r.rule).split("=>"); as = parseRuleSide(l); bs = parseRuleSide(rr); }
        if (as.length !== 1 || bs.length !== 1) return;
        const lift = num(r.lift); if (lift === null) return;
        as.forEach(a => bs.forEach(b => {
          if (a === b) return;
          const key = [a, b].sort().join("\u0001"), cur = pairMap.get(key);
          if (!cur || lift > cur.lift) pairMap.set(key, { source: a, target: b, lift, lift_lo: num(r.lift_lo), lift_hi: num(r.lift_hi), support: num(r.support), confidence: num(r.confidence) });
        }));
      });
      const links = [...pairMap.values()];
      const itemMap = new Map();
      g.items.forEach(it => { const id = String(pick(it, ["item", "id", "name"])); itemMap.set(id, { id, vendor: it.vendor || "Other", support: num(it.support) }); if (!g.year && it.year) g.year = +it.year; });
      links.forEach(l => [l.source, l.target].forEach(id => { if (!itemMap.has(id)) itemMap.set(id, { id, vendor: "Other", support: null }); }));
      const nodes = [...itemMap.values()].filter(n => links.some(l => l.source === n.id || l.target === n.id) || (n.support || 0) >= 0.05);
      if (!g.year) { const m = String(g.id).match(/(\d{2,4})/); if (m) g.year = m[1].length === 2 ? 2000 + +m[1] : +m[1]; }
      if (links.length) baskets.push({ id: String(g.id), year: g.year, description: g.description, n: g.n || null, nodes, links });
    });
    baskets.sort((a, b) => (a.year || 0) - (b.year || 0));
    const status = String(meta.status || (meta.final ? "final" : "provisional")).toLowerCase();
    return { meta, status, classes, baskets };
  }

  /* ----------------------------- facts ------------------------------------ */
  function deriveFacts(d) {
    const f = {}, pt = (o, y) => (d.trend[o] || []).find(p => p.year === y);
    const P = v => (v === null || v === undefined || isNaN(v) ? null : Math.round(v) + "%");
    const PP = v => (v === null || v === undefined || isNaN(v) ? null : (v > 0 ? "+" : v < 0 ? "−" : "±") + Math.abs(Math.round(v)) + " pp");
    const dir = (v, up = "rose", down = "fell") => (v === null || isNaN(v) ? null : Math.abs(v) < 1 ? "held steady" : v > 0 ? up : down);
    const years = [...new Set(Object.values(d.trend).flat().map(p => p.year))].sort();
    if (years.length) { f.years_span = years[0] + "–" + years[years.length - 1]; f.n_years = String(years.length); }
    ["use", "plan", "trust", "distrust", "fav"].forEach(o => [2023, 2024, 2025, 2026].forEach(y => { const p = pt(o, y); if (p) f[`${o}_${y}`] = P(p.pct); }));
    ["use", "trust", "distrust", "fav"].forEach(o => {
      const a = pt(o, 2023), b = pt(o, 2025);
      if (a && b) { f[`${o}_change`] = PP(b.pct - a.pct); f[`${o}_dir`] = dir(b.pct - a.pct); }
    });
    [2023, 2025].forEach(y => { const u = pt("use", y), t = pt("trust", y); if (u && t) f[`gap_${y}`] = Math.round(u.pct - t.pct) + " pp"; });

    const uwd = d.extras && d.extras.use_while_distrusting_share_of_pros;
    if (uwd) uwd.rows.forEach(r => { if (r.year && num(r.value) !== null) f[`use_distrust_${r.year}`] = P(num(r.value) <= 1 ? num(r.value) * 100 : num(r.value)); });
    const nUse = (d.trend.use || []).reduce((s, p) => s + (num(p.n) || 0), 0);
    const n = nUse > 0 ? nUse : (d.sizes || []).reduce((s, r) => s + (num(r.n) || 0), 0);
    if (n > 0) f.n_respondents = n.toLocaleString("en-GB");

    const ex = d.experience, rowsT = ex.rows.filter(r => r.outcome === "trust");
    if (ex.bands.length >= 2 && rowsT.length) {
      const young = ex.bands[0], old = ex.bands[ex.bands.length - 1];
      f.exp_young = young; f.exp_old = old;
      const gap = y => { const a = rowsT.find(r => r.band === old && r.year === y), b = rowsT.find(r => r.band === young && r.year === y); return a && b ? a.pct - b.pct : null; };
      const g23 = gap(2023), g25 = gap(2025);
      if (g23 !== null) f.exp_gap_2023 = PP(g23);
      if (g25 !== null) f.exp_gap_2025 = PP(g25);
      if (g23 !== null && g25 !== null) { const w = Math.abs(g25) - Math.abs(g23); f.exp_gap_change = PP(w); f.exp_gap_dir = Math.abs(w) < 1 ? "stayed about the same" : w > 0 ? "widened" : "narrowed"; }
    }

    const m = d.modelling;
    const followup = d.followup;
    if (followup) {
      const main = followup.frequency_contrasts[0], cc = followup.frequency_contrasts[1];
      const levels = followup.frequency_adjusted.filter(r => r.analysis === main.analysis);
      const one = n => (+n).toFixed(1), nfmt = n => (+n).toLocaleString("en-GB");
      f.frequency_n = nfmt(main.n);
      f.frequency_daily = one(levels.find(r => r.frequency === "Daily").adjusted_pct) + "%";
      f.frequency_monthly = one(levels.find(r => r.frequency === "Monthly or infrequent").adjusted_pct) + "%";
      f.frequency_gap = one(main.adjusted_difference_pp) + " pp";
      f.frequency_interval = `[${one(main.lo)}, ${one(main.hi)}]`;
      f.frequency_cc_n = nfmt(cc.n);
      f.frequency_cc_gap = one(cc.adjusted_difference_pp) + " pp";
      f.frequency_cc_interval = `[${one(cc.lo)}, ${one(cc.hi)}]`;
      f.completion_2025 = one(followup.population_flow.find(r => r.year === 2025).completion_pct) + "%";
      const issue = followup.source_audit.issues.find(i => i.id === "2025_count");
      f.archive_2025_n = nfmt(issue.archive_rows);
      f.published_2025_n = nfmt(issue.published_topline);
      f.archive_2025_difference = nfmt(issue.difference);
      f.adoption_bound_interval = `[${one(followup.adoption_change_bounds.lo)}, ${one(followup.adoption_change_bounds.hi)}]`;
    }
    if (m.stability) {
      const s = m.stability, trust = s.summary.find(r => r.outcome === "trust");
      const margin = m.meta.margin_that_matters || {};
      f.stability_runs = String(s.meta.full_pipeline_runs_per_outcome);
      f.stability_refits = String(s.meta.training_bootstrap_refits_per_outcome);
      f.stability_trust_signal = trust.reference_d_auc_lo > 0 ?
        "The reference trust interval excludes zero: a small detectable gain." :
        "The reference trust interval includes zero: a gain is not clearly resolved.";
      f.stability_practical = s.runs.every(r => r.d_auc < margin.d_auc && r.d_log_loss_rel > -margin.rel_log_loss) ?
        "Neither AUC nor relative log-loss gains reach the analyst-set practical benchmarks in these runs." :
        "The practical verdict is mixed; inspect the full comparison.";
      f.stability_max_logloss = (100 * Math.max(...s.runs.map(r => Math.abs(r.d_log_loss_rel)))).toFixed(2) + "%";
      f.margin_logloss = (100 * margin.rel_log_loss).toFixed(0) + "%";
    }
    const def = A.modelDefaults(m);
    if (def) {
      f.model_outcome = (m.meta.outcomes && m.meta.outcomes[def.outcome]) || def.outcome;
      const rows = m.metrics.filter(r => r.outcome === def.outcome && r.feature_set === def.feature_set && r.scheme === def.scheme);
      const best = rows.filter(r => r.model !== "logit" && !/^(baseline|dummy)$|_recal$/.test(r.model)).sort((a, b) => b.auc - a.auc)[0];
      const baseline = best && best.model === "ensemble" ? "logit_recal" : "logit";
      const lg = rows.find(r => r.model === baseline) || rows.find(r => r.model === "logit");
      if (lg) f.auc_logit = lg.auc.toFixed(3);
      if (lg) f.baseline_model = A.modelName(lg.model);
      if (best) { f.auc_best = best.auc.toFixed(3); f.best_model = A.modelName(best.model); }
      const dv = best && m.diffs.find(r => r.outcome === def.outcome && r.feature_set === def.feature_set && r.scheme === def.scheme && r.model === best.model && (!r.vs || r.vs === baseline));
      if (dv && num(dv.d_auc) !== null) {
        const s = v => (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(3);
        f.d_auc = s(+dv.d_auc);
        if (num(dv.d_auc_lo) !== null) f.d_auc_ci = `[${s(+dv.d_auc_lo)}, ${s(+dv.d_auc_hi)}]`;
        if (dv.verdict) f.verdict = String(dv.verdict);
      }
      if (m.margin !== null) f.margin_auc = "+" + m.margin.toFixed(3);
      const sh = m.shap.filter(r => r.outcome === def.outcome && (r.model === (best ? best.model : "lgbm"))).sort((a, b) => b.mean_abs_shap - a.mean_abs_shap)[0];
      if (sh) f.top_driver = sh.label;
    }

    const s = d.segments;
    if (s.classes.length) { f.n_segments = String(s.classes.length); f.largest_segment = s.classes[0].label; f.largest_share = P(s.classes[0].share * 100); }
    const bk = s.baskets[s.baskets.length - 1];
    if (bk) {
      f.n_tools = String(bk.nodes.length); f.basket_label = bk.year ? String(bk.year) : bk.id;
      const top = bk.links.slice().sort((a, b) => b.lift - a.lift)[0];
      if (top) { f.top_pair = `${top.source} + ${top.target}`; f.top_lift = "×" + top.lift.toFixed(1); }
    }
    Object.keys(f).forEach(k => { if (f[k] === null || f[k] === undefined) delete f[k]; });
    return f;
  }

  A.modelName = m => ({ logit: "Logistic regression", logit_recal: "Calibrated logistic regression", lgbm: "Gradient boosting (LightGBM)", lgbm_recal: "LightGBM (recalibrated)", xgb: "Gradient boosting (XGBoost)", rf: "Random forest", ensemble: "Calibrated ensemble", dummy: "Base rate", baseline: "Base rate (no model)", gbm: "Gradient boosting", hgb: "Gradient boosting" }[m] || m);
  A.schemeName = s => {
    const m = String(s).match(/^temporal_(\d+)to(\d+)$/);
    if (m) { const yrs = t => t.match(/\d\d/g).map(y => "20" + y); const a = yrs(m[1]), b = yrs(m[2]); return `Train ${a[0]}–${a[a.length - 1].slice(2)} → test ${b.join(", ")}`; }
    if (/^groupcv_country$/.test(s)) return "Cross-validated by country";
    return String(s).replace(/_/g, " ");
  };
  A.modelDefaults = function (m) {
    if (!m || !m.metrics.length) return null;
    const outs = [...new Set(m.metrics.map(r => r.outcome))];
    const outcome = outs.includes("trust") ? "trust" : outs[0];
    const fsets = [...new Set(m.metrics.filter(r => r.outcome === outcome).map(r => r.feature_set))];
    const feature_set = fsets.includes("D") ? "D" : fsets[0];
    const schemes = [...new Set(m.metrics.filter(r => r.outcome === outcome).map(r => r.scheme))];
    const scheme = schemes.includes("temporal_2324to25") ? "temporal_2324to25" : schemes[0];
    return { outcome, feature_set, scheme };
  };

  /* ------------------------------ load ------------------------------------ */
  A.loadData = async function () {
    const status = {}, sources = {}, raw = {};
    let manifest = null;
    try {
      const r = await fetch("data/manifest.json", { cache: "no-cache" });
      if (r.ok) { const j = await r.json(); if (j && Array.isArray(j.files)) manifest = j.files.map(f => String(f).replace(/\.json$/, "")); }
    } catch (e) { /* no manifest: probe both locations */ }
    const results = await Promise.all(FILES.map(n => fetchJSON(n, manifest)));
    FILES.forEach((name, i) => {
      if (results[i]) { raw[name] = results[i].json; status[name] = "json"; sources[name] = results[i].from; }
      else if (A.params.get("demo") === "1") {
        raw[name] = DEV_FIXTURES[name]; status[name] = "fixture"; sources[name] = "DEV_FIXTURES";
      } else {
        throw new Error(`Missing ${name}.json. Results cannot be displayed. Serve the site over HTTP and copy all analysis exports first.`);
      }
    });
    const safe = (fn, name) => {
      try { return fn(raw[name]); }
      catch (e) {
        if (A.params.get("demo") !== "1") throw e;
        console.warn(`[atlas] could not normalise ${name}.json; using DEV_FIXTURES`, e);
        status[name] = "fixture"; sources[name] = "DEV_FIXTURES"; return fn(DEV_FIXTURES[name]);
      }
    };
    const tt = safe(normTrends, "trust_trends");
    let mo = safe(normModelling, "modelling");
    let sg = safe(normSegments, "segments");
    if (A.params.get("demo") !== "1" &&
        (!tt.trend.use?.length || !tt.trend.trust?.length || !tt.experience.rows.length ||
         !mo.metrics.length || !sg.classes.length || !sg.baskets.length)) {
      throw new Error("An analysis export is incomplete. No illustrative values will be substituted.");
    }
    if (A.params.get("demo") !== "1" &&
        (!tt.followup?.meta || tt.followup.population_flow?.length !== 4 ||
         tt.followup.source_audit?.files?.length !== 4 ||
         tt.followup.frequency_adjusted?.length !== 6 || tt.followup.frequency_contrasts?.length !== 2 ||
         !tt.followup.frequency_adjusted.every(r => Number.isFinite(r.adjusted_pct)) ||
         mo.stability?.summary?.length !== 2 || mo.stability.runs?.length !== 8 ||
         !mo.stability.summary.every(r => Number.isFinite(r.reference_d_auc)))) {
      throw new Error("The audited analytical follow-ups are incomplete. Results cannot be displayed.");
    }
    // A JSON that loads but lacks a section falls back per section (still flagged as fixture).
    const sectionStatus = { adoption: status.trust_trends, trend: status.trust_trends, experience: status.trust_trends, modelling: status.modelling, segments: status.segments, network: status.segments };
    if (!tt.trend.use || !tt.trend.use.length) { const f = normTrends(DEV_FIXTURES.trust_trends); tt.trend = Object.assign({}, f.trend, tt.trend); tt.trend.use = f.trend.use; tt.trend.plan = tt.trend.plan || f.trend.plan; sectionStatus.adoption = sectionStatus.trend = "fixture"; }
    if (!tt.trend.trust || !tt.trend.trust.length) { const f = normTrends(DEV_FIXTURES.trust_trends); tt.trend.trust = f.trend.trust; tt.trend.distrust = tt.trend.distrust || f.trend.distrust; sectionStatus.trend = "fixture"; }
    if (!tt.experience.rows.length) { tt.experience = normTrends(DEV_FIXTURES.trust_trends).experience; sectionStatus.experience = "fixture"; }
    if (!tt.sizes || !tt.sizes.length) tt.sizes = null;
    if (!mo.metrics.length) { mo = normModelling(DEV_FIXTURES.modelling); sectionStatus.modelling = "fixture"; }
    if (!sg.classes.length) { sg.classes = normSegments(DEV_FIXTURES.segments).classes; sectionStatus.segments = "fixture"; }
    if (!sg.baskets.length) { sg.baskets = normSegments(DEV_FIXTURES.segments).baskets; sectionStatus.network = "fixture"; }
    if (status.segments === "fixture") sg.status = "provisional";

    let sizes = tt.sizes;
    if (!sizes && mo.meta && Array.isArray(mo.meta.sample_sizes)) {
      const byYear = new Map(); mo.meta.sample_sizes.filter(r => r.outcome === "use").forEach(r => byYear.set(r.year, r.n)); sizes = [...byYear].map(([year, n]) => ({ year, n }));
    }
    const data = {
      status, sources, sectionStatus,
      anyFixture: Object.values(sectionStatus).some(s => s === "fixture"),
      trend: tt.trend, std: tt.std, experience: tt.experience, sizes: sizes || [], extras: tt.extras || {}, followup: tt.followup,
      modelling: mo, segments: sg,
      attribution: (mo.meta && mo.meta.attribution) || (tt.meta && tt.meta.attribution) || null
    };
    data.facts = deriveFacts(data);
    A.data = data;
    console.info("[atlas] data sources:", sources, "section status:", sectionStatus);
    return data;
  };
})();
