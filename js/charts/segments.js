/* Chapter 4 — Who are the developers? Archetype "orbits": one dot ≈ a fixed share
   of respondents, clustered by latent class, slowly orbiting a common centre.
   Hover / focus an archetype to read its profile. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});

  A.initSegments = function () {
    const SG = A.data.segments, S = window.AtlasStory.ch4;
    const host = document.getElementById("seg-chart"), card = document.getElementById("seg-profile"), list = document.getElementById("seg-list");
    const classes = SG.classes;
    if (SG.status !== "final") document.getElementById("seg-provisional").hidden = false;
    let selected = classes[0] ? classes[0].id : null, sim = null, running = false, visible = false, theta = 0, raf = null;
    const colorOf = i => `var(--c-cat${(i % 7) + 1})`;

    list.innerHTML = "";
    classes.forEach((c, i) => {
      const b = document.createElement("button");
      b.type = "button"; b.className = "seg-item"; b.dataset.id = c.id;
      b.style.setProperty("--seg", colorOf(i));
      b.innerHTML = `<span class="seg-dot" aria-hidden="true"></span><span class="seg-name">${A.esc(c.label)}</span><span class="seg-share">${A.fmtPct(c.share * 100)}</span>`;
      b.setAttribute("aria-pressed", "false");
      b.addEventListener("click", () => select(c.id));
      b.addEventListener("mouseenter", () => select(c.id));
      b.addEventListener("focus", () => select(c.id));
      list.appendChild(b);
    });

    function select(id) {
      selected = id;
      list.querySelectorAll(".seg-item").forEach(b => b.setAttribute("aria-pressed", String(String(b.dataset.id) === String(id))));
      d3.select(host).selectAll("circle.sdot").classed("is-dim", d => String(d.cls.id) !== String(id));
      d3.select(host).selectAll("g.seg-label").classed("is-dim", d => String(d.id) !== String(id));
      const i = classes.findIndex(c => String(c.id) === String(id)), c = classes[i];
      if (!c) return;
      const bar = (label, v) => v === null || v === undefined || isNaN(v) ? "" :
        `<div class="pbar"><div class="pbar-line"><span>${A.esc(label)}</span><b>${A.fmtPct(v)}</b></div><div class="pbar-track"><div class="pbar-fill" style="width:${A.clamp(v, 0, 100)}%"></div></div></div>`;
      card.style.setProperty("--seg", colorOf(i));
      card.innerHTML = `<p class="eyebrow">Profile ${i + 1} of ${classes.length}</p>
        <h3 class="profile-name">${A.esc(c.label)}</h3>
        <p class="profile-share"><strong>${A.fmtPct(c.share * 100)}</strong> model-estimated share${c.share_lo !== null && c.share_hi !== null ? ` <span class="muted">(95% CI ${A.fmtCI(c.share_lo * 100, c.share_hi * 100, 0)}%)</span>` : ""}${c.n ? ` · ${c.n.toLocaleString("en-GB")} modal assignments` : ""}</p>
        ${c.description ? `<p class="profile-desc">${A.esc(c.description)}</p>` : ""}
        <p class="small muted">Bars are model-conditional response probabilities, not observed percentages within modal groups.</p>
        <div class="pbars">${bar("Trust AI accuracy", c.trust_pct)}${bar("Favourable to AI", c.fav_pct)}${c.profile.filter(p => !((c.trust_pct != null && /trust/i.test(p.label)) || (c.fav_pct != null && /favou?r/i.test(p.label)))).slice(0, 6).map(p => bar(p.label, p.value * 100)).join("")}</div>`;
    }

    let nodes = [], centers = [], W = 0, H = 0, svg, gDots, gLabels;
    function layout() {
      const narrow = A.isNarrow();
      W = host.clientWidth || 700; H = narrow ? 380 : 520;
      ({ svg } = A.svgIn(host, H, { label: `Orbit diagram of ${classes.length} developer archetypes; dot clusters are sized by share of respondents.` }));
      svg.selectAll("*").remove();
      const cx = W / 2, cy = H / 2, rx = Math.min(W * 0.34, 300), ry = Math.min(H * 0.33, 170);
      svg.append("ellipse").attr("class", "orbit").attr("cx", cx).attr("cy", cy).attr("rx", rx).attr("ry", ry);
      svg.append("ellipse").attr("class", "orbit orbit-inner").attr("cx", cx).attr("cy", cy).attr("rx", rx * 0.45).attr("ry", ry * 0.45);
      svg.append("text").attr("class", "orbit-core").attr("x", cx).attr("y", cy + 4).attr("text-anchor", "middle").text("developers");
      const total = narrow ? 200 : 320;
      // largest-remainder allocation of dots to classes
      const raw = classes.map(c => c.share * total), base = raw.map(Math.floor);
      let rest = total - base.reduce((a, b) => a + b, 0);
      raw.map((v, i) => [v - base[i], i]).sort((a, b) => b[0] - a[0]).slice(0, Math.max(0, rest)).forEach(([, i]) => base[i]++);
      centers = classes.map((c, i) => ({ id: c.id, a0: -Math.PI / 2 + (i / classes.length) * Math.PI * 2, x: cx, y: cy, rx, ry, cx, cy }));
      const old = new Map(nodes.map(n => [n.key, n]));
      nodes = [];
      classes.forEach((c, i) => d3.range(base[i]).forEach(j => {
        const key = c.id + "-" + j, o = old.get(key);
        nodes.push({ key, cls: c, ci: i, x: o ? o.x : cx + (Math.random() - 0.5) * 40, y: o ? o.y : cy + (Math.random() - 0.5) * 40 });
      }));
      const r = narrow ? 3.2 : 4.2;
      gDots = svg.append("g").attr("class", "sdots");
      gDots.selectAll("circle").data(nodes, d => d.key).join("circle").attr("class", "sdot").attr("r", r)
        .style("fill", d => colorOf(d.ci)).attr("cx", d => d.x).attr("cy", d => d.y)
        .on("pointerenter", (ev, d) => select(d.cls.id));
      gLabels = svg.append("g").attr("class", "seg-labels");
      const lab = gLabels.selectAll("g").data(classes).join("g").attr("class", "seg-label");
      lab.append("text").attr("class", "seg-label-name").attr("text-anchor", "middle").text(c => (narrow && c.label.length > 16 ? c.label.slice(0, 15) + "…" : c.label));
      lab.append("text").attr("class", "seg-label-share").attr("text-anchor", "middle").attr("dy", 16).text(c => A.fmtPct(c.share * 100));
      placeCenters();
      if (sim) sim.stop();
      sim = d3.forceSimulation(nodes)
        .force("x", d3.forceX(d => centers[d.ci].x).strength(0.09))
        .force("y", d3.forceY(d => centers[d.ci].y).strength(0.09))
        .force("collide", d3.forceCollide(r + 0.9).iterations(2))
        .alphaDecay(0.02).stop();
      if (A.reducedMotion()) { for (let i = 0; i < 260; i++) sim.tick(); draw(); }
      else { for (let i = 0; i < 40; i++) sim.tick(); draw(); }
      select(selected);
    }
    function placeCenters() {
      centers.forEach((c, i) => { const a = c.a0 + theta; c.x = c.cx + Math.cos(a) * c.rx; c.y = c.cy + Math.sin(a) * c.ry; });
      if (gLabels) gLabels.selectAll("g.seg-label").attr("transform", (d, i) => {
        const c = centers[i], n = Math.sqrt(classes[i].share * (A.isNarrow() ? 200 : 320)) * (A.isNarrow() ? 4.1 : 5.1) * 1.08;
        const dy = c.y < c.cy ? -n - 30 : n + 20;
        return `translate(${A.clamp(c.x, 70, W - 70)},${A.clamp(c.y + dy, 14, H - 22)})`;
      });
    }
    function draw() { gDots.selectAll("circle").attr("cx", d => d.x).attr("cy", d => d.y); }
    function loop() {
      if (!running) return;
      theta += 0.0009; placeCenters();
      sim.alpha(Math.max(sim.alpha(), 0.06)); sim.tick(); draw();
      raf = requestAnimationFrame(loop);
    }
    function start() { if (running || A.reducedMotion() || !visible || document.hidden) return; running = true; raf = requestAnimationFrame(loop); }
    function stop() { running = false; if (raf) cancelAnimationFrame(raf); }

    layout();
    A.watchVisibility(host, v => { visible = v; v ? start() : stop(); });
    document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));
    let lastW = host.clientWidth;
    window.addEventListener("resize", A.debounce(() => { if (host.clientWidth !== lastW) { lastW = host.clientWidth; stop(); layout(); start(); } }, 200));

    A.srTable(document.getElementById("seg-table"), "Developer archetypes: share of respondents and attitudes", ["Archetype", "Share", "Trust", "Favourable", "Description"],
      classes.map(c => [c.label, A.fmtPct(c.share * 100, 1), A.fmtPct(c.trust_pct), A.fmtPct(c.fav_pct), c.description || ""]));
  };
})();
