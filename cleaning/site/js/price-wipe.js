/* Salty Air — mop-wipe reveal for the instant-price section.
   Progressive enhancement: without JS or with reduced motion the section
   simply renders. Belt-and-suspenders: if anything prevents the animation
   from running, .wipe-done clears the mask so content can never stay hidden. */

(function () {
  var sec = document.getElementById("price");
  if (!sec) return;
  if (window.innerWidth < 640) return; // phones: plain section, no theatrics
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  if (!window.CSS || !CSS.supports || !CSS.supports("mask-size", "300% 100%")) return;
  if (!("IntersectionObserver" in window)) return;

  sec.classList.add("wipe-armed");
  var played = false;

  function play() {
    if (played) return;
    played = true;
    sec.classList.add("wipe-play");
    io.disconnect();
    removeEventListener("scroll", fallbackCheck);
    // whatever happens with the animation, force the final state afterwards
    setTimeout(function () { sec.classList.add("wipe-done"); }, 2300);
  }

  // fire only once the section substantially fills the view — triggering the
  // one-shot sweep the moment the top edge peeks up meant most visitors
  // (still reading the hero finale) never saw it
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) { if (en.intersectionRatio >= 0.55) play(); });
  }, { threshold: [0.55] });
  io.observe(sec);

  // fallback trigger: section top well inside the viewport (covers short
  // windows where the 0.55 area ratio is unreachable, and any IO quirks)
  function fallbackCheck() {
    var r = sec.getBoundingClientRect();
    if (r.top < window.innerHeight * 0.35 && r.bottom > window.innerHeight * 0.5) play();
  }
  addEventListener("scroll", fallbackCheck, { passive: true });
  fallbackCheck();

  // absolute backstop: never leave the section masked forever
  setTimeout(function () {
    if (!played) { sec.classList.remove("wipe-armed"); io.disconnect(); }
  }, 15000);
})();
