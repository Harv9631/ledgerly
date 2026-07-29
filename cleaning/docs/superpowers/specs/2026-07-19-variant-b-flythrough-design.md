# Variant B landing page — "Fly-Through" design

**Date:** 2026-07-19
**Status:** Approved (user reviewed a working browser mockup and the chosen footage)
**Mockup:** `.superpowers/brainstorm/1801-1784508790/content/flythrough-mockup-v2.html` (served locally during brainstorming)

## Goal

Build a complete alternative landing page (variant B) to A/B compare against the current
landing page (`site/index.html`, the three.js 3D-house scroll hero). Variant B replaces the
3D hero with a **scroll-driven room-to-room fly-through of real home footage** and restyles
the entire page in a **dark coastal editorial** design language.

References the user loves:

- **lamassuhomes.com** — full-bleed cinematic interior walkthrough video hero
- **Silvia Bianchi Home Design** (Awwwards HM) — dark editorial luxury: enormous serif
  display type, framed imagery, tiny understated nav, generous negative space

Page A is untouched. Comparison is manual (open both URLs); no analytics split in this scope.

## Files

| File | Purpose |
|---|---|
| `site/index-b.html` | Variant B page. Lives beside `index.html` so all relative links (`book.html`, `js/`, `assets/`) work unchanged |
| `site/css/styles-b.css` | All variant-B styling, including the dark re-skin of the quote widget |
| `site/js/flythrough.js` | Scroll engine for the pinned fly-through hero + reveal-on-scroll for below-fold sections |
| `site/assets/video/*.mp4` + `*.jpg` | Self-hosted room clips and poster frames |

Shared, unchanged: `js/quote.js` (instant-price widget), `book.html` booking flow,
Fraunces/Albert Sans fonts.

`site/index.html`, `css/styles.css`, `css/components.css`, and all hero3d files are **not modified**.
Exception: if a components.css rule must change for the dark quote re-skin, override it from
`styles-b.css` instead — never edit shared files.

## Design language (from the approved mockup)

Design tokens:

| Token | Value | Use |
|---|---|---|
| `--navy` | `#0F2C3B` | page background (existing brand navy) |
| `--navy-deep` | `#0A2230` | overlays, panels |
| `--cream` | `#FAF5EB` | primary type |
| `--sand` | `#E3D9C4` | secondary accents, rail dots |
| `--seafoam` | `#8FC3B4` | eyebrows/kickers, italic emphasis |
| `--terra` | `#E08A4E` | chapter numbers, italic display words, solid CTA buttons |
| `--mist` | `rgba(250,245,235,.55)` | body copy on dark |

Type: Fraunces (display, weight ~380–500, italics for accent words), Albert Sans (UI/body).
Editorial conventions: huge serif headings with an italic terracotta accent word, uppercase
letter-spaced kickers in seafoam, thin `rgba(250,245,235,.14)` rules between sections,
`№ 1/2/3` index markers on cards, framed (1px-border) cards and panels, generous vertical
space (~14vh section padding).

Nav: minimal fixed bar — wordmark, four links (Services / Pricing / Areas / FAQ), cream
pill CTA "Get my price" → `book.html`.

## The fly-through hero

Structure: a `~560vh` scroll track containing a `position: sticky; top: 0; height: 100vh`
stage. Five full-viewport chapters, each a `.layer` with a background `<video>`
(object-fit: cover), a navy gradient shade, and chapter copy.

| # | Chapter | Copy | Footage (Pexels ID) |
|---|---|---|---|
| 0 | Arrival | Eyebrow "Home cleaning · Ponte Vedra · Nocatee · Jax Beach"; huge `Salty ↓ Air` spanning the viewport (Bianchi treatment, animated bobbing arrow); lede "Walk through a home the way we leave it…"; "Scroll to enter →" hint | 7578540 (bright open-plan glide) |
| 1 | The Kitchen | `01 — The Kitchen` / "Counters that *gleam* before coffee." + support line | 34955013 |
| 2 | The Living Room | `02 — The Living Room` / "Dust-free, fluffed, *guest-ready*." + support line | **15887137** (user-picked: cozy neutral family room, board-and-batten, fireplace) |
| 3 | The Bath | `03 — The Bath` / "Scrubbed, sanitized, *spa-quiet*." + support line | 8403602 |
| 4 | Finale | Centered: eyebrow "Ready when you are"; "See your price before you say *hello*."; buttons **Get my instant price** (→ `#price`) + **Explore services** (→ `#services`) | 34954996 (bedroom) |

Scroll behavior (mirrors the validated mockup implementation):

- Scroll progress `p = -track.top / (track.height - 100vh)`, each chapter owns a `1/5` segment.
- Crossfade in the last **18%** of each segment: outgoing layer fades to 0 while the incoming
  fades to 1 ("the video goes from one room to another").
- Chapter copy drifts vertically ~18px across its segment for parallax life.
- Videos: muted, loop, playsinline. Only the active chapter ±1 plays; others pause.
  First clip `preload="auto"`, the rest `preload="metadata"` + poster.
- Progress rail fixed at the stage's right edge: five dots with uppercase labels
  (Arrive / Kitchen / Living / Bath / Bedroom), active dot terracotta with a soft ring.

## Footage pipeline

Source: Pexels (free for commercial use, no attribution required). Download the HD rendition
of each chosen clip (1920×1080 where available, else best ≤2160p), then optimize:
trim to ~6–10 s loops, re-encode H.264 ~2–4 Mbps, target **≤5 MB per clip**, strip audio.
Extract a poster JPEG from the first frame of each. Store as
`site/assets/video/{arrival,kitchen,living,bath,bedroom}.mp4` + matching `-poster.jpg`.

Known-good source URLs (resolved during brainstorming):

- arrival: `videos.pexels.com/video-files/7578540/7578540-hd_1280_720_30fps.mp4`
- kitchen: `videos.pexels.com/video-files/15887298/15887298-hd_1920_1080_30fps.mp4` (swapped 2026-07-29 — brighter white/coastal kitchen per Harvey)
- living: `videos.pexels.com/video-files/15887137/15887137-hd_1920_1080_30fps.mp4`
- bath: `videos.pexels.com/video-files/8403602/8403602-hd_1280_720_30fps.mp4`
- bedroom: `videos.pexels.com/video-files/34954996/14806924_3840_2160_25fps.mp4` (downscale)

If ffmpeg is unavailable locally, self-host the smallest acceptable source rendition as-is
(720p clips are already ~3–8 MB) and note the follow-up.

## Below the fold — full content parity with page A

Same copy as `index.html`, restyled editorial-dark, in this order:

1. **Services** (`#services`) — kicker + "Three ways to come home to *fresh*." Three framed
   cards (`№ 1` The Standard — featured with seafoam tint, `№ 2` The Deep Clean, `№ 3`
   Move In/Out) with the full bullet lists from page A.
2. **How it works** (`#how`) — three numbered steps, same copy as page A.
3. **Guarantee quote band** — the reclean promise as a full-width centered Fraunces quote.
4. **Instant price** (`#price`) — split layout: left, kicker + "Price your clean in
   *60 seconds*." + lede; right, **the real quote widget**: `<div id="quote-mount"
   data-mode="teaser">` with `js/quote.js` loaded, fully functional (live price updates,
   add-ons, CTA carries selections to `book.html?…`). `styles-b.css` re-skins
   `.quote-card` for dark: navy-deep panel, thin cream borders, cream/sand text, terracotta
   price + CTA. Functionality and markup untouched.
5. **Service area** (`#areas`) — chip list, same areas + "St. Augustine — coming soon".
6. **FAQ** (`#faq`) — same six `<details>` items, dark-styled.
7. **Final CTA** — "Enjoy life. We'll handle *the cleaning*." + terracotta button → `book.html`.
8. **Footer** — same content/links as page A, minus the Sketchfab 3D-model credit (no 3D on
   this page). No footage attribution needed (Pexels license requires none).

SEO/meta: reuse page A's `<title>` and meta description verbatim, plus
`<meta name="robots" content="noindex">` while it's an experiment.

## Motion & fallbacks

- Zero dependencies (no GSAP/three.js): rAF-throttled scroll handler + IntersectionObserver
  reveals (`opacity/translateY`, ~0.9s `cubic-bezier(.2,.65,.25,1)`, staggered delays).
- `prefers-reduced-motion: reduce` → videos never play (posters show), crossfades become
  instant opacity swaps, reveals render visible; page scrolls normally.
- No-JS → hero shows the arrival poster + copy statically (track collapses to 100vh via
  `<noscript>` CSS); all content below remains readable.
- Mobile: same chapters; copy sizes clamp down; rail labels hide (dots remain). Videos are
  small enough to stream on LTE; `poster` paints instantly.
- Apply the installed motion/design skills during implementation: `transitions-dev` +
  `transitions-polish` for easing/timing, `high-end-visual-design` / `design-taste-frontend`
  for typography and spacing QA.

## Performance budget

- No three.js, no external JS. Page weight dominated by video: ≤5 MB × 5 clips, lazy-loaded
  (only the first preloads).
- Videos pause when their chapter is inactive and when the tab is hidden.
- Fonts already cached from page A (same Google Fonts request).

## Verification

1. `serve-site.bat` local server; browse `index-b.html`.
2. Playwright pass in Chrome + Firefox: screenshot each chapter (0/25/45/65/95% of track),
   the quote widget interaction (change beds → price updates, CTA href carries params),
   and below-fold sections.
3. Reduced-motion emulation: posters shown, no autoplay.
4. Mobile viewport (390×844) sweep.
5. Confirm page A (`index.html`) byte-identical / untouched via `git status`.

## Out of scope

- Analytics/split-testing infrastructure (manual comparison for now).
- Any change to page A, booking flow, or pricing logic.
- AI-generated continuous single-take footage (future option if stock chapters feel
  disjointed).
