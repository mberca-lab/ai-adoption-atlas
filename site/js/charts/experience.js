/* Chapter 3 — The experience gradient: dot-matrix (10×10 waffles) by years of
   coding × survey year, with a ridgeline of each band's trajectory. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});
  const LABEL = { trust: "Trust accuracy", distrust: "Distrust accuracy", fav: "Favourable" };
  const CLS = { trust: "s-trust", distrust: "s-distrust", fav: "s-fav" };

  A.initExperience = function () {
    const D = A.data.experience, S = window.AtlasStory.ch3;
    const host = document.getElementById("exp-chart"), ctl = document.getElementById("exp-outcome"), note = document.getElementById("exp-note");
    const outcomes = Object.keys(LABEL).filter(o => D.rows.some(r => r.outcome === o));
    let outcome = outcomes.includes("trust") ? "trust" : outcomes[0], entered = false;
    A.segmented(ctl, outcomes.map(o => ({ value: o, label: LABEL[o] })), outcome, v => { outcome = v; entered = false; render(true); }, "Outcome");

    function render(animate) {
      const rows = D.rows.filter(r => r.outcome === outcome);
      const years = [...new Set(rows.map(r => r.year))].sort();
      const bands = D.bands.filter(b => rows.some(r => r.band === b));
      const Wh = host.clientWidth || 800, narrow = Wh < 760;
      const labelW = narrow ? 64 : 120, gap = narrow ? 10 : 22;
      const ridgeMin = Wh >= 980 ? 300 : 0;
      const cell = Math.min(124, Math.floor((Wh - labelW - ridgeMin - (ridgeMin ? 56 : 0) - gap * (years.length - 1)) / years.length));
      // the ridgeline takes whatever width the capped dot matrix leaves free
      const ridgeW = ridgeMin ? Math.max(ridgeMin, Math.min(520, Wh - labelW - years.length * cell - gap * (years.length - 1) - 72)) : 0;
      const rowH = cell + (narrow ? 40 : 46), top = 34;
      const H = top + bands.length * rowH + 6;
      const { svg, width: W } = A.svgIn(host, H, { label: `Dot matrix: share of AI users who ${LABEL[outcome].toLowerCase()} by years of coding experience and year. A data table follows.` });
      svg.selectAll("*").remove();
      svg.attr("class", "chart " + CLS[outcome]);
      const cx = i => labelW + i * (cell + gap);
      years.forEach((yr, i) => svg.append("text").attr("class", "col-head").attr("x", cx(i) + cell / 2).attr("y", 16).attr("text-anchor", "middle").text(yr));
      const pitch = cell / 10, r = pitch * 0.34;
      const show = entered || A.reducedMotion() || !animate;
      bands.forEach((b, bi) => {
        const y0 = top + bi * rowH;
        const lab = svg.append("text").attr("class", "row-head").attr("x", 0).attr("y", y0 + cell / 2 - 4);
        lab.append("tspan").text(b.replace(/\s*yrs?$/, ""));
        lab.append("tspan").attr("x", 0).attr("dy", 16).attr("class", "row-sub").text("yrs coding");
        years.forEach((yr, yi) => {
          const d = rows.find(r => r.band === b && r.year === yr);
          const g = svg.append("g").attr("class", "waffle").attr("transform", `translate(${cx(yi)},${y0})`)
            .attr("tabindex", 0).attr("role", "img")
            .attr("aria-label", d ? `${b}, ${yr}: ${A.fmtPct(d.pct)} ${LABEL[outcome].toLowerCase()}${d.lo !== null ? ", 95% CI " + A.fmtCI(d.lo, d.hi) + "%" : ""}` : `${b}, ${yr}: no data`);
          g.append("rect").attr("class", "waffle-hit").attr("x", -4).attr("y", -4).attr("width", cell + 8).attr("height", cell + 30).attr("rx", 8);
          const k = d ? Math.round(d.pct) : 0;
          const dots = d3.range(100).map(i => ({ i, c: i % 10, r: 9 - Math.floor(i / 10), on: i < k }));
          g.selectAll("circle").data(dots).join("circle")
            .attr("cx", q => q.c * pitch + pitch / 2).attr("cy", q => q.r * pitch + pitch / 2).attr("r", r)
            .attr("class", q => "dot" + (q.on ? " on" : ""))
            .style("opacity", q => (q.on && !show ? 0 : null))
            .call(sel => { if (!show) sel.filter(q => q.on).transition().delay(q => yi * 120 + bi * 90 + q.i * 7).duration(220).style("opacity", 1); });
          if (d) {
            g.append("text").attr("class", "cell-val").attr("x", 0).attr("y", cell + 19).text(A.fmtPct(d.pct));
            if (d.lo !== null && !narrow) g.append("text").attr("class", "cell-ci").attr("x", cell).attr("y", cell + 19).attr("text-anchor", "end").text(A.fmtCI(d.lo, d.hi, 0));
          }
          g.on("pointerenter focus", ev => d && A.tip.show(`<strong>${A.esc(b)} · ${yr}</strong><br>${A.esc(LABEL[outcome])}: <b>${A.fmtPct(d.pct, 1)}</b>${d.lo !== null ? `<br><span class="muted">95% CI ${A.fmtCI(d.lo, d.hi)}%</span>` : ""}${d.n ? `<br><span class="muted">n = ${d.n.toLocaleString("en-GB")}</span>` : ""}`, ev))
            .on("pointermove", ev => A.tip.move(ev)).on("pointerleave blur", () => A.tip.hide());
        });
      });

      // ridgeline
      if (ridgeW) {
        const rx0 = W - ridgeW, x = d3.scalePoint().domain(years).range([rx0 + 10, W - 50]);
        const hScale = d3.scaleLinear().domain([0, 100]).range([0, rowH * 1.25]);
        svg.append("text").attr("class", "col-head").attr("x", rx0 + 10).attr("y", 16).text("Trajectory by band");
        const rg = svg.append("g").attr("class", "ridges");
        bands.forEach((b, bi) => {
          const pts = years.map(yr => rows.find(r => r.band === b && r.year === yr)).filter(Boolean);
          const base = top + bi * rowH + cell;
          const op = 0.25 + 0.6 * (bi / Math.max(1, bands.length - 1));
          const area = d3.area().x(p => x(p.year)).y0(base).y1(p => base - hScale(p.pct)).curve(d3.curveMonotoneX);
          const line = d3.line().x(p => x(p.year)).y(p => base - hScale(p.pct)).curve(d3.curveMonotoneX);
          const gg = rg.append("g").attr("class", "ridge");
          gg.append("path").attr("class", "ridge-area").attr("d", area(pts)).style("fill-opacity", op);
          const ln = gg.append("path").attr("class", "ridge-line").attr("d", line(pts));
          gg.append("line").attr("class", "ridge-base").attr("x1", rx0 + 10).attr("x2", W - 50).attr("y1", base).attr("y2", base);
          const last = pts[pts.length - 1];
          if (last) gg.append("text").attr("class", "ridge-val").attr("x", W - 44).attr("y", base - hScale(last.pct) + 4).text(A.fmtPct(last.pct));
          if (!show) { const L = ln.node().getTotalLength(); ln.attr("stroke-dasharray", L).attr("stroke-dashoffset", L).transition().delay(300 + bi * 160).duration(900).attr("stroke-dashoffset", 0); }
        });
        years.forEach(yr => rg.append("text").attr("class", "tick").attr("x", x(yr)).attr("y", H - 2).attr("text-anchor", "middle").text(yr));
      }
      if (animate) entered = true;

      // gradient annotation (numbers from data, words from story.js)
      const young = bands[0], old = bands[bands.length - 1];
      const gapAt = yr => { const a = rows.find(r => r.band === old && r.year === yr), b = rows.find(r => r.band === young && r.year === yr); return a && b ? a.pct - b.pct : null; };
      note.innerHTML = years.map(yr => `<span>${A.fill(S.gapLabel, { old, young, year: String(yr), gap: A.fmtPP(gapAt(yr)) })}</span>`).join("");

      A.srTable(document.getElementById("exp-table"), `${LABEL[outcome]} among AI users, by years of coding (percent, 95% CI)`, ["Years coding", ...years.map(String)],
        bands.map(b => [b, ...years.map(yr => { const d = rows.find(r => r.band === b && r.year === yr); return d ? `${A.fmtPct(d.pct, 1)} [${A.fmtCI(d.lo, d.hi)}]` : "n/a"; })]));
    }
    render(false);
    // hide filled dots until visible, then animate in
    if (!A.reducedMotion()) {
      d3.select(host).selectAll(".dot.on").style("opacity", 0);
      A.onVisible(host, () => render(true), 0.25);
    }
    let lastW = host.clientWidth;
    window.addEventListener("resize", A.debounce(() => { if (host.clientWidth !== lastW) { lastW = host.clientWidth; render(false); } }, 200));
  };
})();
