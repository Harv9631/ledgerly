# 3D Scroll-Driven "Dirty → Clean" Hero — Design Spec

**Date:** 2026-07-16
**Site:** Salty Air Home Cleaning (`cleaning/site/`, static HTML/CSS/JS, no build step)
**Reference:** likova.space technique — full-screen Three.js canvas, scroll scrubs a cinematic 3D scene. Contained here to a pinned hero (design Option A, user-approved).
**Aesthetic reference:** Fab "Suburban Modular House Pack" (warm realistic American suburban home). Pack itself unusable (Unreal-only, license); look matched with a web-ready CC-BY model instead.

## Experience

1. Visitor lands on a gloomy, grimy realistic 3D house — overcast sky, dusty air, dead lawn. Headline: "Some homes just lose their sparkle."
2. The hero pins (~400vh scroll track, `position: sticky` stage) while scroll scrubs the transformation: camera orbits and pushes in, grime wipes off roof-down, sky turns golden, lawn greens, dust motes become sparkles.
3. At the end, the clean sunny house holds; final headline ("The freshest clean on the First Coast."), trust strip, CTA and the instant-quote teaser card fade in beside it. Pin releases into the existing site (wave divider → Services), unchanged below.

## Architecture

- Three.js pinned-version ES module via importmap + CDN; no bundler.
- `site/index.html`: hero replaced with `.hero3d-track` > `.hero3d-stage` (sticky, 100vh) containing canvas + 3 overlay stages. Existing hero preserved in `.hero-fallback`.
- `site/js/hero3d.js`: boot/capability check, scroll→progress with lerp smoothing, overlay choreography, fallback switch.
- `site/js/hero3d-scene.js`: GLTF load, lights/sky/ground/particles, transformation timeline. (Files kept <500 lines each.)
- `site/assets/models/house.glb`: CC-BY model, gltf-transform optimized, ≤4 MB. Attribution in footer.
- `#quote-mount` element is moved (not duplicated) into overlay stage 3 when 3D boots; `js/quote.js` untouched.

## Dirty→clean mechanics

- **Grime:** `onBeforeCompile` patch on model materials; `uGrime` uniform drives noise-based darkening/desaturation with a roof-down wipe front. Works over any baked textures.
- **Environment:** hemisphere/sun color+intensity lerp (overcast→golden), sky gradient to linen/seaglass brand tones, fog fade, exposure ramp.
- **Ground/greenery:** lawn color lerp, small instanced flowers scale in late.
- **Particles:** dust motes cross-fade to rising sparkles (two THREE.Points systems).
- **Camera:** keyframed orbit+push-in scrubbed by progress; ±2° mouse parallax.

## Fallbacks

No WebGL / `prefers-reduced-motion` / model-load failure → static `.hero-fallback` (today's hero exactly); track collapses. Mobile keeps 3D with lighter settings (smaller pixel ratio, fewer particles, 300vh track).

## Model selection gate

3–5 realistic CC-BY suburban candidates rendered in the actual scene, dirty+clean screenshots presented in the visual companion; Harvey picks. Fallback if none pass: stylized procedural cottage (pre-agreed).

## Verification

Playwright over local server: screenshots at progress 0/0.5/1, console clean, quote card interactive at stage 3, fallback paths render today's hero, mobile 390×844 run, ≤4 MB model / ~200 KB JS gzipped / 60 fps scrub spot-check.
