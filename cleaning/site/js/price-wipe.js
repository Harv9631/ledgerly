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

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) { if (en.isIntersecting) play(); });
  }, { threshold: 0, rootMargin: "0px 0px -35% 0px" });
  io.observe(sec);

  // fallback trigger in case the observer misbehaves in any browser
  function fallbackCheck() {
    var r = sec.getBoundingClientRect();
    if (r.top < window.innerHeight * 0.65 && r.bottom > 0) play();
  }
  addEventListener("scroll", fallbackCheck, { passive: true });
  fallbackCheck();

  // absolute backstop: never leave the section masked forever
  setTimeout(function () {
    if (!played) { sec.classList.remove("wipe-armed"); io.disconnect(); }
  }, 15000);
})();
