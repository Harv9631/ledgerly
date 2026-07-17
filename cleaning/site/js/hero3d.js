/* Salty Air — 3D scroll hero bootstrap.
   The inline head script adds .hero3d-on when WebGL is available and motion is
   allowed; this module boots the scene and removes the class if anything fails,
   which restores the static .hero-fallback hero. */

const root = document.documentElement;

function abortToFallback(err) {
  console.warn("hero3d: falling back to static hero —", err);
  root.classList.remove("hero3d-on", "hero3d-ready");
}

async function boot() {
  if (!root.classList.contains("hero3d-on")) return;

  const track = document.querySelector(".hero3d-track");
  const canvas = document.getElementById("hero3d-canvas");
  if (!track || !canvas) return abortToFallback("missing markup");

  let scene;
  try {
    const mod = await import("./hero3d-scene.js?v=20260716e");
    scene = await mod.createScene(canvas, {
      onContextDead: () => abortToFallback("webgl context lost"),
    });
  } catch (err) {
    return abortToFallback(err);
  }

  root.classList.add("hero3d-ready");

  // --- scroll → progress -------------------------------------------------
  const overlays = {
    s1: track.querySelector(".hero3d-s1"),
    s2: track.querySelector(".hero3d-s2"),
    s3: track.querySelector(".hero3d-s3"),
  };

  // Each overlay fades in/out over a window of progress: [in0, in1, out0, out1]
  const WINDOWS = {
    s1: [0.0, 0.0, 0.14, 0.3],
    s2: [0.38, 0.48, 0.58, 0.68],
    s3: [0.78, 0.9, 1.01, 1.02],
  };

  function windowOpacity(p, [a, b, c, d]) {
    if (p <= a) return a === b ? 1 : 0;
    if (p < b) return (p - a) / (b - a);
    if (p <= c) return 1;
    if (p < d) return 1 - (p - c) / (d - c);
    return 0;
  }

  let target = 0;
  let smooth = -1; // force first paint
  const pointer = { x: 0, y: 0 };

  function readScroll() {
    const rect = track.getBoundingClientRect();
    const span = track.offsetHeight - window.innerHeight;
    target = span > 0 ? Math.min(1, Math.max(0, -rect.top / span)) : 0;
  }

  addEventListener("scroll", readScroll, { passive: true });
  addEventListener("resize", () => { readScroll(); scene.resize(); }, { passive: true });
  addEventListener("pointermove", (e) => {
    pointer.x = (e.clientX / window.innerWidth) * 2 - 1;
    pointer.y = (e.clientY / window.innerHeight) * 2 - 1;
  }, { passive: true });
  readScroll();

  let lastT = 0;
  function frame(t) {
    const dt = lastT ? (t - lastT) / 1000 : 1 / 60;
    lastT = t;
    // time-based smoothing: same feel at any frame rate
    const k = 1 - Math.exp(-(Math.abs(target - smooth) > 0.2 ? 10 : 5.5) * dt);
    smooth += (target - smooth) * k;
    if (Math.abs(target - smooth) < 0.0005) smooth = target;

    for (const key of Object.keys(overlays)) {
      const el = overlays[key];
      if (!el) continue;
      const o = windowOpacity(smooth, WINDOWS[key]);
      el.style.opacity = o.toFixed(3);
      el.classList.toggle("is-live", o > 0.5);
    }

    scene.update(smooth, pointer, t);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

boot();
