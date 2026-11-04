/* AI Adoption Atlas — bootstrap: copy, theme, scroll orchestration, nav. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});
  const STORY = window.AtlasStory;
  const root = document.documentElement;

  /* ---------------- theme ---------------- */
  function initTheme() {
    const btn = document.getElementById("theme-toggle");
    const set = t => {
      root.setAttribute("data-theme", t);
      btn.setAttribute("aria-pressed", String(t === "dark"));
      btn.querySelector("span").textContent = t === "dark" ? "Light" : "Dark";
      if (A.field) A.field.setTheme();
    };
    set(root.getAttribute("data-theme") || "light");
    btn.addEventListener("click", () => {
      const t = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      try { localStorage.setItem("atlas-theme", t); } catch (e) { /* private mode */ }
      set(t);
    });
  }

  /* ---------------- copy ---------------- */
  function fillCopy(facts) {
    document.querySelectorAll("[data-copy]").forEach(el => {
      const tpl = A.get(STORY, el.dataset.copy);
      if (typeof tpl === "string") el.innerHTML = A.fill(tpl, facts);
    });
    // nav labels
    document.querySelectorAll(".chapter-nav a").forEach((a, i) => { const l = a.querySelector(".nav-label"); if (l && STORY.nav[i]) l.textContent = STORY.nav[i]; });
    // caveats + method
    document.getElementById("caveats").innerHTML = STORY.ch7.caveats.map((c, i) =>
      `<article class="caveat reveal-up"><span class="caveat-n">${String(i + 1).padStart(2, "0")}</span><h3>${c.h}</h3><p>${A.fill(c.p, facts)}</p></article>`).join("");
    document.getElementById("method-list").innerHTML = STORY.ch7.method.map(m => `<li>${m}</li>`).join("");
    const L = STORY.meta.links;
    document.querySelectorAll("[data-link]").forEach(a => { const u = L[a.dataset.link]; if (u) a.href = u; });
  }

  function initFollowups() {
    const D = A.data, f = D.followup, stability = D.modelling.stability;
    if (!f || !stability) {
      ["panel-frequency", "panel-stability", "panel-source-audit"].forEach(id => {
        document.getElementById(id).hidden = true;
      });
      return;
    }
    const n = v => v == null ? "n/a" : (+v).toLocaleString("en-GB");
    const delta = v => (v >= 0 ? "+" : "") + (+v).toFixed(4);
    const primary = f.frequency_adjusted.filter(r => r.analysis === f.frequency_contrasts[0].analysis);
    A.srTable(document.getElementById("frequency-table"),
      "Accuracy trust among observed 2025 professional AI users, raw and standardised to the same covariate mix",
      ["Frequency", "n", "Raw trust", "Raw 95% CI", "Adjusted trust", "Model-based 95% interval"],
      primary.map(r => {
        const raw = f.frequency_raw.find(v => v.ai_use_freq === r.frequency);
        return [r.frequency, n(raw.n), A.fmtPct(raw.pct, 1), A.fmtCI(raw.lo, raw.hi) + "%",
          A.fmtPct(r.adjusted_pct, 1), A.fmtCI(r.lo, r.hi) + "%"];
      }));
    A.srTable(document.getElementById("population-table"),
      "Distinct respondent counts by year and analysis stage; not a longitudinal panel",
      ["Year", "Eligible adult professionals", "Answered AI status", "Missing AI status", "Current AI users", "Trust answered (users)", "Missing trust (users)", "AI completion"],
      f.population_flow.map(r => [r.year, n(r.eligible_professionals), n(r.answered_ai_status),
        n(r.missing_ai_status), n(r.current_ai_users), n(r.trust_answered_users),
        n(r.trust_missing_users), A.fmtPct(r.completion_pct, 1)]));
    A.srTable(document.getElementById("source-table"), "Local public archive files, matched to pinned upstream Git LFS hashes",
      ["Year", "All archive responses", "Columns", "SHA-256 prefix", "Match"],
      f.source_audit.files.map(r => [r.year, n(r.rows), r.columns, r.sha256.slice(0, 12), r.upstream_match ? "Verified" : "Unverified"]));
    const pin = document.getElementById("source-pin");
    pin.textContent = f.source_audit.upstream_commit.slice(0, 12);
    pin.href = "https://github.com/StackExchange/Survey/tree/" + f.source_audit.upstream_commit;
    A.srTable(document.getElementById("stability-table"),
      "Full-base context-only calibrated ensemble minus calibrated logistic; ranges across four runs are descriptive",
      ["Outcome", "2025 test n", "Reference ΔAUC", "Conditional 95% CI", "ΔAUC range across runs"],
      stability.summary.map(r => [r.outcome === "trust" ? "Accuracy trust" : "Favourability",
        n(r.n_test), delta(r.reference_d_auc), `[${delta(r.reference_d_auc_lo)}, ${delta(r.reference_d_auc_hi)}]`,
        `[${delta(r.d_auc_min)}, ${delta(r.d_auc_max)}]`]));
  }

  /* ---------------- fixture badge ---------------- */
  function initBadge() {
    const D = A.data, pill = document.getElementById("fixture-badge");
    if (!D.anyFixture) return;
    const which = Object.entries(D.sectionStatus).filter(([, s]) => s === "fixture").map(([k]) => k);
    pill.hidden = false;
    pill.querySelector(".fb-text").textContent = STORY.badges.fixture;
    pill.title = STORY.badges.fixtureLong + " Affected: " + which.join(", ");
    pill.querySelector(".fb-detail").textContent = "Fixtures in: " + which.join(", ");
    root.classList.add("has-fixtures");
    const map = { adoption: "panel-adoption", trend: "panel-trust", experience: "panel-exp", segments: "panel-seg", modelling: "panel-models", network: "panel-net" };
    Object.entries(map).forEach(([k, id]) => A.markFixture(document.getElementById(id), k));
  }

  /* ---------------- adoption scrolly (ch0–1) ---------------- */
  function initScrolly() {
    const D = A.data, use = D.trend.use || [], plan = D.trend.plan || [];
    const shares = {};
    use.forEach(p => { const pl = plan.find(q => q.year === p.year); shares[p.year] = { use: p.pct / 100, plan: pl ? pl.pct / 100 : 0, series: p.series }; });
    const stage = document.getElementById("stage"), canvas = document.getElementById("field");
    const steps = [...document.querySelectorAll(".step[data-year]")];
    // fill each step's copy with its own year's numbers
    steps.forEach(st => {
      const yr = +st.dataset.year, s = shares[yr];
      const loc = Object.assign({}, D.facts, { year: String(yr), use: s ? Math.round(s.use * 100) + "%" : null, plan: s && s.plan ? Math.round(s.plan * 100) + "%" : null });
      const c = STORY.ch1.steps[yr];
      if (!c || !s) { st.hidden = true; return; }
      st.querySelector(".step-title").innerHTML = A.fill(c.title, loc);
      st.querySelector(".step-body").innerHTML = A.fill(c.body, loc);
      st.querySelector(".step-stat").innerHTML = `<strong>${A.fmtPct(s.use * 100)}</strong><span>${A.esc(STORY.ch1.statLabel || STORY.ch1.legend.use)}${s.series === "B" ? " · new series" : ""}</span>`;
    });
    // year ticker + legend
    const ticker = document.getElementById("year-ticker");
    const years = Object.keys(shares).map(Number).sort();
    ticker.innerHTML = years.map((y, i) => `${i && shares[y].series !== shares[years[i - 1]].series ? '<span class="tick-break" aria-hidden="true">⫽</span>' : ""}<button type="button" class="yt" data-year="${y}" aria-pressed="false">${y}</button>`).join("");
    ticker.querySelectorAll(".yt").forEach(b => b.addEventListener("click", () => {
      const st = steps.find(s => +s.dataset.year === +b.dataset.year);
      if (st) st.scrollIntoView({ behavior: A.reducedMotion() ? "auto" : "smooth", block: "center" });
    }));
    const lg = STORY.ch1.legend;
    const legendEl = document.getElementById("stage-legend");
    const setLegend = yr => {
      const s = shares[yr];
      legendEl.innerHTML = s ? `<span class="lg use"><i></i>${A.esc(lg.use)} <b>${A.fmtPct(s.use * 100)}</b></span>` +
        (s.plan ? `<span class="lg plan"><i></i>${A.esc(lg.plan)} <b>${A.fmtPct(s.plan * 100)}</b></span>` : "") +
        `<span class="lg none"><i></i>${A.esc(lg.none)}</span>` + (s.series === "B" ? `<span class="lg ring"><i></i>${A.esc(lg.newSeries)}</span>` : "") : "";
      ticker.querySelectorAll(".yt").forEach(b => b.setAttribute("aria-pressed", String(+b.dataset.year === yr)));
      canvas.setAttribute("aria-label", s ? A.fill(STORY.ch1.canvasLabel, { year: String(yr), use: A.fmtPct(s.use * 100), plan: A.fmtPct(s.plan * 100) }).replace(/<[^>]+>/g, "") : "Animated field of dots representing developers.");
      stage.classList.toggle("is-break", !!(s && s.series === "B"));
    };
    A.field = new A.Field(canvas, stage, shares);
    A.srTable(document.getElementById("adoption-table"), "Share of developers using or planning to use AI tools, by year (percent)", ["Year", "Use AI", "Plan to", "Series"],
      years.map(y => [String(y), A.fmtPct(shares[y].use * 100, 1), shares[y].plan ? A.fmtPct(shares[y].plan * 100, 1) : "n/a", shares[y].series === "B" ? "B (redesigned)" : "A"]));

    let curYear = null;
    A.updateScrolly = function () {
      const vh = window.innerHeight;
      const first = steps.find(s => !s.hidden);
      if (!first) return;
      const r = first.getBoundingClientRect();
      // morph runs while the first year step travels from the bottom to the middle of the viewport
      const t = A.clamp((vh - r.top) / (vh * 0.6), 0, 1);
      A.field.setMorph(t);
      let active = null;
      steps.forEach(s => { if (s.hidden) return; const rr = s.getBoundingClientRect(); if (rr.top < vh * 0.62) active = +s.dataset.year; });
      stage.classList.toggle("is-grid", t >= 0.5);
      if (active === null) active = +first.dataset.year;
      if (active !== curYear) { curYear = active; A.field.setYear(active); setLegend(active); steps.forEach(s => s.classList.toggle("is-active", +s.dataset.year === active)); }
    };
    window.addEventListener("resize", A.debounce(() => A.field.resize(false), 200));
  }

  /* ---------------- nav + progress ---------------- */
  function initNav() {
    const links = [...document.querySelectorAll(".chapter-nav a")];
    const secs = links.map(a => document.querySelector(a.getAttribute("href")));
    const bar = document.getElementById("progress-bar"), current = document.getElementById("nav-current");
    let ticking = false;
    const update = () => {
      ticking = false;
      const y = window.scrollY, vh = window.innerHeight, docH = document.documentElement.scrollHeight - vh;
      bar.style.transform = `scaleX(${docH > 0 ? A.clamp(y / docH, 0, 1) : 0})`;
      let idx = 0;
      secs.forEach((s, i) => { if (s && s.getBoundingClientRect().top < vh * 0.45) idx = i; });
      links.forEach((a, i) => {
        if (i === idx) a.setAttribute("aria-current", "location"); else a.removeAttribute("aria-current");
        const s = secs[i]; if (!s) return;
        const r = s.getBoundingClientRect(), end = secs[i + 1] ? secs[i + 1].getBoundingClientRect().top : r.bottom;
        const p = A.clamp((vh * 0.45 - r.top) / Math.max(1, end - r.top), 0, 1);
        a.style.setProperty("--p", p.toFixed(3));
      });
      current.textContent = `${String(idx).padStart(2, "0")} · ${STORY.nav[idx] || ""}`;
      if (A.updateScrolly) A.updateScrolly();
    };
    window.addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    window.addEventListener("resize", () => requestAnimationFrame(update));
    update();
    A.updateNav = update;
  }

  /* ---------------- reveal-on-scroll ---------------- */
  function initReveals() {
    const els = document.querySelectorAll(".reveal-up");
    if (A.reducedMotion() || !("IntersectionObserver" in window)) { els.forEach(e => e.classList.add("is-in")); return; }
    const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); } }), { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
    els.forEach(e => io.observe(e));
  }

  /* ---------------- debug: ?chapter=n / ?step=YYYY ---------------- */
  function jumpFromParams() {
    const p = A.params, ch = p.get("chapter"), step = p.get("step");
    let target = null;
    if (step) target = document.querySelector(`.step[data-year="${step}"]`);
    else if (ch !== null) target = document.getElementById("ch" + ch);
    else if (location.hash) target = document.querySelector(location.hash);
    if (!target) return;
    const go = () => {
      const block = target.classList.contains("step") ? "center" : "start";
      const top = target.getBoundingClientRect().top + window.scrollY - (block === "center" ? (window.innerHeight - target.offsetHeight) / 2 : 0);
      window.scrollTo(0, Math.max(0, top - (block === "start" ? 0 : 0)));
      if (A.updateNav) A.updateNav();
    };
    go(); requestAnimationFrame(go); setTimeout(go, 400);
  }

  /* ---------------- boot ---------------- */
  async function boot() {
    if (A.reducedMotion()) root.classList.add("reduced-motion");
    initTheme();
    const D = await A.loadData();
    fillCopy(D.facts);
    initFollowups();
    const meta = D.modelling.meta;
    document.getElementById("modelling-scope").textContent =
      meta.analysis_note || "Exploratory model comparison. Sample sizes and computational budget are documented in the repository.";
    const segments = D.segments.meta;
    document.getElementById("segments-scope").textContent = segments.n_lca ?
      `${segments.n_lca.toLocaleString("en-GB")} complete-case 2025 AI users, all developer statuses. Four attitude indicators; exploratory profiles, not fixed types of people. No class-share confidence intervals; limited stability refits. Full selection details are in the repository.` :
      segments.population || "Exploratory within-year profiles, not fixed types of people.";
    initBadge();
    const safe = (name, fn) => { try { fn(); } catch (e) { console.error(`[atlas] ${name} failed`, e); } };
    safe("scrolly", initScrolly);
    safe("trust", A.initTrust);
    safe("experience", A.initExperience);
    safe("segments", A.initSegments);
    safe("models", A.initModels);
    safe("network", A.initNetwork);
    initReveals();
    initNav();
    root.classList.add("is-ready");
    jumpFromParams();
    window.addEventListener("keydown", e => { if (e.key === "Escape") A.tip.hide(); });
    window.addEventListener("beforeprint", () => { root.classList.add("is-printing"); document.querySelectorAll(".reveal-up").forEach(e => e.classList.add("is-in")); });
  }
  function start() {
    boot().catch(error => {
      console.error("[atlas] Results unavailable", error);
      const notice = document.createElement("p");
      notice.className = "load-error";
      notice.setAttribute("role", "alert");
      notice.textContent = "Results unavailable: " + error.message;
      document.getElementById("main").replaceChildren(notice);
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
})();
