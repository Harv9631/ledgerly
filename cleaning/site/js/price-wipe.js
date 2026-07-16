/* Salty Air — mop-wipe reveal for the instant-price section.
   Progressive enhancement: without JS or with reduced motion the section
   simply renders; with it, a mop sweeps across and reveals the content. */

(function () {
  var sec = document.getElementById("price");
  if (!sec) return;
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  if (!("IntersectionObserver" in window) || !CSS.supports("mask-size", "300% 100%")) return;

  sec.classList.add("wipe-armed");

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (!en.isIntersecting) return;
      sec.classList.add("wipe-play");
      io.disconnect();
      setTimeout(function () { sec.classList.add("wipe-done"); }, 2200);
    });
  }, { threshold: 0.35 });

  io.observe(sec);
})();
