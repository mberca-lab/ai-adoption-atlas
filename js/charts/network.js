/* Chapter 6 — Tool constellations: force network of AI tools used together.
   Nodes = tools (area ∝ support), edges = association-rule pairs (width ∝ lift).
   Hover / focus a tool to isolate it and its partners. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});

  A.initNetwork = function () {
    const NB = A.data.segments.baskets, S = window.AtlasStory.ch6;
    const host = document.getElementById("net-chart"), ctl = document.getElementById("net-basket"), info = document.getElementById("net-info"), legend = document.getElementById("net-legend");
    if (!NB.length) return;
    let current = NB[NB.length - 1].id, sim = null, locked = null, visible = false, pending = true;

    const basketLabel = b => b.id === "B25A" ? "2025 agents" : b.id === "B25M" ? "2025 models + IDEs" : b.year ? String(b.year) : b.id;
    A.segmented(ctl, NB.map(b => ({ value: b.id, label: basketLabel(b) })), current, v => { current = v; locked = null; render(true); }, "Survey basket");

    function vendorColors(nodes) {
      const counts = d3.rollups(nodes, v => d3.sum(v, n => n.support || 0.01), n => n.vendor).sort((a, b) => b[1] - a[1]).map(d => d[0]).filter(v => v && v !== "Other");
      const top = counts.slice(0, 6), map = new Map(top.map((v, i) => [v, `var(--c-cat${i + 1})`]));
      return { color: v => map.get(v) || "var(--c-none)", list: [...top, "Other"] };
    }

    function render(animate) {
      const b = NB.find(x => x.id === current) || NB[0];
      const narrow = A.isNarrow();
      const H = narrow ? 460 : 580;
      const { svg, width: W } = A.svgIn(host, H, { label: `Network of ${b.nodes.length} AI tools; lines connect tools used together more often than chance.` });
      svg.selectAll("*").remove();
      if (sim) sim.stop();
      const nodes = b.nodes.map(n => ({ ...n })), byId = new Map(nodes.map(n => [n.id, n]));
      const links = b.links.filter(l => byId.has(l.source) && byId.has(l.target)).map(l => ({ ...l }));
      const vc = vendorColors(nodes);
      const maxSup = d3.max(nodes, n => n.support || 0) || 1;
      const rS = d3.scaleSqrt().domain([0, maxSup]).range([narrow ? 4 : 5, narrow ? 26 : 40]);
      const wS = d3.scaleLinear().domain(d3.extent(links, l => l.lift)).range([1.2, narrow ? 5 : 7]);
      const deg = new Map(); links.forEach(l => { deg.set(l.source, (deg.get(l.source) || 0) + 1); deg.set(l.target, (deg.get(l.target) || 0) + 1); });

      const gL = svg.append("g").attr("class", "links");
      const link = gL.selectAll("line").data(links).join("line").attr("class", "nlink").attr("stroke-width", l => wS(l.lift));
      const gN = svg.append("g").attr("class", "nodes");
      const node = gN.selectAll("g").data(nodes, n => n.id).join("g").attr("class", "nnode")
        .attr("tabindex", 0).attr("role", "button")
        .attr("aria-label", n => `${n.id}${n.support != null ? `, used by ${Math.round(n.support * 100)}% of respondents in this basket` : ""}, ${deg.get(n.id) || 0} strong pairings. Press Enter to isolate.`);
      node.append("circle").attr("class", "nhalo").attr("r", n => rS(n.support || 0) + 6);
      node.append("circle").attr("class", "ncirc").attr("r", n => rS(n.support || 0)).style("fill", n => vc.color(n.vendor));
      const showLabel = n => (n.support || 0) >= maxSup * (narrow ? 0.12 : 0.05) || (deg.get(n.id) || 0) >= 2 || !narrow;
      node.filter(showLabel).append("text").attr("class", "nlabel").attr("dy", n => rS(n.support || 0) + 13).attr("text-anchor", "middle").text(n => n.id);

      const neighbours = id => new Set([id, ...links.filter(l => l.source.id === id || l.target.id === id).map(l => (l.source.id === id ? l.target.id : l.source.id))]);
      function isolate(id) {
        if (!id) { svg.classed("is-isolating", false); node.classed("is-on", false); link.classed("is-on", false); info.innerHTML = defaultInfo(); return; }
        const nb = neighbours(id);
        svg.classed("is-isolating", true);
        node.classed("is-on", n => nb.has(n.id)).classed("is-focus", n => n.id === id);
        link.classed("is-on", l => l.source.id === id || l.target.id === id);
        const n = byId.get(id);
        const partners = links.filter(l => l.source.id === id || l.target.id === id).sort((a, b) => b.lift - a.lift)
          .map(l => { const o = l.source.id === id ? l.target : l.source; return `<li><span>${A.esc(o.id)}</span><b>×${l.lift.toFixed(2)}</b>${l.lift_lo != null ? `<small>${l.lift_lo.toFixed(2)}–${l.lift_hi.toFixed(2)}</small>` : ""}</li>`; }).join("");
        info.innerHTML = `<p class="eyebrow">${A.esc(n.vendor || "")}</p><h3 class="profile-name">${A.esc(id)}</h3>
          ${n.support != null ? `<p class="profile-share"><strong>${A.fmtPct(n.support * 100)}</strong> of respondents in this basket</p>` : ""}
          ${partners ? `<p class="muted small">Used together more than chance with (lift, 95% interval):</p><ul class="partners">${partners}</ul>` : `<p class="muted">No pairing passed the support, confidence and lift thresholds.</p>`}`;
      }
      function defaultInfo() {
        const top = links.slice().sort((a, b) => b.lift - a.lift).slice(0, 5)
          .map(l => `<li><span>${A.esc(l.source.id || l.source)} + ${A.esc(l.target.id || l.target)}</span><b>×${l.lift.toFixed(2)}</b></li>`).join("");
        return `<p class="eyebrow">${A.esc(basketLabel(b))} · ${nodes.length} tools · ${links.length} pairings</p>
          ${b.n ? `<p class="small muted">Basket denominator: ${b.n.toLocaleString("en-GB")} respondents.</p>` : ""}
          ${b.description ? `<p class="muted small">${A.esc(b.description)}</p>` : ""}
          <p class="small"><strong>Strongest pairings</strong></p><ul class="partners">${top}</ul><p class="muted small">${A.esc(S.liftNote)}</p>`;
      }
      node.on("pointerenter", (ev, n) => { if (!locked) isolate(n.id); })
        .on("pointerleave", () => { if (!locked) isolate(null); })
        .on("focus", (ev, n) => { if (!locked) isolate(n.id); })
        .on("blur", () => { if (!locked) isolate(null); })
        .on("click", (ev, n) => { locked = locked === n.id ? null : n.id; isolate(locked || n.id); })
        .on("keydown", (ev, n) => {
          if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); locked = locked === n.id ? null : n.id; isolate(locked || n.id); }
          if (ev.key === "Escape") { locked = null; isolate(null); ev.target.blur(); }
        });
      svg.on("click", ev => { if (ev.target === svg.node()) { locked = null; isolate(null); } });

      const cx = W / 2, cy = H / 2;
      nodes.forEach((n, i) => { const a = (i / nodes.length) * Math.PI * 2; n.x = cx + Math.cos(a) * W * 0.25; n.y = cy + Math.sin(a) * H * 0.25; });
      sim = d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(n => n.id).distance(l => (narrow ? 70 : 120) / Math.sqrt(l.lift)).strength(0.5))
        .force("charge", d3.forceManyBody().strength(narrow ? -160 : -320))
        .force("collide", d3.forceCollide(n => rS(n.support || 0) + (narrow ? 14 : 22)))
        .force("x", d3.forceX(cx).strength(0.06)).force("y", d3.forceY(cy).strength(0.08));
      const ticked = () => {
        nodes.forEach(n => { const r = rS(n.support || 0) + 6; n.x = A.clamp(n.x, r + 4, W - r - 4); n.y = A.clamp(n.y, r + 4, H - r - 18); });
        link.attr("x1", l => l.source.x).attr("y1", l => l.source.y).attr("x2", l => l.target.x).attr("y2", l => l.target.y);
        node.attr("transform", n => `translate(${n.x},${n.y})`);
      };
      if (A.reducedMotion() || !animate || !visible) { sim.stop(); for (let i = 0; i < 320; i++) sim.tick(); ticked(); }
      else { sim.on("tick", ticked); sim.alpha(1).restart(); }
      // gentle drag for the curious
      if (!A.reducedMotion()) node.call(d3.drag()
        .on("start", (ev, n) => { if (!ev.active) sim.alphaTarget(0.2).restart(); n.fx = n.x; n.fy = n.y; })
        .on("drag", (ev, n) => { n.fx = ev.x; n.fy = ev.y; })
        .on("end", (ev, n) => { if (!ev.active) sim.alphaTarget(0); n.fx = null; n.fy = null; }));
      if (!sim.on("tick")) sim.on("tick", ticked);
      info.innerHTML = defaultInfo();
      legend.innerHTML = vc.list.map(v => `<span class="legend-item"><span class="legend-dot" style="background:${v === "Other" ? "var(--c-none)" : vc.color(v)}"></span>${A.esc(v)}</span>`).join("") +
        `<span class="legend-item"><span class="legend-line"></span>line weight = lift</span>`;
      A.srTable(document.getElementById("net-table"), `Tool pairings in ${b.year || b.id}, sorted by lift`, ["Tool A", "Tool B", "Lift", "Support", "Confidence"],
        links.slice().sort((a, b2) => b2.lift - a.lift).map(l => [l.source.id || l.source, l.target.id || l.target, l.lift.toFixed(2), l.support != null ? (l.support * 100).toFixed(1) + "%" : "", l.confidence != null ? (l.confidence * 100).toFixed(0) + "%" : ""]));
      pending = false;
    }
    render(false);
    A.watchVisibility(host, v => { const was = visible; visible = v; if (v && !was && pending === false && !A.reducedMotion() && !host.dataset.played) { host.dataset.played = "1"; render(true); } if (!v && sim) sim.stop(); });
    let lastW = host.clientWidth;
    window.addEventListener("resize", A.debounce(() => { if (host.clientWidth !== lastW) { lastW = host.clientWidth; render(false); } }, 200));
  };
})();
