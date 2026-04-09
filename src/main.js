/* ============================================================
   LEDGERLY — Main Script
   Canvas animations + GSAP + Chart.js
   ============================================================ */

'use strict';

// ============================================================
// CURSOR
// ============================================================
(function initCursor() {
  if (window.matchMedia('(hover: none)').matches) return;

  const dot  = document.getElementById('cursor-dot');
  const ring = document.getElementById('cursor-ring');
  let aimX = 0, aimY = 0;
  let ringX = 0, ringY = 0;

  document.addEventListener('mousemove', e => {
    aimX = e.clientX; aimY = e.clientY;
    dot.style.left = aimX + 'px';
    dot.style.top  = aimY + 'px';
  });

  (function animateRing() {
    ringX += (aimX - ringX) * 0.12;
    ringY += (aimY - ringY) * 0.12;
    ring.style.left = ringX + 'px';
    ring.style.top  = ringY + 'px';
    requestAnimationFrame(animateRing);
  })();

  document.querySelectorAll('a, button, input').forEach(el => {
    el.addEventListener('mouseenter', () => document.body.classList.add('cursor-hover'));
    el.addEventListener('mouseleave', () => document.body.classList.remove('cursor-hover'));
  });
})();

// ============================================================
// NAV SCROLL STATE
// ============================================================
(function initNav() {
  const nav = document.getElementById('nav');
  const check = () => nav.classList.toggle('scrolled', window.scrollY > 60);
  window.addEventListener('scroll', check, { passive: true });
  check();
})();

// ============================================================
// HERO CANVAS — Financial particle + sparkline background
// ============================================================
function initHeroScene() {
  const canvas = document.getElementById('hero-canvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  let W, H;

  function resize() {
    W = canvas.width  = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }
  resize();
  window.addEventListener('resize', debounce(resize, 250));

  // Particles
  const PARTICLE_COUNT = W < 768 ? 60 : 120;
  const particles = Array.from({ length: PARTICLE_COUNT }, () => ({
    x: Math.random() * W,
    y: Math.random() * H,
    r: Math.random() * 1.5 + 0.3,
    vx: (Math.random() - 0.5) * 0.3,
    vy: (Math.random() - 0.5) * 0.3,
    alpha: Math.random() * 0.5 + 0.1,
  }));

  // Background chart line data
  const LINE_POINTS = 12;
  const incomeData = Array.from({ length: LINE_POINTS }, (_, i) =>
    8000 + Math.sin(i * 0.8) * 2000 + Math.random() * 1500
  );
  const debtData = Array.from({ length: LINE_POINTS }, (_, i) =>
    95000 - i * 800 - Math.random() * 500
  );

  let t = 0;

  function drawBgLine(data, color, alpha, offsetY, scale) {
    const stepX = W / (LINE_POINTS - 1);
    const min = Math.min(...data);
    const max = Math.max(...data);
    const range = max - min || 1;

    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.globalAlpha = alpha;
    ctx.lineWidth = 1.5;

    data.forEach((val, i) => {
      const x = i * stepX;
      const y = offsetY - ((val - min) / range) * scale;
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.stroke();

    // Gradient fill under line
    const grad = ctx.createLinearGradient(0, offsetY - scale, 0, offsetY);
    grad.addColorStop(0, color.replace(')', ', 0.08)').replace('rgb', 'rgba'));
    grad.addColorStop(1, color.replace(')', ', 0)').replace('rgb', 'rgba'));
    ctx.beginPath();
    data.forEach((val, i) => {
      const x = i * stepX;
      const y = offsetY - ((val - min) / range) * scale;
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.lineTo(W, offsetY);
    ctx.lineTo(0, offsetY);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  function frame() {
    requestAnimationFrame(frame);
    ctx.clearRect(0, 0, W, H);
    t += 0.008;

    // Ambient gradient
    const bg = ctx.createRadialGradient(W * 0.65, H * 0.4, 0, W * 0.65, H * 0.4, W * 0.6);
    bg.addColorStop(0, 'rgba(99,102,241,0.04)');
    bg.addColorStop(1, 'transparent');
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    // Animated background lines
    const shiftedIncome = incomeData.map((v, i) => v + Math.sin(t + i * 0.5) * 300);
    const shiftedDebt   = debtData.map((v, i)   => v + Math.cos(t + i * 0.4) * 200);

    drawBgLine(shiftedIncome, 'rgb(99,102,241)',   0.06, H * 0.75, H * 0.25);
    drawBgLine(shiftedDebt,   'rgb(236,72,153)',    0.05, H * 0.6,  H * 0.2);

    // Particles
    particles.forEach(p => {
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0) p.x = W;
      if (p.x > W) p.x = 0;
      if (p.y < 0) p.y = H;
      if (p.y > H) p.y = 0;

      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(196,181,253,${p.alpha})`;
      ctx.fill();
    });
  }

  frame();
}

// ============================================================
// SPARKLINE — hero dashboard net worth mini chart
// ============================================================
function initSparkline() {
  const canvas = document.getElementById('sparkline-canvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  const W = canvas.offsetWidth || 280;
  const H = 60;
  canvas.width  = W * (window.devicePixelRatio || 1);
  canvas.height = H * (window.devicePixelRatio || 1);
  ctx.scale(window.devicePixelRatio || 1, window.devicePixelRatio || 1);

  const data = [38200, 39500, 38900, 41200, 43000, 42400, 44100, 45800, 45200, 47830];
  const min = Math.min(...data) - 1000;
  const max = Math.max(...data) + 500;
  const stepX = W / (data.length - 1);

  function toY(v) { return H - ((v - min) / (max - min)) * (H - 8) - 4; }

  // Gradient fill
  const grad = ctx.createLinearGradient(0, 0, 0, H);
  grad.addColorStop(0, 'rgba(99,102,241,0.3)');
  grad.addColorStop(1, 'rgba(99,102,241,0.0)');

  // Draw line animated
  let progress = 0;

  function draw() {
    ctx.clearRect(0, 0, W, H);
    const drawCount = Math.floor(progress * (data.length - 1));
    const frac      = (progress * (data.length - 1)) % 1;

    if (drawCount < 1) { progress += 0.03; requestAnimationFrame(draw); return; }

    // Fill path
    ctx.beginPath();
    ctx.moveTo(0, toY(data[0]));
    for (let i = 1; i <= drawCount; i++) ctx.lineTo(i * stepX, toY(data[i]));
    if (drawCount < data.length - 1) {
      const x = (drawCount + frac) * stepX;
      const y = toY(data[drawCount] + (data[drawCount + 1] - data[drawCount]) * frac);
      ctx.lineTo(x, y);
    }
    ctx.lineTo(Math.min((drawCount + frac) * stepX, (data.length - 1) * stepX), H);
    ctx.lineTo(0, H);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    // Line
    ctx.beginPath();
    ctx.strokeStyle = '#6366f1';
    ctx.lineWidth   = 2;
    ctx.lineJoin    = 'round';
    ctx.moveTo(0, toY(data[0]));
    for (let i = 1; i <= drawCount; i++) ctx.lineTo(i * stepX, toY(data[i]));
    if (drawCount < data.length - 1) {
      const x = (drawCount + frac) * stepX;
      const y = toY(data[drawCount] + (data[drawCount + 1] - data[drawCount]) * frac);
      ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Dot at end
    const endX = Math.min((drawCount + frac) * stepX, (data.length - 1) * stepX);
    const endI = Math.min(drawCount, data.length - 1);
    const endY = toY(data[endI]);
    ctx.beginPath();
    ctx.arc(endX, endY, 3, 0, Math.PI * 2);
    ctx.fillStyle   = '#818cf8';
    ctx.shadowColor = '#6366f1';
    ctx.shadowBlur  = 8;
    ctx.fill();
    ctx.shadowBlur  = 0;

    if (progress < 1) { progress += 0.025; requestAnimationFrame(draw); }
  }

  draw();
}

// ============================================================
// CTA CANVAS — concentric animated rings (2D)
// ============================================================
function initCtaScene() {
  const canvas = document.getElementById('cta-canvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  let W, H;

  function resize() {
    W = canvas.width  = canvas.parentElement.clientWidth || window.innerWidth;
    H = canvas.height = canvas.parentElement.clientHeight || 600;
  }
  resize();
  window.addEventListener('resize', debounce(resize, 250));

  const RINGS = [
    { r: 90,  color: 'rgba(99,102,241,',  alpha: 0.25, speed: 0.003 },
    { r: 150, color: 'rgba(129,140,248,', alpha: 0.18, speed: -0.002 },
    { r: 210, color: 'rgba(168,85,247,',  alpha: 0.14, speed: 0.0015 },
    { r: 270, color: 'rgba(192,132,252,', alpha: 0.10, speed: -0.001 },
    { r: 330, color: 'rgba(236,72,153,',  alpha: 0.07, speed: 0.0008 },
  ];
  const angles = RINGS.map(() => Math.random() * Math.PI * 2);
  const tilts  = RINGS.map(() => Math.random() * 0.8 + 0.2);

  // Particles around origin
  const pts = Array.from({ length: 80 }, () => {
    const angle = Math.random() * Math.PI * 2;
    const r     = 100 + Math.random() * 260;
    return { angle, r, speed: (Math.random() - 0.5) * 0.002 };
  });

  let t = 0;

  function frameCta() {
    requestAnimationFrame(frameCta);
    ctx.clearRect(0, 0, W, H);
    t += 1;
    const cx = W / 2, cy = H / 2;

    // Core glow
    const core = ctx.createRadialGradient(cx, cy, 0, cx, cy, 60);
    core.addColorStop(0, 'rgba(99,102,241,0.25)');
    core.addColorStop(1, 'rgba(99,102,241,0)');
    ctx.fillStyle = core;
    ctx.beginPath();
    ctx.arc(cx, cy, 60, 0, Math.PI * 2);
    ctx.fill();

    // Rings (ellipses to simulate 3D tilt)
    RINGS.forEach((ring, i) => {
      angles[i] += ring.speed;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(angles[i]);
      ctx.scale(1, tilts[i]);
      ctx.beginPath();
      ctx.arc(0, 0, ring.r, 0, Math.PI * 2);
      ctx.strokeStyle = ring.color + ring.alpha + ')';
      ctx.lineWidth   = 1.5;
      ctx.stroke();
      ctx.restore();
    });

    // Particles
    pts.forEach(p => {
      p.angle += p.speed;
      const x = cx + Math.cos(p.angle) * p.r;
      const y = cy + Math.sin(p.angle) * p.r * 0.55;
      ctx.beginPath();
      ctx.arc(x, y, 1.2, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(139,92,246,0.45)';
      ctx.fill();
    });
  }

  frameCta();
}

// ============================================================
// MAIN CHART — Income vs Debt Payments (Chart.js)
// ============================================================
function initMainChart() {
  const canvas = document.getElementById('main-chart');
  if (!canvas || typeof Chart === 'undefined') return;

  const labels  = ['Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar'];
  const income  = [10200, 11400, 10900, 11800, 12100, 12450];
  const debt    = [3200,  3100,  2950,  3300,  3100,  2840];

  Chart.defaults.color = '#8888b0';
  Chart.defaults.font.family = 'Inter, system-ui, sans-serif';

  new Chart(canvas, {
    type: 'bar',
    data: {
      labels,
      datasets: [
        {
          label: 'Income',
          data: income,
          backgroundColor: 'rgba(99,102,241,0.7)',
          borderColor:     'rgba(99,102,241,1)',
          borderWidth: 1,
          borderRadius: 6,
          borderSkipped: false,
        },
        {
          label: 'Debt Payment',
          data: debt,
          backgroundColor: 'rgba(236,72,153,0.6)',
          borderColor:     'rgba(236,72,153,1)',
          borderWidth: 1,
          borderRadius: 6,
          borderSkipped: false,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: 'rgba(12,12,24,0.9)',
          borderColor:     'rgba(99,102,241,0.3)',
          borderWidth: 1,
          padding: 12,
          callbacks: {
            label: ctx => ` $${ctx.parsed.y.toLocaleString()}`,
          },
        },
      },
      scales: {
        x: {
          grid:  { color: 'rgba(255,255,255,0.04)' },
          ticks: { color: '#8888b0' },
        },
        y: {
          grid:   { color: 'rgba(255,255,255,0.04)' },
          ticks:  { color: '#8888b0', callback: v => '$' + (v / 1000).toFixed(0) + 'k' },
          border: { display: false },
        },
      },
    },
  });
}

// ============================================================
// PERSONAL / BUSINESS TOGGLE
// ============================================================
function initToggle() {
  const toggle = document.getElementById('modeToggle');
  if (!toggle) return;

  const personalData = {
    totalIncome:  '$12,450',
    totalDebt:    '$89,200',
    healthScore:  '78',
    healthGrade:  'Good',
    healthOffset: '66',
  };

  const businessData = {
    totalIncome:  '$48,200',
    totalDebt:    '$312,000',
    healthScore:  '82',
    healthGrade:  'Great',
    healthOffset: '54',
  };

  function applyMode(mode) {
    const d = mode === 'business' ? businessData : personalData;
    const metricVal  = document.querySelector('.dash-metric-val');
    const healthNum  = document.querySelector('.health-num');
    const healthGrade = document.querySelector('.health-grade');
    const ringFill   = document.querySelector('.ring-fill');

    if (metricVal)  {
      metricVal.style.opacity = '0';
      setTimeout(() => {
        metricVal.textContent = mode === 'business' ? '$284,500' : '$47,830';
        metricVal.style.opacity = '1';
      }, 150);
    }
    if (healthNum && healthGrade && ringFill) {
      healthNum.textContent   = d.healthScore;
      healthGrade.textContent = d.healthGrade;
      ringFill.style.strokeDashoffset = d.healthOffset;
    }

    const incomeEl = document.querySelector('.dash-mini-val');
    if (incomeEl) incomeEl.textContent = d.totalIncome;

    const debtEls = document.querySelectorAll('.dash-mini-val');
    if (debtEls[1]) debtEls[1].textContent = d.totalDebt;
  }

  toggle.addEventListener('click', e => {
    const btn = e.target.closest('.mode-btn');
    if (!btn) return;
    toggle.querySelectorAll('.mode-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    applyMode(btn.dataset.mode);

    // Announce mode change to body for CSS hooks
    document.body.dataset.mode = btn.dataset.mode;
  });
}

// ============================================================
// GSAP ANIMATIONS
// ============================================================
function initAnimations() {
  if (typeof gsap === 'undefined') return;
  gsap.registerPlugin(ScrollTrigger);

  // Hero entrance
  const heroTL = gsap.timeline({ delay: 0.3 });
  heroTL
    .to('.hero-badge', { opacity: 1, y: 0, duration: 0.75, ease: 'power3.out' })
    .to('.hero-h1 .line', { opacity: 1, y: 0, duration: 0.75, stagger: 0.12, ease: 'power3.out' }, '-=0.4')
    .to('.hero-sub',      { opacity: 1, y: 0, duration: 0.65, ease: 'power3.out' }, '-=0.45')
    .to('.hero-ctas',     { opacity: 1, y: 0, duration: 0.6,  ease: 'power3.out' }, '-=0.4')
    .to('.hero-stats',    { opacity: 1, y: 0, duration: 0.6,  ease: 'power3.out' }, '-=0.35')
    .to('.hero-dashboard',{ opacity: 1, y: 0, x: 0, duration: 0.9, ease: 'power3.out' }, '-=0.5');

  // Hero parallax
  gsap.to('.hero-content', {
    scrollTrigger: { trigger: '#hero', start: 'top top', end: 'bottom top', scrub: 1.2 },
    y: '22%', opacity: 0.15, ease: 'none',
  });

  // Logo strip
  gsap.from('#logos', {
    scrollTrigger: { trigger: '#logos', start: 'top 90%' },
    opacity: 0, y: 20, duration: 0.8, ease: 'power2.out',
  });

  // Features section header
  gsap.from('#dashboard .section-eyebrow, #dashboard .section-title, #dashboard .section-sub', {
    scrollTrigger: { trigger: '#dashboard', start: 'top 80%' },
    opacity: 0, y: 35, stagger: 0.1, duration: 0.85, ease: 'power3.out',
  });

  // Feature cards
  document.querySelectorAll('.feat-card').forEach((card, i) => {
    gsap.to(card, {
      scrollTrigger: { trigger: card, start: 'top 88%' },
      opacity: 1, y: 0, duration: 0.75, delay: (i % 3) * 0.1, ease: 'power3.out',
    });
  });

  // Tracker sections
  ['#income .tracker-layout', '#debt .tracker-layout'].forEach(sel => {
    gsap.from(sel + ' > *', {
      scrollTrigger: { trigger: sel, start: 'top 80%' },
      opacity: 0, y: 40, stagger: 0.15, duration: 0.8, ease: 'power3.out',
    });
  });

  // Animate progress bars when visible
  const io = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      entry.target.querySelectorAll('.debt-fill, .hf-fill').forEach(bar => {
        const target = bar.style.width;
        bar.style.width = '0%';
        requestAnimationFrame(() => { bar.style.width = target; });
      });
      io.unobserve(entry.target);
    });
  }, { threshold: 0.3 });

  document.querySelectorAll('.fin-panel, .health-card').forEach(el => io.observe(el));

  // Chart card
  gsap.to('.chart-card', {
    scrollTrigger: { trigger: '#reports', start: 'top 75%' },
    opacity: 1, y: 0, duration: 0.9, ease: 'power3.out',
  });

  // CTA
  gsap.to('.cta-content', {
    scrollTrigger: { trigger: '#cta', start: 'top 70%' },
    opacity: 1, y: 0, duration: 1, ease: 'power3.out',
  });
}

// ============================================================
// COUNTER ANIMATIONS
// ============================================================
function initCounters() {
  const els = document.querySelectorAll('.counter');
  if (!els.length || typeof gsap === 'undefined') return;

  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      const el     = entry.target;
      const target = parseInt(el.dataset.target, 10);
      const obj    = { val: 0 };

      gsap.to(obj, {
        val: target,
        duration: 2.2,
        ease: 'power2.out',
        onUpdate: () => { el.textContent = Math.round(obj.val).toLocaleString(); },
      });

      observer.unobserve(el);
    });
  }, { threshold: 0.6 });

  els.forEach(el => observer.observe(el));
}

// ============================================================
// UTILITY — debounce
// ============================================================
function debounce(fn, ms) {
  let id;
  return (...args) => { clearTimeout(id); id = setTimeout(() => fn(...args), ms); };
}

// ============================================================
// BOOT
// ============================================================
window.addEventListener('load', () => {
  initHeroScene();
  initCtaScene();
  initSparkline();
  initMainChart();
  initAnimations();
  initCounters();
  initToggle();

  if (typeof ScrollTrigger !== 'undefined') {
    ScrollTrigger.refresh();
  }
});
