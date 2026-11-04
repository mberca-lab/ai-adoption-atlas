/* AI Adoption Atlas — living particle field (chapters 0–1).
   Thousands of "developers" drift in a flow field, then settle into a unit chart
   (each dot ≈ 1/N of respondents) whose colours follow adoption by year.
   Perf: typed arrays, capped count, DPR ≤ 2, paused off-screen / hidden tab,
   idles when nothing moves. Reduced motion: static frames only. */
(function () {
  "use strict";
  const A = (window.Atlas = window.Atlas || {});

  function hexToRgb(h) {
    h = String(h || "").trim();
    if (h.startsWith("rgb")) { const m = h.match(/[\d.]+/g); return m ? [+m[0], +m[1], +m[2]] : [128, 128, 128]; }
    h = h.replace("#", "");
    if (h.length === 3) h = h.split("").map(c => c + c).join("");
    const v = parseInt(h, 16);
    return isNaN(v) ? [128, 128, 128] : [(v >> 16) & 255, (v >> 8) & 255, v & 255];
  }

  class Field {
    constructor(canvas, stage, shares) {
      this.cv = canvas; this.stage = stage; this.ctx = canvas.getContext("2d", { alpha: true });
      this.shares = shares;           // {2023:{use,plan,series}, …} in 0–1
      this.morphTarget = 0; this.morph = 0; this.year = null;
      this.visible = true; this.running = false; this.raf = null; this.lastActive = 0;
      this.pointer = { x: -1e4, y: -1e4 };
      this.reduced = A.reducedMotion();
      this.readColors();
      this._tick = this.tick.bind(this);
      this.resize(true);
      const onPtr = e => { const r = this.cv.getBoundingClientRect(); this.pointer.x = e.clientX - r.left; this.pointer.y = e.clientY - r.top; this.wake(); };
      stage.addEventListener("pointermove", onPtr, { passive: true });
      stage.addEventListener("pointerleave", () => { this.pointer.x = this.pointer.y = -1e4; });
      document.addEventListener("visibilitychange", () => (document.hidden ? this.stop() : this.wake()));
      A.watchVisibility(stage, v => { this.visible = v; v ? this.wake() : this.stop(); });
    }

    readColors() {
      this.col = { use: hexToRgb(A.css("--c-use")), plan: hexToRgb(A.css("--c-plan")), none: hexToRgb(A.css("--c-none")), hero: hexToRgb(A.css("--c-dot")) };
    }

    resize(init) {
      const r = this.stage.getBoundingClientRect();
      const W = Math.max(300, r.width), H = Math.max(400, r.height);
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.cv.width = Math.round(W * dpr); this.cv.height = Math.round(H * dpr);
      this.cv.style.width = W + "px"; this.cv.style.height = H + "px";
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const narrow = W < 760;
      const N = Math.round(A.clamp((W * H) / 520, 700, 2400));
      const oldW = this.W || W, oldH = this.H || H;
      this.W = W; this.H = H; this.narrow = narrow;
      if (init || N !== this.N) this.alloc(N);
      else for (let i = 0; i < this.N; i++) { this.fx[i] *= W / oldW; this.fy[i] *= H / oldH; }
      // grid region (unit chart)
      const box = narrow ? { x0: W * 0.07, x1: W * 0.93, y0: H * 0.15, y1: H * 0.50 } : { x0: W * 0.47, x1: W * 0.93, y0: H * 0.2, y1: H * 0.8 };
      const bw = box.x1 - box.x0, bh = box.y1 - box.y0;
      const cell = Math.sqrt((bw * bh) / this.N);
      let cols = Math.max(10, Math.floor(bw / cell)); let rows = Math.ceil(this.N / cols);
      while (rows * cell > bh * 1.08 && cols < this.N) { cols++; rows = Math.ceil(this.N / cols); }
      const cw = bw / cols, ch = Math.min(cw, bh / rows);
      const gx0 = box.x0, gy0 = box.y0 + (bh - rows * ch) / 2;
      this.grid = { cols, rows, cw, ch, x0: gx0, y0: gy0, x1: gx0 + cols * cw, y1: gy0 + rows * ch, dot: Math.max(1.6, Math.min(cw, ch) * 0.66) };
      for (let i = 0; i < this.N; i++) {
        const c = Math.floor(i / rows), rr = i % rows;          // column-major: the block grows left → right
        this.gx[i] = gx0 + c * cw + cw / 2; this.gy[i] = gy0 + rr * ch + ch / 2;
        this.gcol[i] = c / Math.max(1, cols - 1);
      }
      if (this.stage) this.stage.style.setProperty("--grid-top", gy0 + "px");
      this.stage && this.stage.style.setProperty("--grid-left", gx0 + "px");
      this.stage && this.stage.style.setProperty("--grid-right", (W - this.grid.x1) + "px");
      this.stage && this.stage.style.setProperty("--grid-bottom", (H - this.grid.y1) + "px");
      this.wake(); this.render(performance.now());
    }

    alloc(N) {
      this.N = N;
      const F = n => new Float32Array(n);
      this.fx = F(N); this.fy = F(N); this.vx = F(N); this.vy = F(N); this.gx = F(N); this.gy = F(N); this.gcol = F(N);
      this.seed = F(N); this.cFrom = F(N * 3); this.cTo = F(N * 3); this.cT0 = new Float64Array(N); this.aFrom = F(N); this.aTo = F(N);
      this.ringFrom = new Uint8Array(N); this.ringTo = new Uint8Array(N);
      for (let i = 0; i < N; i++) {
        this.fx[i] = Math.random() * (this.W || 1200); this.fy[i] = Math.random() * (this.H || 800);
        this.seed[i] = Math.random();
        const c = this.col.hero; this.cFrom.set(c, i * 3); this.cTo.set(c, i * 3);
        this.aFrom[i] = this.aTo[i] = 0.25 + 0.55 * this.seed[i];
      }
      this.applyColors(true);
    }

    /** Which state is particle i in for the current year? */
    stateOf(i) {
      if (this.year === null || this.morphTarget < 0.5) return "hero";
      const s = this.shares[this.year]; if (!s) return "none";
      const f = i / this.N;
      return f < s.use ? "use" : f < s.use + (s.plan || 0) ? "plan" : "none";
    }

    applyColors(instant) {
      const now = performance.now();
      const ring = this.year !== null && this.morphTarget >= 0.5 && this.shares[this.year] && this.shares[this.year].series === "B";
      for (let i = 0; i < this.N; i++) {
        const st = this.stateOf(i);
        const c = this.col[st] || this.col.none;
        const a = st === "hero" ? 0.25 + 0.55 * this.seed[i] : st === "none" ? 0.42 : 1;
        // current colour becomes the new start (approximate if mid-transition)
        const k = this.progressOf(i, now);
        for (let j = 0; j < 3; j++) this.cFrom[i * 3 + j] = A.lerp(this.cFrom[i * 3 + j], this.cTo[i * 3 + j], k);
        this.aFrom[i] = A.lerp(this.aFrom[i], this.aTo[i], k);
        this.ringFrom[i] = k > 0.5 ? this.ringTo[i] : this.ringFrom[i];
        this.cTo[i * 3] = c[0]; this.cTo[i * 3 + 1] = c[1]; this.cTo[i * 3 + 2] = c[2]; this.aTo[i] = a;
        this.ringTo[i] = ring && st !== "hero" ? 1 : 0;
        this.cT0[i] = instant || this.reduced ? now - 1e4 : now + this.gcol[i] * 650 + this.seed[i] * 140;
      }
      this.colorsBusyUntil = now + (instant || this.reduced ? 0 : 1300);
    }
    progressOf(i, now) { const t = (now - this.cT0[i]) / 480; return t <= 0 ? 0 : t >= 1 ? 1 : A.ease(t); }

    setYear(y) { if (y === this.year) return; this.year = y; this.applyColors(false); this.wake(); }
    setMorph(t) {
      const before = this.morphTarget >= 0.5;
      this.morphTarget = this.reduced ? (t >= 0.5 ? 1 : 0) : A.clamp(t, 0, 1);
      if ((this.morphTarget >= 0.5) !== before) this.applyColors(false);
      this.wake();
    }
    setTheme() { this.readColors(); this.applyColors(true); this.wake(); this.render(performance.now()); }

    wake() {
      this.lastActive = performance.now();
      if (this.reduced) { this.morph = this.morphTarget; requestAnimationFrame(() => this.render(performance.now())); return; }
      if (!this.running && this.visible && !document.hidden) { this.running = true; this.raf = requestAnimationFrame(this._tick); }
    }
    stop() { this.running = false; if (this.raf) cancelAnimationFrame(this.raf); this.raf = null; }

    tick(now) {
      if (!this.running) return;
      this.morph += (this.morphTarget - this.morph) * 0.08;
      if (Math.abs(this.morphTarget - this.morph) < 0.0005) this.morph = this.morphTarget;
      this.step(now);
      this.render(now);
      // idle when fully settled into the grid and no colour transitions remain
      const settled = this.morph >= 0.999 && now > this.colorsBusyUntil + 600 && now - this.lastActive > 1500;
      if (settled) { this.running = false; return; }
      this.raf = requestAnimationFrame(this._tick);
    }

    step(now) {
      if (this.morph >= 0.999) return;
      const t = now * 0.0001, W = this.W, H = this.H, px = this.pointer.x, py = this.pointer.y;
      const repel = this.morph < 0.3;
      for (let i = 0; i < this.N; i++) {
        let x = this.fx[i], y = this.fy[i];
        const a = Math.sin(x * 0.0031 + t * 1.6) * 1.8 + Math.cos(y * 0.0042 - t) * 1.8 + this.seed[i] * 0.6;
        let vx = this.vx[i] * 0.955 + Math.cos(a) * 0.028, vy = this.vy[i] * 0.955 + Math.sin(a) * 0.028;
        if (repel) {
          const dx = x - px, dy = y - py, d2 = dx * dx + dy * dy;
          if (d2 < 9000) { const f = (1 - d2 / 9000) * 0.6 / Math.sqrt(d2 + 1); vx += dx * f; vy += dy * f; }
        }
        x += vx; y += vy;
        if (x < -5) x += W + 10; else if (x > W + 5) x -= W + 10;
        if (y < -5) y += H + 10; else if (y > H + 5) y -= H + 10;
        this.fx[i] = x; this.fy[i] = y; this.vx[i] = vx; this.vy[i] = vy;
      }
    }

    render(now) {
      const ctx = this.ctx, g = this.grid, M = this.reduced ? this.morphTarget : this.morph;
      ctx.clearRect(0, 0, this.W, this.H);
      const heroSize = 1.9;
      for (let i = 0; i < this.N; i++) {
        // staggered arrival: left columns settle first
        let m = A.clamp(M * 1.6 - this.gcol[i] * 0.6, 0, 1); m = A.ease(m);
        const x = A.lerp(this.fx[i], this.gx[i], m), y = A.lerp(this.fy[i], this.gy[i], m);
        const k = this.progressOf(i, now);
        const r = A.lerp(this.cFrom[i * 3], this.cTo[i * 3], k) | 0, gg = A.lerp(this.cFrom[i * 3 + 1], this.cTo[i * 3 + 1], k) | 0, b = A.lerp(this.cFrom[i * 3 + 2], this.cTo[i * 3 + 2], k) | 0;
        const al = A.lerp(this.aFrom[i], this.aTo[i], k);
        const s = A.lerp(heroSize * (0.7 + this.seed[i] * 0.8), g.dot, m);
        const ring = k > 0.5 ? this.ringTo[i] : this.ringFrom[i];
        if (ring && m > 0.9) {
          ctx.strokeStyle = `rgba(${r},${gg},${b},${al})`; ctx.lineWidth = Math.max(1, s * 0.22);
          ctx.strokeRect(x - s / 2 + 0.5, y - s / 2 + 0.5, s - 1, s - 1);
        } else {
          ctx.fillStyle = `rgba(${r},${gg},${b},${al})`;
          ctx.fillRect(x - s / 2, y - s / 2, s, s);
        }
      }
    }
  }
  A.Field = Field;
})();
