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
      layer.style.visibility = o === 0 ? "hidden" : "visible";

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
