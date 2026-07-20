# Variant B Fly-Through Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `site/index-b.html` — a dark-editorial alternative landing page whose hero is a scroll-driven room-to-room video fly-through, with the real instant-price widget, for A/B comparison against `site/index.html`.

**Architecture:** A static page beside page A. A ~560vh scroll track pins a full-viewport stage; five video chapters crossfade as scroll progresses (vanilla rAF scroll engine, no libraries). Below the fold, page A's content restyled dark-editorial. The existing `js/quote.js` widget mounts unmodified; its look is re-skinned by redefining the CSS custom properties `components.css` consumes.

**Tech Stack:** Plain HTML/CSS/JS. `ffmpeg` (installed, winget build 8.1) for video optimization. Pexels stock clips (free license). Python preview server (`serve-site.bat` → `http://localhost:8317`). Playwright MCP for verification.

**Spec:** `docs/superpowers/specs/2026-07-19-variant-b-flythrough-design.md`

**Hard rule from spec:** `site/index.html`, `css/styles.css`, `css/components.css`, `js/quote.js`, and all hero3d files are NOT modified. All variant-B styling lives in `css/styles-b.css`.

---

### Task 1: Download and optimize the five room clips

**Files:**
- Create: `site/assets/video/arrival.mp4`, `kitchen.mp4`, `living.mp4`, `bath.mp4`, `bedroom.mp4`
- Create: `site/assets/video/arrival-poster.jpg`, `kitchen-poster.jpg`, `living-poster.jpg`, `bath-poster.jpg`, `bedroom-poster.jpg`

- [ ] **Step 1: Download source clips to a temp dir** (Git Bash)

```bash
mkdir -p /c/Users/harve/cleaning/site/assets/video
TMP=$(mktemp -d)
curl -sL -o "$TMP/arrival-src.mp4" "https://videos.pexels.com/video-files/7578540/7578540-hd_1280_720_30fps.mp4"
curl -sL -o "$TMP/kitchen-src.mp4" "https://videos.pexels.com/video-files/34955013/14806923_3840_2160_25fps.mp4"
curl -sL -o "$TMP/living-src.mp4"  "https://videos.pexels.com/video-files/15887137/15887137-hd_1920_1080_30fps.mp4"
curl -sL -o "$TMP/bath-src.mp4"    "https://videos.pexels.com/video-files/8403602/8403602-hd_1280_720_30fps.mp4"
curl -sL -o "$TMP/bedroom-src.mp4" "https://videos.pexels.com/video-files/34954996/14806924_3840_2160_25fps.mp4"
ls -la "$TMP"
echo "TMP=$TMP"
```

Expected: five files, each 2–80 MB (the 4K ones are large; that's fine, they get re-encoded next). If any file is under 100 KB the download failed — re-resolve that ID via `curl -s -o /dev/null -w "%{redirect_url}" "https://www.pexels.com/download/video/<ID>/"` and retry.

- [ ] **Step 2: Re-encode each to a ≤5 MB, ≤1080p, ~9 s muted loop + extract poster**

```bash
cd /c/Users/harve/cleaning/site/assets/video
for name in arrival kitchen living bath bedroom; do
  ffmpeg -y -i "$TMP/$name-src.mp4" -t 9 -an \
    -vf "scale='min(1920,iw)':-2" \
    -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart \
    "$name.mp4"
  ffmpeg -y -i "$name.mp4" -frames:v 1 -q:v 4 "$name-poster.jpg"
done
ls -la
```

Expected: 5 mp4 + 5 jpg. Check sizes: any mp4 over 5 MB → re-run just that one with `-crf 28`.

- [ ] **Step 3: Sanity-play one clip** — open `site/assets/video/living.mp4` duration/size:

```bash
ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 living.mp4
```

Expected: `duration≈9.0`, `size` under 5242880.

- [ ] **Step 4: Commit**

```bash
cd /c/Users/harve/cleaning
git add site/assets/video
git commit -m "feat(cleaning): self-hosted room clips + posters for variant B fly-through

Co-Authored-By: claude-flow <ruv@ruv.net>"
```

---

### Task 2: `css/styles-b.css` — full variant-B stylesheet

**Files:**
- Create: `site/css/styles-b.css`

`index-b.html` loads **`components.css` then `styles-b.css`** (never `styles.css`). The
`:root` block below redefines every custom property `components.css` uses, which re-skins the
quote widget dark without touching shared files.

- [ ] **Step 1: Write the file** — complete content:

```css
/* Salty Air — Variant B "fly-through" page. Dark coastal editorial.
   Loaded AFTER components.css; the :root remap below dark-skins the quote widget. */

:root {
  /* variant-B design tokens */
  --navy: #0F2C3B;
  --navy-deep: #0A2230;
  --cream: #FAF5EB;
  --sand: #E3D9C4;
  --seafoam: #8FC3B4;
  --terra: #E08A4E;
  --terra-deep: #C97435;
  --mist: rgba(250, 245, 235, 0.55);

  /* remap of the tokens components.css consumes (quote widget dark re-skin) */
  --white: #0A2230;                          /* card background */
  --line: rgba(250, 245, 235, 0.18);         /* borders */
  --linen: #0F2C3B;                          /* select / segmented bg */
  --linen-deep: #081B26;                     /* price readout bg */
  --ink: #FAF5EB;                            /* primary text */
  --ink-soft: rgba(250, 245, 235, 0.62);     /* secondary text */
  --ocean: #FAF5EB;                          /* .seg .on bg (cream on navy) */
  --seaglass: #8FC3B4;
  --seaglass-soft: rgba(143, 195, 180, 0.14);
  --coral: #E08A4E;
  --coral-deep: #C97435;
  --shadow-lg: 0 24px 60px -24px rgba(0, 0, 0, 0.6);
  --shadow-sm: 0 10px 30px -18px rgba(0, 0, 0, 0.6);
  --radius: 18px;
  --font-display: "Fraunces", Georgia, serif;
  --font-body: "Albert Sans", "Segoe UI", sans-serif;
}

* { margin: 0; padding: 0; box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  font-family: var(--font-body);
  background: var(--navy);
  color: var(--cream);
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
  overflow-x: hidden;
}
img, svg, video { display: block; max-width: 100%; }
a { color: inherit; }
.serif { font-family: var(--font-display); }

/* ---------- buttons ---------- */
.btn {
  display: inline-block;
  text-decoration: none;
  font-weight: 700;
  font-size: 14.5px;
  letter-spacing: 0.04em;
  padding: 15px 32px;
  border-radius: 100px;
  transition: transform 0.18s, background 0.18s;
}
.btn:hover { transform: translateY(-2px); }
.btn-primary { background: var(--terra); color: #12100C; box-shadow: 0 10px 24px -10px rgba(224, 138, 78, 0.5); }
.btn-primary:hover { background: var(--terra-deep); }
.btn-line { border: 1px solid rgba(250, 245, 235, 0.45); color: var(--cream); }
.btn-line:hover { background: rgba(250, 245, 235, 0.1); }

/* ---------- nav ---------- */
.nav-b {
  position: fixed; top: 0; left: 0; right: 0; z-index: 50;
  display: flex; justify-content: space-between; align-items: center;
  padding: 24px 4vw;
  background: linear-gradient(180deg, rgba(10, 34, 48, 0.55), transparent);
}
.nav-b .logo { display: flex; align-items: center; gap: 10px; text-decoration: none; }
.nav-b .logo-name { font-weight: 700; letter-spacing: 0.02em; }
.nav-b .logo-name em { font-family: var(--font-display); font-style: italic; }
.nav-b .links { display: flex; gap: 28px; font-size: 12.5px; letter-spacing: 0.14em; text-transform: uppercase; }
.nav-b .links a { color: var(--mist); text-decoration: none; transition: color 0.15s; }
.nav-b .links a:hover { color: var(--cream); }
.nav-b .nav-cta {
  font-size: 12.5px; letter-spacing: 0.14em; text-transform: uppercase;
  color: var(--navy-deep); background: var(--cream);
  padding: 10px 20px; border-radius: 100px; text-decoration: none; font-weight: 700;
}

/* ---------- fly-through hero ---------- */
.track { height: 560vh; position: relative; }
.stage { position: sticky; top: 0; height: 100vh; overflow: hidden; }
.layer { position: absolute; inset: 0; opacity: 0; }
.layer video { width: 100%; height: 100%; object-fit: cover; filter: saturate(0.92); }
.layer .shade {
  position: absolute; inset: 0;
  background: linear-gradient(180deg, rgba(10,34,48,0.62) 0%, rgba(10,34,48,0.28) 38%, rgba(10,34,48,0.55) 100%);
}
.layer.arrival .shade {
  background: linear-gradient(180deg, rgba(10,34,48,0.55) 0%, rgba(10,34,48,0.35) 45%, rgba(10,34,48,0.78) 100%);
}

.copy {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; justify-content: flex-end;
  padding: 0 4vw 9vh;
  pointer-events: none;
}
.copy .eyebrow-b {
  font-size: 12px; letter-spacing: 0.26em; text-transform: uppercase;
  color: var(--seafoam); margin-bottom: 18px; font-weight: 600;
}
.copy .num { font-family: var(--font-display); font-style: italic; color: var(--terra); font-size: clamp(15px, 1.4vw, 20px); margin-bottom: 10px; }
.copy h2 {
  font-family: var(--font-display); font-weight: 400;
  font-size: clamp(2.6rem, 6vw, 5.2rem); line-height: 1.02; letter-spacing: -0.01em; max-width: 14em;
}
.copy h2 em { font-style: italic; color: var(--terra); }
.copy p { margin-top: 16px; max-width: 34em; color: var(--mist); font-size: clamp(15px, 1.25vw, 18px); line-height: 1.55; }

/* arrival chapter */
.arrival-copy .eyebrow-b { margin-bottom: 2vh; }
.big-title { display: flex; align-items: baseline; justify-content: space-between; width: 100%; gap: 2vw; }
.big-title .w { font-family: var(--font-display); font-weight: 380; font-size: clamp(4rem, 15.5vw, 15rem); line-height: 0.9; letter-spacing: -0.02em; }
.big-title .arrow { font-family: var(--font-display); font-size: clamp(2rem, 6vw, 5rem); color: var(--sand); animation: bob 2.6s ease-in-out infinite; }
@keyframes bob { 0%, 100% { transform: translateY(-0.6vw); } 50% { transform: translateY(0.6vw); } }
.arrival-sub { display: flex; justify-content: space-between; align-items: flex-end; margin-top: 3.5vh; gap: 4vw; }
.arrival-sub p { font-size: clamp(14px, 1.15vw, 17px); color: var(--mist); max-width: 30em; line-height: 1.6; margin: 0; }
.arrival-sub .hint { font-size: 11px; letter-spacing: 0.24em; text-transform: uppercase; color: var(--sand); white-space: nowrap; }

/* finale chapter */
.finale-copy { justify-content: center; align-items: center; text-align: center; }
.finale-copy h2 { max-width: 11em; }
.finale-copy .btns { margin-top: 34px; pointer-events: auto; display: flex; gap: 14px; justify-content: center; flex-wrap: wrap; }

/* progress rail */
.rail { position: absolute; right: 3vw; top: 50%; transform: translateY(-50%); display: flex; flex-direction: column; gap: 22px; z-index: 5; }
.rail .stop { display: flex; align-items: center; gap: 12px; flex-direction: row-reverse; opacity: 0.42; transition: opacity 0.3s; }
.rail .stop.on { opacity: 1; }
.rail .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--sand); }
.rail .stop.on .dot { background: var(--terra); box-shadow: 0 0 0 4px rgba(224, 138, 78, 0.25); }
.rail .lbl { font-size: 10.5px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--cream); }

/* ---------- below the fold ---------- */
section { padding: 14vh 4vw; }
.rule { width: 100%; height: 1px; background: rgba(250, 245, 235, 0.14); }
.kicker { font-size: 12px; letter-spacing: 0.26em; text-transform: uppercase; color: var(--seafoam); font-weight: 600; display: block; margin-bottom: 22px; }
.ed-h { font-family: var(--font-display); font-weight: 400; font-size: clamp(2.2rem, 4.6vw, 4rem); line-height: 1.05; letter-spacing: -0.01em; }
.ed-h em { font-style: italic; color: var(--terra); }
.ed-lede { color: var(--mist); line-height: 1.6; margin-top: 18px; max-width: 34em; }

/* services */
.svc { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2.5vw; margin-top: 8vh; }
.svc .card { border: 1px solid rgba(250, 245, 235, 0.16); padding: 34px 30px 38px; position: relative; }
.svc .card.feat { background: rgba(143, 195, 180, 0.07); border-color: rgba(143, 195, 180, 0.4); }
.svc .idx { font-family: var(--font-display); font-style: italic; color: var(--terra); font-size: 15px; }
.svc h3 { font-family: var(--font-display); font-weight: 500; font-size: clamp(1.4rem, 2vw, 1.9rem); margin: 14px 0 6px; }
.svc .tag { font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: var(--seafoam); }
.svc ul { list-style: none; margin-top: 18px; }
.svc li { color: var(--mist); font-size: 14.5px; line-height: 1.6; padding: 6px 0 6px 22px; position: relative; }
.svc li::before { content: "—"; position: absolute; left: 0; color: var(--seafoam); }

/* how it works */
.how-b { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2.5vw; margin-top: 8vh; }
.how-b .step { border-top: 1px solid rgba(250, 245, 235, 0.16); padding-top: 24px; }
.how-b .idx { font-family: var(--font-display); font-style: italic; color: var(--terra); font-size: 15px; }
.how-b h3 { font-family: var(--font-display); font-weight: 500; font-size: 1.35rem; margin: 12px 0 10px; }
.how-b p { color: var(--mist); font-size: 14.5px; line-height: 1.65; }

/* guarantee quote band */
.quote-band { text-align: center; padding: 16vh 4vw; }
.quote-band .q { font-family: var(--font-display); font-weight: 380; font-size: clamp(1.8rem, 3.6vw, 3.2rem); line-height: 1.2; max-width: 24em; margin: 0 auto; }
.quote-band .q em { font-style: italic; color: var(--seafoam); }
.quote-band .who { margin-top: 26px; font-size: 12px; letter-spacing: 0.22em; text-transform: uppercase; color: var(--mist); }

/* instant price */
.price-flex-b { display: grid; grid-template-columns: 1fr 1fr; gap: 5vw; align-items: start; }
.price-flex-b .quote-card { border-radius: var(--radius); }
.q-price-num { color: var(--terra) !important; }           /* price pops terracotta, not cream */
.addon:has(input:checked) { background: rgba(143, 195, 180, 0.14); }

/* areas */
.area-chips-b { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 8vh; max-width: 640px; }
.chip-b { border: 1px solid rgba(250, 245, 235, 0.25); border-radius: 100px; padding: 10px 20px; font-size: 14px; color: var(--cream); }
.chip-b.soon { border-style: dashed; color: var(--mist); }

/* FAQ */
.faq-b { margin-top: 8vh; max-width: 760px; }
.faq-b details { border-top: 1px solid rgba(250, 245, 235, 0.16); }
.faq-b details:last-child { border-bottom: 1px solid rgba(250, 245, 235, 0.16); }
.faq-b summary {
  cursor: pointer; list-style: none; padding: 22px 0;
  font-family: var(--font-display); font-weight: 500; font-size: 1.2rem;
  display: flex; justify-content: space-between; align-items: center; gap: 16px;
}
.faq-b summary::after { content: "+"; color: var(--terra); font-size: 1.4rem; font-family: var(--font-body); }
.faq-b details[open] summary::after { content: "–"; }
.faq-b details p { color: var(--mist); font-size: 15px; line-height: 1.65; padding: 0 0 22px; max-width: 60ch; }

/* final CTA + footer */
.final-b { padding: 18vh 4vw; text-align: center; }
.final-b .ed-h { max-width: 14em; margin: 0 auto; }
footer { padding: 40px 4vw 60px; display: flex; justify-content: space-between; color: var(--mist); font-size: 13px; flex-wrap: wrap; gap: 12px; }
footer a { color: var(--sand); }

/* reveal-on-scroll */
.reveal { opacity: 0; transform: translateY(34px); transition: opacity 0.9s cubic-bezier(0.2, 0.65, 0.25, 1), transform 0.9s cubic-bezier(0.2, 0.65, 0.25, 1); }
.reveal.in { opacity: 1; transform: none; }

/* ---------- motion & responsive fallbacks ---------- */
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .big-title .arrow { animation: none; }
  .reveal { opacity: 1; transform: none; transition: none; }
}

@media (max-width: 820px) {
  .nav-b .links { display: none; }
  .svc, .how-b { grid-template-columns: 1fr; }
  .price-flex-b { grid-template-columns: 1fr; }
  .rail .lbl { display: none; }
  .copy { padding-bottom: 12vh; }
}
```

- [ ] **Step 2: Commit**

```bash
cd /c/Users/harve/cleaning
git add site/css/styles-b.css
git commit -m "feat(cleaning): variant B dark-editorial stylesheet with quote widget re-skin

Co-Authored-By: claude-flow <ruv@ruv.net>"
```

---

### Task 3: `js/flythrough.js` — scroll engine

**Files:**
- Create: `site/js/flythrough.js`

- [ ] **Step 1: Write the file** — complete content:

```js
/* Salty Air variant B — fly-through scroll engine + section reveals.
   No dependencies. Reduced-motion users get posters (videos never play). */

(function () {
  const track = document.getElementById("track");
  if (!track) return;

  const layers = [...track.querySelectorAll(".layer")];
  const stops = [...document.querySelectorAll("#rail .stop")];
  const N = layers.length;
  const FADE = 0.18; // fraction of each chapter segment used to crossfade
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  let active = -1;
  let ticking = false;

  function playPause(idx) {
    layers.forEach((l, i) => {
      const v = l.querySelector("video");
      if (!v) return;
      if (!reduced && !document.hidden && Math.abs(i - idx) <= 1) {
        if (v.paused) v.play().catch(() => {});
      } else if (!v.paused) {
        v.pause();
      }
    });
  }

  function update() {
    ticking = false;
    const vh = innerHeight;
    const rect = track.getBoundingClientRect();
    const total = track.offsetHeight - vh;
    const p = clamp(-rect.top / total, 0, 1);
    const seg = 1 / N;

    layers.forEach((layer, i) => {
      const start = i * seg;
      const end = (i + 1) * seg;
      let o = 0;
      if (p >= start && p < end) o = 1;
      if (i > 0 && p >= start - seg * FADE && p < start) o = (p - (start - seg * FADE)) / (seg * FADE);
      if (p >= end - seg * FADE && p < end && i < N - 1) o = 1 - (p - (end - seg * FADE)) / (seg * FADE);
      if (i === N - 1 && p >= 1 - seg) o = 1;
      layer.style.opacity = clamp(o, 0, 1).toFixed(3);
      layer.style.zIndex = Math.round(clamp(o, 0, 1) * 10);

      const local = clamp((p - start) / seg, 0, 1);
      const copy = layer.querySelector(".copy");
      if (copy && !reduced) copy.style.transform = "translateY(" + ((1 - local) * 18 - 9).toFixed(2) + "px)";
    });

    const idx = clamp(Math.floor(p / seg), 0, N - 1);
    if (idx !== active) {
      active = idx;
      stops.forEach((s, i) => s.classList.toggle("on", i === idx));
      playPause(idx);
    }
  }

  function onScroll() {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(update);
    }
  }

  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", onScroll);
  document.addEventListener("visibilitychange", () => playPause(active));
  update();

  // reveal-on-scroll for below-fold sections
  const io = new IntersectionObserver(
    (entries) =>
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      }),
    { threshold: 0.18 }
  );
  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));
})();
```

- [ ] **Step 2: Commit**

```bash
cd /c/Users/harve/cleaning
git add site/js/flythrough.js
git commit -m "feat(cleaning): fly-through scroll engine for variant B

Co-Authored-By: claude-flow <ruv@ruv.net>"
```

---

### Task 4: `site/index-b.html` — the page

**Files:**
- Create: `site/index-b.html`

Copy notes: all section copy below is taken verbatim from `site/index.html` (content parity
per spec); hero chapter copy is from the approved mockup. The quote widget mounts with
`data-mode="teaser"` exactly like page A.

- [ ] **Step 1: Write the file** — complete content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Salty Air Home Cleaning — House Cleaning in Ponte Vedra, Nocatee &amp; Jax Beach, FL</title>
  <meta name="description" content="Five-star recurring home cleaning in Ponte Vedra Beach, Nocatee, Sawgrass and Jacksonville Beach. Price your clean online in 60 seconds. Insured, bonded, background-checked pros and a 100% reclean guarantee.">
  <meta name="robots" content="noindex">
  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40'%3E%3Ccircle cx='20' cy='20' r='19' fill='%230F2C3B'/%3E%3Cpath d='M7 22c3.5-3 6.5-3 10 0s6.5 3 10 0 5-2.5 6-1.5' stroke='%238FC3B4' stroke-width='2.2' stroke-linecap='round' fill='none'/%3E%3Cpath d='M9 27c3-2.4 5.5-2.4 8.5 0s6 2.4 9 0' stroke='%23E08A4E' stroke-width='2.2' stroke-linecap='round' fill='none'/%3E%3Ccircle cx='27' cy='12' r='3.5' fill='%23FAF5EB'/%3E%3C/svg%3E">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,300..700;1,9..144,300..700&family=Albert+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="css/components.css?v=20260719b">
  <link rel="stylesheet" href="css/styles-b.css?v=20260719b">
  <noscript>
    <style>
      .track { height: auto; }
      .stage { position: static; }
      .layer { position: absolute; }
      .layer.arrival { position: relative; opacity: 1; }
      .rail { display: none; }
      .reveal { opacity: 1; transform: none; }
    </style>
  </noscript>
</head>
<body>

<nav class="nav-b">
  <a class="logo" href="#top" aria-label="Salty Air Home Cleaning">
    <svg width="34" height="34" viewBox="0 0 40 40" fill="none" aria-hidden="true">
      <circle cx="20" cy="20" r="19" fill="#0F2C3B" stroke="rgba(250,245,235,.4)"/>
      <path d="M7 22c3.5-3 6.5-3 10 0s6.5 3 10 0 5-2.5 6-1.5" stroke="#8FC3B4" stroke-width="2.2" stroke-linecap="round"/>
      <path d="M9 27c3-2.4 5.5-2.4 8.5 0s6 2.4 9 0" stroke="#E08A4E" stroke-width="2.2" stroke-linecap="round"/>
      <circle cx="27" cy="12" r="3.5" fill="#FAF5EB"/>
    </svg>
    <span class="logo-name">Salty <em>Air</em></span>
  </a>
  <div class="links">
    <a href="#services">Services</a>
    <a href="#how">How it works</a>
    <a href="#price">Pricing</a>
    <a href="#areas">Areas</a>
    <a href="#faq">FAQ</a>
  </div>
  <a class="nav-cta" href="book.html">Get my price</a>
</nav>

<div class="track" id="track" aria-label="Scroll to fly through the house, room by room">
  <div class="stage">

    <div class="layer arrival" data-ch="0">
      <video muted loop playsinline preload="auto" poster="assets/video/arrival-poster.jpg" src="assets/video/arrival.mp4"></video>
      <div class="shade"></div>
      <div class="copy arrival-copy">
        <span class="eyebrow-b">Home cleaning &middot; Ponte Vedra &middot; Nocatee &middot; Jax Beach</span>
        <div class="big-title">
          <span class="w">Salty</span><span class="arrow">&darr;</span><span class="w">Air</span>
        </div>
        <div class="arrival-sub">
          <p>Walk through a home the way we leave it. Vetted local pros, priced online in sixty seconds, backed by a 100% reclean guarantee.</p>
          <span class="hint">Scroll to enter &rarr;</span>
        </div>
      </div>
    </div>

    <div class="layer" data-ch="1">
      <video muted loop playsinline preload="metadata" poster="assets/video/kitchen-poster.jpg" src="assets/video/kitchen.mp4"></video>
      <div class="shade"></div>
      <div class="copy">
        <div class="num">01 — The Kitchen</div>
        <h2>Counters that <em>gleam</em> before coffee.</h2>
        <p>Counters, sink and appliance fronts polished. Floors mopped to a shine. The room you use most, reset every visit.</p>
      </div>
    </div>

    <div class="layer" data-ch="2">
      <video muted loop playsinline preload="metadata" poster="assets/video/living-poster.jpg" src="assets/video/living.mp4"></video>
      <div class="shade"></div>
      <div class="copy">
        <div class="num">02 — The Living Room</div>
        <h2>Dust-free, fluffed, <em>guest-ready.</em></h2>
        <p>Every surface dusted, floors vacuumed and mopped, cushions straightened, glass polished. Drop-in company? Bring it on.</p>
      </div>
    </div>

    <div class="layer" data-ch="3">
      <video muted loop playsinline preload="metadata" poster="assets/video/bath-poster.jpg" src="assets/video/bath.mp4"></video>
      <div class="shade"></div>
      <div class="copy">
        <div class="num">03 — The Bath</div>
        <h2>Scrubbed, sanitized, <em>spa-quiet.</em></h2>
        <p>Tile, grout and fixtures detail-scrubbed. Mirrors spotless. The kind of clean you can smell from the hallway.</p>
      </div>
    </div>

    <div class="layer" data-ch="4">
      <video muted loop playsinline preload="metadata" poster="assets/video/bedroom-poster.jpg" src="assets/video/bedroom.mp4"></video>
      <div class="shade"></div>
      <div class="copy finale-copy">
        <span class="eyebrow-b">Ready when you are</span>
        <h2>See your price before you say <em>hello.</em></h2>
        <p style="max-width:28em">Sixty seconds, five questions, zero phone calls.</p>
        <div class="btns">
          <a class="btn btn-primary" href="#price">Get my instant price</a>
          <a class="btn btn-line" href="#services">Explore services</a>
        </div>
      </div>
    </div>

    <div class="rail" id="rail" aria-hidden="true">
      <div class="stop on"><span class="lbl">Arrive</span><span class="dot"></span></div>
      <div class="stop"><span class="lbl">Kitchen</span><span class="dot"></span></div>
      <div class="stop"><span class="lbl">Living</span><span class="dot"></span></div>
      <div class="stop"><span class="lbl">Bath</span><span class="dot"></span></div>
      <div class="stop"><span class="lbl">Bedroom</span><span class="dot"></span></div>
    </div>
  </div>
</div>

<section id="services">
  <span class="kicker reveal">Services</span>
  <h2 class="ed-h reveal">Three ways to come home to <em>fresh.</em></h2>
  <p class="ed-lede reveal">Every clean is done by a vetted local pro team and rated by you afterward. Under four stars? We come back and make it right — free.</p>
  <div class="svc">
    <div class="card feat reveal">
      <span class="idx">№ 1 &middot; Most popular</span>
      <h3>The Standard</h3>
      <span class="tag">Weekly &middot; bi-weekly &middot; monthly</span>
      <ul>
        <li>All rooms dusted, vacuumed &amp; mopped</li>
        <li>Kitchen counters, sink &amp; appliance exteriors</li>
        <li>Bathrooms scrubbed &amp; sanitized</li>
        <li>Beds made, mirrors &amp; glass polished</li>
        <li>Trash emptied, tidy-up throughout</li>
      </ul>
    </div>
    <div class="card reveal" style="transition-delay:.12s">
      <span class="idx">№ 2</span>
      <h3>The Deep Clean</h3>
      <span class="tag">First visits &amp; seasonal resets</span>
      <ul>
        <li>Everything in The Standard, plus:</li>
        <li>Baseboards, door frames &amp; switch plates</li>
        <li>Inside microwave, cabinet fronts</li>
        <li>Ceiling fans &amp; light fixtures</li>
        <li>Detail scrub of tile, grout &amp; fixtures</li>
      </ul>
    </div>
    <div class="card reveal" style="transition-delay:.24s">
      <span class="idx">№ 3</span>
      <h3>Move In / Move Out</h3>
      <span class="tag">Empty-home top-to-bottom</span>
      <ul>
        <li>Everything in The Deep Clean, plus:</li>
        <li>Inside all cabinets, drawers &amp; closets</li>
        <li>Inside fridge &amp; oven included</li>
        <li>Garage &amp; entryway sweep-out</li>
        <li>Realtor &amp; landlord friendly scheduling</li>
      </ul>
    </div>
  </div>
</section>

<div class="rule"></div>

<section id="how">
  <span class="kicker reveal">How it works</span>
  <h2 class="ed-h reveal">Booked in minutes, spotless <em>for good.</em></h2>
  <div class="how-b">
    <div class="step reveal">
      <span class="idx">Step 01</span>
      <h3>Price it in 60 seconds</h3>
      <p>Answer five quick questions about your home and see your exact price on screen. No phone tag, no in-home estimates, no surprises on the invoice.</p>
    </div>
    <div class="step reveal" style="transition-delay:.12s">
      <span class="idx">Step 02</span>
      <h3>A vetted local pro arrives</h3>
      <p>We match your home with an experienced, background-checked, insured cleaning team from your own community — and keep the same team on your recurring schedule.</p>
    </div>
    <div class="step reveal" style="transition-delay:.24s">
      <span class="idx">Step 03</span>
      <h3>Rate every single clean</h3>
      <p>After each visit you rate the clean from your phone. Anything under four stars and we return to reclean, free. Your rating decides who keeps cleaning your home.</p>
    </div>
  </div>
</section>

<div class="rule"></div>

<div class="quote-band">
  <p class="q reveal">&ldquo;If any clean isn&rsquo;t a five-star clean, tell us within 24 hours and we&rsquo;ll <em>reclean it free.</em> No forms, no arguing, no fine print.&rdquo;</p>
  <p class="who reveal">— The Salty Air promise, on every single visit</p>
</div>

<div class="rule"></div>

<section id="price">
  <div class="price-flex-b">
    <div>
      <span class="kicker reveal">Instant price</span>
      <h2 class="ed-h reveal">Price your clean in <em>60 seconds.</em></h2>
      <p class="ed-lede reveal">Five quick questions, your exact price on screen — no phone tag, no in-home estimates, no surprises.</p>
    </div>
    <div class="reveal">
      <div id="quote-mount" data-mode="teaser"></div>
    </div>
  </div>
</section>

<div class="rule"></div>

<section id="areas">
  <span class="kicker reveal">Service area</span>
  <h2 class="ed-h reveal">Proudly serving <em>St. Johns &amp; Duval.</em></h2>
  <p class="ed-lede reveal">We keep our service area tight on purpose — local teams, short drives, and cleans that start on time.</p>
  <div class="area-chips-b reveal">
    <span class="chip-b">Ponte Vedra Beach</span>
    <span class="chip-b">Nocatee</span>
    <span class="chip-b">Sawgrass</span>
    <span class="chip-b">Palm Valley</span>
    <span class="chip-b">Jacksonville Beach</span>
    <span class="chip-b">Atlantic Beach</span>
    <span class="chip-b soon">St. Augustine — coming soon</span>
  </div>
</section>

<div class="rule"></div>

<section id="faq">
  <span class="kicker reveal">FAQ</span>
  <h2 class="ed-h reveal">Good questions, <em>straight answers.</em></h2>
  <div class="faq-b reveal">
    <details>
      <summary>Who actually cleans my home?</summary>
      <p>Independent professional cleaning teams from right here on the First Coast. Every team is background-checked, insured, experienced, and rated by homeowners after every single visit — only the best-rated teams keep getting matched with homes.</p>
    </details>
    <details>
      <summary>Do I get the same team every time?</summary>
      <p>Yes — recurring customers are matched with a dedicated team so they learn your home and your preferences. If your team is ever unavailable, we'll offer a backup team with equally strong ratings before your visit.</p>
    </details>
    <details>
      <summary>Do I need to supply anything?</summary>
      <p>No. Teams bring their own professional supplies and equipment. If you prefer specific products used in your home (or all-natural only), just note it on your booking and we'll match accordingly.</p>
    </details>
    <details>
      <summary>What about pets?</summary>
      <p>We love them. Just tell us about your pets when you book so your team knows who'll be greeting them at the door.</p>
    </details>
    <details>
      <summary>What if I need to cancel or reschedule?</summary>
      <p>Life happens — reschedule or skip any visit free with 24 hours' notice. No contracts, no cancellation fees, pause anytime.</p>
    </details>
    <details>
      <summary>Why is the first clean priced as a deep clean?</summary>
      <p>The first visit brings your home up to our maintainable standard — baseboards, fixtures, detail work — so every recurring visit after it stays fast, consistent, and affordably priced.</p>
    </details>
  </div>
</section>

<section class="final-b">
  <span class="kicker reveal">Ready when you are</span>
  <h2 class="ed-h reveal">Enjoy life. We&rsquo;ll handle <em>the cleaning.</em></h2>
  <div style="margin-top:36px" class="reveal">
    <a class="btn btn-primary" href="book.html">Price my clean &rarr;</a>
  </div>
</section>

<footer>
  <span>&copy; 2026 Salty Air Home Cleaning LLC. All rights reserved.</span>
  <span><a href="mailto:hello@saltyairhomecleaning.com">hello@saltyairhomecleaning.com</a> &middot; <a href="tel:+19045550134">(904) 555-0134</a></span>
  <span>Insured &amp; bonded &middot; Serving St. Johns &amp; Duval counties</span>
</footer>

<script src="js/quote.js?v=20260719b"></script>
<script src="js/flythrough.js?v=20260719b"></script>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
cd /c/Users/harve/cleaning
git add site/index-b.html
git commit -m "feat(cleaning): variant B fly-through landing page

Co-Authored-By: claude-flow <ruv@ruv.net>"
```

---

### Task 5: Browser verification (Playwright MCP against the local server)

**Files:** none created — verification only. Fix-and-commit anything found.

- [ ] **Step 1: Start the preview server** (background)

```bash
python /c/Users/harve/cleaning/scripts/serve.py
```

(or double-click `serve-site.bat`). Server: `http://localhost:8317`.

- [ ] **Step 2: Chapter sweep at 1440×900.** With Playwright, navigate to
`http://localhost:8317/index-b.html`, then for each fraction f in
`[0.02, 0.25, 0.45, 0.65, 0.95]`: `scrollTo(0, (track.offsetHeight - innerHeight) * f)`,
wait ~1.5 s, screenshot. **Read each screenshot** and check: correct room video visible,
correct chapter copy, rail dot advanced, arrival shows `Salty ↓ Air` full-width, finale
shows both CTAs.

Note: use `document.getElementById('track').offsetHeight` from the live page — a fixed
pixel scroll can land short (this bit us during mockup verification).

- [ ] **Step 3: Quote widget functional check.** Scroll to `#price`, then:

```js
// in page context
const before = document.querySelector('#q-num').textContent;
document.querySelector('#q-beds').value = '5';
document.querySelector('#q-beds').dispatchEvent(new Event('change'));
const after = document.querySelector('#q-num').textContent;
const href = document.querySelector('#q-cta').href;
JSON.stringify({before, after, href});
```

Expected: `after !== before` (price increased) and `href` contains `book.html?beds=5`.
Screenshot the widget — dark card, cream text, terracotta price, no illegible elements.

- [ ] **Step 4: Reduced-motion check.** Emulate `prefers-reduced-motion: reduce`
(Playwright: `page.emulateMedia({reducedMotion: 'reduce'})`), reload, screenshot arrival +
one mid chapter. Expected: posters/paused frames visible (no playing video), page still
scrolls through chapters, reveals visible without animation.

- [ ] **Step 5: Mobile sweep at 390×844.** Repeat the chapter fractions + `#price` widget
screenshot. Expected: title fits, copy legible, rail shows dots only, widget single-column.

- [ ] **Step 6: Firefox pass.** Repeat Step 2 quickly in Firefox if available
(`browser_run_code_unsafe` currently drives Chromium; if a Firefox channel isn't available in
the Playwright MCP, note it and verify manually later).

- [ ] **Step 7: Page A untouched check**

```bash
cd /c/Users/harve/cleaning && git status --short site/
```

Expected: no modifications to `index.html`, `css/styles.css`, `css/components.css`, `js/quote.js`,
or any `hero3d*` file.

- [ ] **Step 8: Commit any fixes** discovered during verification (one commit per fix,
`fix(cleaning): …` with the co-author trailer).

---

## Self-review notes (done at plan time)

- **Spec coverage:** files table → Tasks 1–4; hero chapters/copy/footage → Task 4 (HTML) +
  Task 1 (assets); scroll behavior + pausing + reduced motion → Task 3; dark quote re-skin +
  real widget → Task 2 `:root` remap + Task 4 mount; content parity sections → Task 4;
  noindex → Task 4 head; verification list → Task 5. Analytics split: out of scope (spec).
- **Type consistency:** element IDs `#track`, `#rail`, `.layer[data-ch]`, `.copy`, `.reveal`
  match between Task 2 CSS, Task 3 JS, Task 4 HTML. Widget IDs (`#q-num`, `#q-beds`,
  `#q-cta`, `#quote-mount`) match `js/quote.js` as shipped.
- **Known judgment call:** `--ocean` remapped to cream makes `.seg button.on` cream-on-navy;
  `.q-price-num` gets an explicit terracotta override so the price doesn't blend in.
```
