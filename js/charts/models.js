/* Chapter 5 — What predicts trust? Simple logistic regression vs complex models:
   AUC tournament with a "margin that matters" band, calibration curves and
   SHAP-style driver bars with bootstrap stability whiskers. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});
  const HIDE_IN_DUEL = /^(baseline|dummy)$|_recal$/;
  const MODEL_CLASS = m => (m === "logit" ? "m-logit" : /lgbm|xgb|gbm|hgb|boost/.test(m) ? "m-gbm" : m === "rf" ? "m-rf" : "m-other");

  A.initModels = function () {
    const M = A.data.modelling, S = window.AtlasStory.ch5;
    const def = A.modelDefaults(M);
    if (!def) return;
    const st = { ...def, shapModel: null, entered: false };
    const outcomes = [...new Set(M.metrics.map(r => r.outcome))];
    const oLabel = o => ({ fav: "Favourable to AI", trust: "Trusts AI accuracy", trust26: "Trust 2026 (new scale)", use: "Uses AI" }[o] || o);
    const fsLabel = f => ({ D: "Who they are", B: "+ how they use AI", E: "+ other attitudes" }[f] || f);
    const els = {
      outcome: document.getElementById("model-outcome"), fs: document.getElementById("model-fs"), scheme: document.getElementById("model-scheme"),
      duel: document.getElementById("model-duel"), verdict: document.getElementById("model-verdict"),
      calib: document.getElementById("model-calib"), calibLegend: document.getElementById("calib-legend"),
      shapModel: document.getElementById("shap-model"), shap: document.getElementById("model-shap"), fsNote: document.getElementById("model-fs-note")
    };

    A.segmented(els.outcome, outcomes.map(o => ({ value: o, label: oLabel(o) })), st.outcome, v => { st.outcome = v; refreshFs(); renderAll(true); }, "Outcome to predict");
    function refreshFs() {
      const fsets = [...new Set(M.metrics.filter(r => r.outcome === st.outcome).map(r => r.feature_set))].sort();
      if (!fsets.includes(st.feature_set)) st.feature_set = fsets[0];
      A.segmented(els.fs, fsets.map(f => ({ value: f, label: fsLabel(f) })), st.feature_set, v => { st.feature_set = v; refreshSchemes(); renderAll(true); }, "Feature set");
      refreshSchemes();
    }
    function refreshSchemes() {
      const schemes = [...new Set(M.metrics.filter(r => r.outcome === st.outcome && r.feature_set === st.feature_set).map(r => r.scheme))];
      if (!schemes.includes(st.scheme)) st.scheme = schemes[0];
      els.scheme.innerHTML = schemes.map(s => `<option value="${A.esc(s)}"${s === st.scheme ? " selected" : ""}>${A.esc(A.schemeName(s))}</option>`).join("");
      els.scheme.closest(".field").hidden = schemes.length < 2;
    }
    els.scheme.addEventListener("change", () => { st.scheme = els.scheme.value; renderAll(true); });
    refreshFs();

    const matchesPanel = r => r.outcome === st.outcome &&
      (r.feature_set || "D") === st.feature_set &&
      (r.scheme || "temporal_2324to25") === st.scheme;

    function renderDuel(animate) {
      const allRows = M.metrics.filter(r => r.outcome === st.outcome && r.feature_set === st.feature_set && r.scheme === st.scheme).sort((a, b) => b.auc - a.auc);
      // the AUC duel hides the base-rate model and recalibrated twins (recalibration leaves AUC unchanged); the table keeps them all
      const rows = allRows.filter(r => !HIDE_IN_DUEL.test(r.model));
      const narrow = A.isNarrow(), rowH = 46, top = 34;
      const H = top + rows.length * rowH + 44;
      const { svg, width: W } = A.svgIn(els.duel, H, { label: "Dot and whisker chart of hold-out AUC by model with 95% bootstrap intervals." });
      svg.selectAll("*").remove();
      const lg = rows.find(r => r.model === "logit");
      const labelW = narrow ? 112 : 210, valW = 56;
      const lo = d3.min(rows, r => r.auc_lo ?? r.auc), hi = d3.max(rows, r => r.auc_hi ?? r.auc);
      const margin = M.margin || 0;
      const x = d3.scaleLinear().domain([lo - 0.01, Math.max(hi, lg ? lg.auc + margin : hi) + 0.01]).nice().range([labelW, W - valW]);
      x.ticks(narrow ? 3 : 5).forEach(t => {
        svg.append("line").attr("class", "grid-line").attr("x1", x(t)).attr("x2", x(t)).attr("y1", top - 8).attr("y2", H - 38);
        svg.append("text").attr("class", "tick").attr("x", x(t)).attr("y", H - 22).attr("text-anchor", "middle").text(t.toFixed(2));
      });
      svg.append("text").attr("class", "axis-note").attr("x", W - valW).attr("y", H - 2).attr("text-anchor", "end").text("AUC on hold-out →");
      if (lg && margin) {
        svg.append("rect").attr("class", "matter-band").attr("x", x(lg.auc)).attr("y", top - 8).attr("width", Math.max(1, x(lg.auc + margin) - x(lg.auc))).attr("height", H - top - 30);
        svg.append("text").attr("class", "matter-label").attr("x", x(lg.auc)).attr("y", top - 14).text(narrow ? "gain that matters →" : "logistic + the gain that would matter →");
        svg.append("line").attr("class", "baseline-line").attr("x1", x(lg.auc)).attr("x2", x(lg.auc)).attr("y1", top - 8).attr("y2", H - 38);
      }
      const g = svg.selectAll("g.mrow").data(rows).join("g").attr("class", r => "mrow " + MODEL_CLASS(r.model)).attr("transform", (r, i) => `translate(0,${top + i * rowH + rowH / 2})`);
      g.append("text").attr("class", "mname").attr("x", 0).attr("y", 4).text(r => (narrow ? A.modelName(r.model).replace(/ \(.*\)/, "").replace("Logistic regression", "Logistic").replace("Gradient boosting", "Boosting") : A.modelName(r.model)));
      g.filter(r => r.model === "logit" && !narrow).append("text").attr("class", "mpill").attr("x", 0).attr("y", 20).text("simple baseline");
      g.append("line").attr("class", "mwhisk").attr("y1", 0).attr("y2", 0).attr("x1", r => x(r.auc_lo ?? r.auc)).attr("x2", r => x(r.auc_hi ?? r.auc));
      const dot = g.append("circle").attr("class", "mdot").attr("r", 7).attr("cy", 0).attr("cx", r => (animate && lg && !A.reducedMotion() ? x(lg.auc) : x(r.auc)));
      if (animate && !A.reducedMotion()) dot.transition().duration(900).delay((r, i) => 150 + i * 120).ease(d3.easeBackOut.overshoot(1.2)).attr("cx", r => x(r.auc));
      g.append("text").attr("class", "mval").attr("x", W).attr("y", 5).attr("text-anchor", "end").text(r => r.auc.toFixed(3));
      g.on("pointerenter", (ev, r) => A.tip.show(`<strong>${A.esc(A.modelName(r.model))}</strong><br>AUC ${r.auc.toFixed(3)} <span class="muted">[${(r.auc_lo ?? NaN).toFixed(3)}, ${(r.auc_hi ?? NaN).toFixed(3)}]</span>${r.brier != null ? `<br>Brier ${(+r.brier).toFixed(3)}` : ""}${r.log_loss != null ? ` · log-loss ${(+r.log_loss).toFixed(3)}` : ""}${r.n_test ? `<br><span class="muted">test n = ${(+r.n_test).toLocaleString("en-GB")}</span>` : ""}`, ev))
        .on("pointermove", ev => A.tip.move(ev)).on("pointerleave", () => A.tip.hide());

      // verdict: best complex model vs logit
      const best = rows.filter(r => r.model !== "logit")[0];
      const dvs = best ? M.diffs.filter(r => r.outcome === st.outcome && r.feature_set === st.feature_set && r.scheme === st.scheme && r.model === best.model) : [];
      const baseline = best && best.model === "ensemble" ? "logit_recal" : "logit";
      const dv = dvs.find(r => !r.vs || r.vs === baseline) || dvs[0];
      if (dv && dv.d_auc != null) {
        const s = v => (v >= 0 ? "+" : "−") + Math.abs(+v).toFixed(3);
        const passes = margin && +dv.d_auc >= margin && +dv.d_auc_lo > 0;
        const vsName = v => (v === "logit_recal" ? "vs recalibrated logistic" : "vs logistic");
        const others = dvs.filter(r => r !== dv && r.verdict);
        els.verdict.innerHTML = `<div class="verdict-num ${passes ? "is-pass" : "is-fail"}"><span>ΔAUC, ${A.esc(A.modelName(best.model).replace(/ \(.*\)/, ""))} − ${baseline === "logit_recal" ? "calibrated logistic" : "logistic"}</span><strong>${s(dv.d_auc)}</strong>${dv.d_auc_lo != null ? `<small>95% CI [${s(dv.d_auc_lo)}, ${s(dv.d_auc_hi)}]</small>` : ""}</div>
          <p class="verdict-text"><b>${A.esc(S.verdictLead)}</b> ${A.esc(dv.verdict || (passes ? "complexity earns its place" : "the simple model is enough"))}${margin ? ` <span class="muted">(margin that matters: +${margin.toFixed(3)})</span>` : ""}</p>${others.map(o => `<p class="verdict-text small"><b>${A.esc(vsName(o.vs))}:</b> ${A.esc(o.verdict)}</p>`).join("")}${S.verdictNote ? `<p class="verdict-text small muted">${A.esc(S.verdictNote)}</p>` : ""}`;
      } else els.verdict.innerHTML = "";

      const fsDesc = M.meta.feature_sets && M.meta.feature_sets[st.feature_set];
      els.fsNote.textContent = fsDesc ? `Feature set ${st.feature_set}: ${fsDesc}` : "";
      A.srTable(document.getElementById("model-table"), `Hold-out AUC by model (${oLabel(st.outcome)}, feature set ${st.feature_set})`, ["Model", "AUC", "95% CI"],
        allRows.map(r => [A.modelName(r.model), r.auc.toFixed(3), r.auc_lo != null ? `${(+r.auc_lo).toFixed(3)}–${(+r.auc_hi).toFixed(3)}` : ""]));
    }

    function renderCalib(animate) {
      const rows = M.calibration.filter(matchesPanel);
      const host = els.calib;
      const size = Math.min(host.clientWidth || 380, 440);
      const { svg } = A.svgIn(host, size, { label: "Calibration curve: mean predicted probability versus observed rate per bin." });
      svg.attr("viewBox", `0 0 ${size} ${size}`).attr("width", size);
      svg.selectAll("*").remove();
      if (!rows.length) { svg.append("text").attr("class", "axis-note").attr("x", 10).attr("y", 30).text("No calibration export for this comparison."); els.calibLegend.innerHTML = ""; return; }
      const m = { t: 14, r: 14, b: 40, l: 44 };
      const x = d3.scaleLinear().domain([0, 1]).range([m.l, size - m.r]), y = d3.scaleLinear().domain([0, 1]).range([size - m.b, m.t]);
      [0, 0.25, 0.5, 0.75, 1].forEach(t => {
        svg.append("line").attr("class", "grid-line").attr("x1", x(t)).attr("x2", x(t)).attr("y1", y(0)).attr("y2", y(1));
        svg.append("line").attr("class", "grid-line").attr("x1", x(0)).attr("x2", x(1)).attr("y1", y(t)).attr("y2", y(t));
        svg.append("text").attr("class", "tick").attr("x", x(t)).attr("y", size - m.b + 16).attr("text-anchor", "middle").text(t);
        svg.append("text").attr("class", "tick").attr("x", m.l - 6).attr("y", y(t) + 4).attr("text-anchor", "end").text(t);
      });
      svg.append("line").attr("class", "diag").attr("x1", x(0)).attr("y1", y(0)).attr("x2", x(1)).attr("y2", y(1));
      svg.append("text").attr("class", "axis-note").attr("x", x(0.98)).attr("y", y(0.98) + 16).attr("text-anchor", "end").text("perfect");
      svg.append("text").attr("class", "axis-title").attr("x", (m.l + size - m.r) / 2).attr("y", size - 6).attr("text-anchor", "middle").text("Predicted probability");
      svg.append("text").attr("class", "axis-title").attr("transform", `translate(12,${(m.t + size - m.b) / 2}) rotate(-90)`).attr("text-anchor", "middle").text("Observed rate");
      const models = [...new Set(rows.map(r => r.model))];
      models.forEach(mo => {
        const pts = rows.filter(r => r.model === mo).sort((a, b) => a.mean_pred - b.mean_pred);
        const g = svg.append("g").attr("class", "cal " + MODEL_CLASS(mo));
        pts.forEach(p => { if (p.obs_lo != null) g.append("line").attr("class", "cal-whisk").attr("x1", x(p.mean_pred)).attr("x2", x(p.mean_pred)).attr("y1", y(p.obs_lo)).attr("y2", y(p.obs_hi)); });
        const path = g.append("path").attr("class", "cal-line").attr("d", d3.line().x(p => x(p.mean_pred)).y(p => y(p.observed))(pts));
        if (animate && !A.reducedMotion()) { const L = path.node().getTotalLength(); path.attr("stroke-dasharray", L).attr("stroke-dashoffset", L).transition().duration(1200).attr("stroke-dashoffset", 0).on("end", () => path.attr("stroke-dasharray", null)); }
        g.selectAll("circle").data(pts).join("circle").attr("class", "cal-pt").attr("cx", p => x(p.mean_pred)).attr("cy", p => y(p.observed)).attr("r", 4)
          .on("pointerenter", (ev, p) => A.tip.show(`<strong>${A.esc(A.modelName(mo))}</strong><br>bin ${p.bin}: predicted ${(p.mean_pred * 100).toFixed(0)}%, observed ${(p.observed * 100).toFixed(0)}%${p.n ? `<br><span class="muted">n = ${(+p.n).toLocaleString("en-GB")}</span>` : ""}`, ev))
          .on("pointermove", ev => A.tip.move(ev)).on("pointerleave", () => A.tip.hide());
      });
      els.calibLegend.innerHTML = models.map(mo => `<span class="legend-item ${MODEL_CLASS(mo)}"><span class="swatch"></span>${A.esc(A.modelName(mo))}</span>`).join("");
    }

    function renderShap(animate) {
      const rowsAll = M.shap.filter(matchesPanel);
      const models = [...new Set(rowsAll.map(r => r.model))];
      if (!models.includes(st.shapModel)) st.shapModel = models.find(m => m !== "logit") || models[0];
      A.segmented(els.shapModel, models.map(m => ({ value: m, label: A.modelName(m).replace(/ \(.*\)/, "") })), st.shapModel, v => { st.shapModel = v; renderShap(true); }, "Model for drivers");
      const rows = rowsAll.filter(r => r.model === st.shapModel).sort((a, b) => b.mean_abs_shap - a.mean_abs_shap).slice(0, 10);
      const narrow = A.isNarrow(), rowH = narrow ? 44 : 34, top = 8;
      const H = top + rows.length * rowH + 26;
      const { svg, width: W } = A.svgIn(els.shap, H, { label: "Bar chart of mean absolute SHAP value per feature with bootstrap intervals." });
      svg.selectAll("*").remove();
      if (!rows.length) {
        svg.append("text").attr("class", "axis-note").attr("x", 0).attr("y", 22).text("No driver export for this comparison.");
        document.getElementById("shap-table").replaceChildren();
        return;
      }
      const labelW = narrow ? 0 : 200, rightW = narrow ? 70 : 150;
      const x = d3.scaleLinear().domain([0, d3.max(rows, r => r.shap_hi ?? r.mean_abs_shap)]).nice().range([labelW, W - rightW]);
      const g = svg.selectAll("g.srow").data(rows).join("g").attr("class", "srow").attr("transform", (r, i) => `translate(0,${top + i * rowH})`);
      const barY = narrow ? 18 : 6, barH = 16;
      g.append("text").attr("class", "slabel").attr("x", narrow ? 0 : labelW - 10).attr("y", narrow ? 12 : barY + 12).attr("text-anchor", narrow ? "start" : "end").text(r => r.label);
      g.append("rect").attr("class", "strack").attr("x", labelW).attr("y", barY).attr("height", barH).attr("width", W - rightW - labelW).attr("rx", 3);
      const bar = g.append("rect").attr("class", "sbar " + MODEL_CLASS(st.shapModel)).attr("x", labelW).attr("y", barY).attr("height", barH).attr("rx", 3)
        .attr("width", r => (animate && !A.reducedMotion() ? 0 : x(r.mean_abs_shap) - labelW));
      if (animate && !A.reducedMotion()) bar.transition().duration(800).delay((r, i) => i * 60).ease(d3.easeCubicOut).attr("width", r => x(r.mean_abs_shap) - labelW);
      g.filter(r => r.shap_lo != null).append("line").attr("class", "swhisk").attr("x1", r => x(r.shap_lo)).attr("x2", r => x(r.shap_hi)).attr("y1", barY + barH / 2).attr("y2", barY + barH / 2);
      g.filter(r => r.shap_lo != null).append("line").attr("class", "swhisk").attr("x1", r => x(r.shap_lo)).attr("x2", r => x(r.shap_lo)).attr("y1", barY + 3).attr("y2", barY + barH - 3);
      g.filter(r => r.shap_hi != null).append("line").attr("class", "swhisk").attr("x1", r => x(r.shap_hi)).attr("x2", r => x(r.shap_hi)).attr("y1", barY + 3).attr("y2", barY + barH - 3);
      g.append("text").attr("class", "srank").attr("x", W).attr("y", barY + 12).attr("text-anchor", "end")
        .text(r => (r.rank_lo != null ? `rank ${Math.round(r.rank_lo)}${Math.round(r.rank_hi) !== Math.round(r.rank_lo) ? "–" + Math.round(r.rank_hi) : ""}` : "") + (!narrow && r.p_top3 != null ? ` · top-3 ${Math.round(r.p_top3 * 100)}%` : ""));
      g.on("pointerenter", (ev, r) => A.tip.show(`<strong>${A.esc(r.label)}</strong><br>mean |SHAP| ${(+r.mean_abs_shap).toFixed(4)}${r.shap_lo != null ? ` <span class="muted">[${(+r.shap_lo).toFixed(4)}, ${(+r.shap_hi).toFixed(4)}]</span>` : ""}${r.p_top3 != null ? `<br>in top 3 in ${Math.round(r.p_top3 * 100)}% of ${r.n_boot || ""} bootstrap fits` : ""}`, ev))
        .on("pointermove", ev => A.tip.move(ev)).on("pointerleave", () => A.tip.hide());
      svg.append("text").attr("class", "tick").attr("x", labelW).attr("y", H - 4).text("0");
      svg.append("text").attr("class", "axis-note").attr("x", W - rightW).attr("y", H - 4).attr("text-anchor", "end").text("mean |SHAP| →");
      A.srTable(document.getElementById("shap-table"), `Top drivers (${A.modelName(st.shapModel)}, ${oLabel(st.outcome)})`, ["Feature", "Mean |SHAP|", "95% interval", "Rank range", "P(top 3)"],
        rows.map(r => [r.label, (+r.mean_abs_shap).toFixed(4), r.shap_lo != null ? `${(+r.shap_lo).toFixed(4)}–${(+r.shap_hi).toFixed(4)}` : "", r.rank_lo != null ? `${r.rank_lo}–${r.rank_hi}` : "", r.p_top3 != null ? Math.round(r.p_top3 * 100) + "%" : ""]));
    }

    function renderAll(animate) { renderDuel(animate); renderCalib(animate); renderShap(animate); }
    renderAll(false);
    if (!A.reducedMotion()) A.onVisible(els.duel, () => renderAll(true), 0.3);
    let lastW = els.duel.clientWidth;
    window.addEventListener("resize", A.debounce(() => { if (els.duel.clientWidth !== lastW) { lastW = els.duel.clientWidth; renderAll(false); } }, 200));
  };
})();
