/* AI Adoption Atlas — shared helpers (no numbers live here). */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});
  const params = new URLSearchParams(location.search);
  A.params = params;

  A.reducedMotion = () => params.get("motion") === "reduce" || window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  A.css = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  A.isNarrow = () => window.innerWidth < 760;

  A.esc = s => String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const warned = new Set();
  /** Fill {{placeholders}} from facts. Values are escaped; template HTML is trusted (story.js). */
  A.fill = function (tpl, facts) {
    if (tpl === undefined || tpl === null) return "";
    return String(tpl).replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, k) => {
      const v = facts ? facts[k] : undefined;
      if (v === undefined || v === null || v === "") {
        if (!warned.has(k)) { warned.add(k); console.warn(`[atlas] missing story fact: {{${k}}}`); }
        return '<span class="missing" title="value not available yet">—</span>';
      }
      return A.esc(v);
    });
  };
  A.get = (obj, path) => path.split(".").reduce((o, k) => (o == null ? undefined : o[k]), obj);

  A.fmtPct = (v, d = 0) => (v === null || v === undefined || isNaN(v) ? "—" : (+v).toFixed(d) + "%");
  A.fmtPP = v => (v === null || v === undefined || isNaN(v) ? "—" : (v > 0 ? "+" : v < 0 ? "−" : "±") + Math.abs(v).toFixed(0) + " pp");
  A.fmtCI = (lo, hi, d = 1) => (lo === null || hi === null || lo === undefined || hi === undefined ? "" : `${(+lo).toFixed(d)}–${(+hi).toFixed(d)}`);

  A.debounce = (fn, ms = 150) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
  A.clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  A.lerp = (a, b, t) => a + (b - a) * t;
  A.ease = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  A.dur = ms => (A.reducedMotion() ? 0 : ms);

  /** Run cb the first time el enters the viewport (immediately when reduced motion / no IO). */
  A.onVisible = function (el, cb, threshold = 0.18) {
    if (!("IntersectionObserver" in window)) { cb(); return; }
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => { if (e.isIntersecting) { io.disconnect(); cb(); } });
    }, { threshold });
    io.observe(el);
  };
  /** Call cb(true/false) as el enters/leaves (used to pause animations). */
  A.watchVisibility = function (el, cb) {
    if (!("IntersectionObserver" in window)) { cb(true); return; }
    new IntersectionObserver(es => es.forEach(e => cb(e.isIntersecting)), { rootMargin: "100px" }).observe(el);
  };

  /* ---------- tooltip ---------- */
  let tipEl;
  A.tip = {
    show(html, ev) {
      tipEl = tipEl || document.getElementById("tooltip");
      tipEl.innerHTML = html; tipEl.hidden = false;
      A.tip.move(ev);
    },
    move(ev) {
      if (!tipEl || tipEl.hidden) return;
      let x, y;
      if (ev && ev.clientX !== undefined) { x = ev.clientX; y = ev.clientY; }
      else if (ev && ev.target && ev.target.getBoundingClientRect) { const r = ev.target.getBoundingClientRect(); x = r.left + r.width / 2; y = r.top; }
      else return;
      const w = tipEl.offsetWidth, h = tipEl.offsetHeight;
      const left = A.clamp(x + 16, 8, window.innerWidth - w - 8);
      const top = y + h + 24 > window.innerHeight ? y - h - 12 : y + 18;
      tipEl.style.left = left + "px"; tipEl.style.top = Math.max(8, top) + "px";
    },
    hide() { if (tipEl) tipEl.hidden = true; }
  };

  /* ---------- fixture badges ---------- */
  A.markFixture = function (panel, sectionKey) {
    if (!panel || !A.data || A.data.sectionStatus[sectionKey] !== "fixture") return;
    if (panel.querySelector(":scope > .chart-badge")) return;
    const b = document.createElement("div");
    b.className = "chart-badge";
    b.setAttribute("role", "note");
    b.innerHTML = `<span aria-hidden="true">◇</span> ${A.esc(window.AtlasStory.badges.chartFixture)}`;
    b.title = window.AtlasStory.badges.fixtureLong;
    panel.prepend(b);
    panel.classList.add("is-fixture");
  };

  /* ---------- accessible data tables ---------- */
  A.srTable = function (host, caption, columns, rows) {
    if (!host) return;
    host.innerHTML = "";
    const t = document.createElement("table");
    t.className = "data-table";
    t.innerHTML = `<caption>${A.esc(caption)}</caption><thead><tr>${columns.map(c => `<th scope="col">${A.esc(c)}</th>`).join("")}</tr></thead>` +
      `<tbody>${rows.map(r => `<tr>${r.map(v => `<td>${A.esc(v ?? "—")}</td>`).join("")}</tr>`).join("")}</tbody>`;
    host.appendChild(t);
  };

  /* ---------- small DOM helpers ---------- */
  A.segmented = function (host, options, current, onChange, label) {
    host.innerHTML = "";
    host.setAttribute("role", "group");
    if (label) host.setAttribute("aria-label", label);
    options.forEach(o => {
      const b = document.createElement("button");
      b.type = "button"; b.className = "seg-btn"; b.dataset.value = o.value;
      b.innerHTML = o.html || A.esc(o.label);
      b.setAttribute("aria-pressed", String(o.value === current));
      b.addEventListener("click", () => {
        host.querySelectorAll(".seg-btn").forEach(x => x.setAttribute("aria-pressed", String(x === b)));
        onChange(o.value);
      });
      host.appendChild(b);
    });
  };

  /** Responsive SVG: returns {svg, width, height} sized to host width. */
  A.svgIn = function (host, height, opts = {}) {
    const width = Math.max(opts.minWidth || 280, Math.floor(host.clientWidth || 640));
    const svg = d3.select(host).selectAll("svg.chart").data([0]).join("svg").attr("class", "chart")
      .attr("viewBox", `0 0 ${width} ${height}`).attr("width", width).attr("height", height)
      .attr("role", "img");
    if (opts.label) svg.attr("aria-label", opts.label);
    return { svg, width, height };
  };

  A.palette = () => ({
    use: A.css("--c-use"), plan: A.css("--c-plan"), trust: A.css("--c-trust"), distrust: A.css("--c-distrust"),
    fav: A.css("--c-fav"), none: A.css("--c-none"), ink: A.css("--cp-text"), muted: A.css("--cp-text-muted"),
    cat: [1, 2, 3, 4, 5, 6, 7].map(i => A.css(`--c-cat${i}`))
  });
})();
