/* Chapter 2 — The trust paradox: dual line/area chart with CI ribbons, series
   break for 2026 and a draggable, keyboard-operable year scrubber. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});

  const SERIES = [
    { key: "use", label: "Use AI tools", pop: "professional respondents", cls: "s-use", on: true },
    { key: "trust", label: "Trust AI accuracy", pop: "professional AI users", cls: "s-trust", on: true },
    { key: "distrust", label: "Distrust accuracy", pop: "professional AI users", cls: "s-distrust", on: false },
    { key: "fav", label: "Favourable to AI", pop: "professional AI users", cls: "s-fav", on: false }
  ];

  A.initTrust = function () {
    const D = A.data, S = window.AtlasStory.ch2;
    const host = document.getElementById("trust-chart"), readout = document.getElementById("trust-readout");
    const ctlSeries = document.getElementById("trust-series"), ctlMode = document.getElementById("trust-mode");
    const series = SERIES.filter(s => D.trend[s.key] && D.trend[s.key].length);
    let mode = "raw", entered = false, active = 2025;
    const on = new Set(series.filter(s => s.on).map(s => s.key));

    ctlSeries.innerHTML = "";
    ctlSeries.setAttribute("role", "group"); ctlSeries.setAttribute("aria-label", "Series shown");
    series.forEach(s => {
      const b = document.createElement("button");
      b.type = "button"; b.className = "chip " + s.cls;
      b.innerHTML = `<span class="chip-swatch" aria-hidden="true"></span>${A.esc(s.label)} <small>${A.esc(s.pop)}</small>`;
      b.setAttribute("aria-pressed", String(on.has(s.key)));
      b.addEventListener("click", () => {
        if (on.has(s.key) && on.size > 1) on.delete(s.key); else on.add(s.key);
        b.setAttribute("aria-pressed", String(on.has(s.key)));
        render(false);
      });
      ctlSeries.appendChild(b);
    });
    if (D.std) {
      A.segmented(ctlMode, [{ value: "raw", label: "As reported" }, { value: "std", label: "Mix-adjusted" }], mode, v => { mode = v; render(false); }, "Estimate type");
    } else ctlMode.hidden = true;

    const getPts = key => (mode === "std" && D.std && D.std[key] ? D.std[key] : D.trend[key]) || [];

    function render(animate) {
      const narrow = A.isNarrow();
      const H = narrow ? 380 : 470;
      const { svg, width: W } = A.svgIn(host, H, { label: "Line chart of AI use and trust by survey year with 95% confidence ribbons. A data table follows." });
      svg.selectAll("*").remove();
      const m = { t: 40, r: narrow ? 26 : 150, b: 52, l: 40 };
      const vis = series.filter(s => on.has(s.key));
      const has26 = vis.some(s => getPts(s.key).some(p => p.series === "B"));
      const yearsA = [...new Set(vis.flatMap(s => getPts(s.key).filter(p => p.series === "A").map(p => p.year)))].sort();
      const innerW = W - m.l - m.r;
      const mainW = has26 ? innerW * (narrow ? 0.7 : 0.8) : innerW;
      const x = d3.scalePoint().domain(yearsA).range([m.l + 14, m.l + mainW]);
      const x26 = m.l + innerW - (narrow ? 6 : 0);
      const X = yr => (yr >= 2026 ? x26 : x(yr));
      const y = d3.scaleLinear().domain([0, 100]).range([H - m.b, m.t]);
      const years = has26 ? [...yearsA, 2026] : yearsA;
      if (!years.includes(active)) active = yearsA[yearsA.length - 1];
      const show = entered || A.reducedMotion();

      const defs = svg.append("defs");
      const clipRect = defs.append("clipPath").attr("id", "trust-clip").append("rect").attr("x", 0).attr("y", 0).attr("height", H).attr("width", show ? W : 0);
      const pat = defs.append("pattern").attr("id", "hatch").attr("patternUnits", "userSpaceOnUse").attr("width", 6).attr("height", 6).attr("patternTransform", "rotate(45)");
      pat.append("rect").attr("width", 6).attr("height", 6).attr("class", "hatch-bg");
      pat.append("line").attr("x1", 0).attr("y1", 0).attr("x2", 0).attr("y2", 6).attr("class", "hatch-line");

      const g = svg.append("g").attr("class", "grid");
      [0, 25, 50, 75, 100].forEach(v => {
        g.append("line").attr("class", "grid-line").attr("x1", m.l).attr("x2", W - m.r + (narrow ? 10 : 10)).attr("y1", y(v)).attr("y2", y(v));
        g.append("text").attr("class", "tick").attr("x", m.l - 8).attr("y", y(v) + 4).attr("text-anchor", "end").text(v + "%");
      });
      years.forEach(yr => svg.append("text").attr("class", "tick tick-year" + (yr === 2026 ? " is-b" : "")).attr("x", X(yr)).attr("y", H - m.b + 22).attr("text-anchor", "middle").text(yr));

      if (has26) {
        const bx = (x(yearsA[yearsA.length - 1]) + x26) / 2;
        const bg = svg.append("g").attr("class", "series-break");
        bg.append("line").attr("x1", bx).attr("x2", bx).attr("y1", m.t - 22).attr("y2", H - m.b + 6);
        bg.append("text").attr("x", bx).attr("y", m.t - 28).attr("text-anchor", "middle").text(window.AtlasStory.ch1.breakLabel);
      }

      const plot = svg.append("g").attr("clip-path", "url(#trust-clip)");
      const labels = [];
      vis.forEach(s => {
        const pts = getPts(s.key), pa = pts.filter(p => p.series === "A"), pb = pts.filter(p => p.series === "B");
        const sg = plot.append("g").attr("class", "series " + s.cls);
        if (pa.length > 1 && pa.every(p => p.lo !== null && p.hi !== null)) {
          sg.append("path").attr("class", "ribbon").attr("d", d3.area().x(p => x(p.year)).y0(p => y(p.lo)).y1(p => y(p.hi)).curve(d3.curveMonotoneX)(pa));
        }
        sg.append("path").attr("class", "line").attr("d", d3.line().x(p => x(p.year)).y(p => y(p.pct)).curve(d3.curveMonotoneX)(pa));
        sg.selectAll("circle.pt").data(pa).join("circle").attr("class", "pt").attr("cx", p => x(p.year)).attr("cy", p => y(p.pct)).attr("r", 4.5).attr("data-year", p => p.year);
        pb.forEach(p => {
          if (p.lo !== null) sg.append("line").attr("class", "whisker").attr("x1", x26).attr("x2", x26).attr("y1", y(p.lo)).attr("y2", y(p.hi));
          sg.append("circle").attr("class", "pt pt-b").attr("cx", x26).attr("cy", y(p.pct)).attr("r", 5.5).attr("data-year", 2026);
        });
        const last = pa[pa.length - 1];
        if (last) labels.push({ s, y: y(last.pct) });
      });
      if (!narrow) {
        labels.sort((a, b) => a.y - b.y);
        for (let i = 1; i < labels.length; i++) if (labels[i].y - labels[i - 1].y < 34) labels[i].y = labels[i - 1].y + 34;
        const lx = has26 ? x26 + 16 : m.l + innerW + 12;
        const lab = svg.append("g").attr("class", "end-labels").style("opacity", show ? 1 : 0);
        labels.forEach(l => {
          const t = lab.append("text").attr("class", "end-label " + l.s.cls).attr("x", lx).attr("y", l.y);
          t.append("tspan").attr("class", "end-name").text(l.s.label);
          t.append("tspan").attr("x", lx).attr("dy", 15).attr("class", "end-pop").text(l.s.pop);
        });
        if (has26) lab.selectAll("text").attr("transform", null);
      }

      const scrub = svg.append("g").attr("class", "scrubber").style("opacity", show ? 1 : 0);
      const sLine = scrub.append("line").attr("y1", m.t - 6).attr("y2", H - m.b);
      const chip = scrub.append("g").attr("class", "scrub-chip");
      chip.append("rect").attr("x", -26).attr("y", H - m.b + 6).attr("width", 52).attr("height", 24).attr("rx", 12);
      const chipT = chip.append("text").attr("y", H - m.b + 22).attr("text-anchor", "middle");
      const overlay = svg.append("rect").attr("class", "scrub-overlay").attr("x", m.l).attr("y", m.t - 20).attr("width", innerW + 10).attr("height", H - m.b - m.t + 40);
      const handle = svg.append("circle").attr("class", "scrub-handle").attr("r", 10).attr("cy", m.t - 6)
        .attr("tabindex", 0).attr("role", "slider").attr("aria-label", "Year scrubber: use arrow keys to change year")
        .attr("aria-valuemin", years[0]).attr("aria-valuemax", years[years.length - 1]).style("opacity", show ? 1 : 0);

      const nearest = px => years.reduce((b, yr) => (Math.abs(X(yr) - px) < Math.abs(X(b) - px) ? yr : b), years[0]);
      function place(px, yr, smooth) {
        const T = sel => (smooth && !A.reducedMotion() ? sel.transition().duration(260).ease(d3.easeCubicOut) : sel);
        T(sLine).attr("x1", px).attr("x2", px);
        T(handle).attr("cx", px);
        T(chip).attr("transform", `translate(${px},0)`);
        chipT.text(yr);
        if (yr !== active || !readout.dataset.ready) { active = yr; updateReadout(); }
        plot.selectAll("circle.pt").classed("is-active", function () { return +this.dataset.year === active; });
      }
      function updateReadout() {
        readout.dataset.ready = "1";
        const isB = active >= 2026;
        const rows = vis.map(s => {
          const p = getPts(s.key).find(q => q.year === active);
          if (!p) return `<div class="ro-row ${s.cls} is-na"><span class="chip-swatch"></span><div><span class="ro-label">${A.esc(s.label)} <small>${A.esc(s.pop)}</small></span><span class="ro-val">n/a</span><span class="ro-ci">${isB ? A.esc(S.breakNote) : "not asked or not comparable"}</span></div></div>`;
          return `<div class="ro-row ${s.cls}"><span class="chip-swatch"></span><div><span class="ro-label">${A.esc(s.label)} <small>${A.esc(s.pop)}</small></span><span class="ro-val">${A.fmtPct(p.pct)}</span><span class="ro-ci">${p.lo !== null ? "95% CI " + A.fmtCI(p.lo, p.hi) + "%" : ""}${p.n ? " · n = " + p.n.toLocaleString("en-GB") : ""}</span></div></div>`;
        }).join("");
        readout.innerHTML = `<div class="ro-year">${active}${isB ? ' <span class="ro-b">new series</span>' : ""}</div>${rows}<p class="small muted">Use and attitudes have different denominators. Their vertical distance is not a percentage of developers.</p>`;
        handle.attr("aria-valuenow", active).attr("aria-valuetext", `${active}: ` + vis.map(s => { const p = getPts(s.key).find(q => q.year === active); return `${s.label} ${p ? A.fmtPct(p.pct) : "not available"}`; }).join(", "));
      }
      const drag = d3.drag().container(svg.node())
        .on("start drag", ev => { const px = A.clamp(ev.x, X(years[0]), X(years[years.length - 1])); place(px, nearest(px), false); svg.classed("is-dragging", true); })
        .on("end", ev => { const yr = nearest(ev.x); place(X(yr), yr, true); svg.classed("is-dragging", false); });
      overlay.call(drag); handle.call(drag);
      handle.on("keydown", ev => {
        const i = years.indexOf(active); let j = i;
        if (ev.key === "ArrowRight" || ev.key === "ArrowUp") j = Math.min(years.length - 1, i + 1);
        else if (ev.key === "ArrowLeft" || ev.key === "ArrowDown") j = Math.max(0, i - 1);
        else if (ev.key === "Home") j = 0; else if (ev.key === "End") j = years.length - 1; else return;
        ev.preventDefault(); place(X(years[j]), years[j], true);
      });
      delete readout.dataset.ready;
      place(X(active), active, false);

      if (animate && !show) {
        entered = true;
        clipRect.transition().duration(1800).ease(d3.easeCubicInOut).attr("width", W)
          .on("end", () => { scrub.transition().duration(400).style("opacity", 1); handle.transition().duration(400).style("opacity", 1); svg.select(".end-labels").transition().duration(400).style("opacity", 1); });
      }

      const tYears = [...new Set(series.flatMap(s => getPts(s.key).map(p => p.year)))].sort();
      A.srTable(document.getElementById("trust-table"), `AI use and sentiment by year (${mode === "std" ? "mix-adjusted" : "as reported"}), percent with 95% CI`, ["Series", ...tYears.map(String)],
        series.map(s => [s.label + " (" + s.pop + ")", ...tYears.map(yr => { const p = getPts(s.key).find(q => q.year === yr); return p ? `${A.fmtPct(p.pct, 1)} [${A.fmtCI(p.lo, p.hi)}]${p.series === "B" ? " (new series)" : ""}` : "n/a"; })]));
    }

    render(false);
    A.onVisible(host, () => render(true), 0.3);
    let lastW = host.clientWidth;
    window.addEventListener("resize", A.debounce(() => { if (host.clientWidth !== lastW) { lastW = host.clientWidth; render(false); } }, 200));
    return { render: () => render(false) };
  };
})();
