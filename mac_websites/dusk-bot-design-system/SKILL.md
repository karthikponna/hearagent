---
name: dusk-bot-design-system
description: Build a marketing site in the dusk bot (dusk.bot) visual language — white page, all-lowercase copy, huge tight General Sans headlines (106px, -0.055em), flat pill buttons with no borders or shadows, warm-grey #f5f5f3 "wash" cards with 28/20/12 radii, and a cast of 16×16 pixel-art bot mascots (one electric color each) that live inline in headlines, peek over windows, and react to the cursor. Pixel-art landscape posters (sky, sea, terraces, meadow) hold white cards; pixel-torn strips separate chapters; a tilted lilac marquee tape lists models; a giant pixel "free" is cut out of a meadow image; pastel step cards use stair-stepped clip-path corners. Use when the user wants a dusk-style page, a playful-but-clean AI-agent product site, pixel mascots, lowercase friendly tone, or to match dusk.bot colors, type, or layout.
disable-model-invocation: true
---

# dusk bot Design System

Reverse-engineered from dusk.bot. It's hand-written CSS with comments that explain the intent (keep them).
The page is a **clean Swiss white layout** that a **pixel-art world** keeps breaking into.
The type and buttons stay strict, and the delight comes from the art and the bots.

## Files

| File | What it is |
|---|---|
| [site.css](site.css) | Global: fonts, tokens, nav bar, mobile menu, buttons, footer |
| [home.css](home.css) | Every homepage section (hero, posters, moments, ways, tape, free, pricing, strips, steps, faq, ending) |
| [motion-kit.css](motion-kit.css) | Their motion tokens: springs as `linear()` easings, reveal variants, press |
| [markup.html](markup.html) | Homepage markup (scripts removed, icons collapsed, live demo stubbed) |
| [bots.html](bots.html) | All 10 pixel-bot shapes as inline SVG plus the 12 bot colors. Open it to preview |
| `reference/*.jpg` | Hero, poster + moments, where-cards, tape/free/pricing, terraces/steps, faq/ending |

Link `site.css` → `motion-kit.css` → `home.css` in that order, then wrap the page in
`<main class="home">`. The art (`/art/*.webp`) belongs to dusk, so bring your own.

## Voice (part of the design)

- **Everything lowercase**: headlines, buttons, nav, FAQ ("questions."). Headlines end with a period.
- Short, concrete, second person: "give each bot a job.", "meet your first bot."
- Fine print and meta in mono: "a live demo. click around.", "every weekday at 8:00".

## Page anatomy

1. **Bar**: brand (28px icon + 17px/550 name), right-side text links (15px, pill hover
   `--wash`), a black "sign in" pill. No background, and it doesn't stick.
2. **Hero**: availability pill ("available on  macos · windows · linux"), then h1 `meet [bot] dusk bot`
   with a pixel bot **inline at 0.8em**, then a lede with model chips (logo + name, tinted per brand),
   then a **split download button** (main half + chevron menu for other OSes) next to a wash pill
   "star on github", then a hint line.
3. **Hero stage**: rounded-28 sky illustration, with a **real app window** floating in it (macOS
   lights, title, mono note). Three bots peek over the window's top edge. A "works with" logo row sits below.
4. **Statement**: one giant sentence (56px) with inline bots and tilted sticker images.
5. **Poster**: full-width pixel landscape (sails) with a white card holding a 2-col list of bot jobs.
6. **Moments**: 2×2 wash cards. Each has an h3, a sentence, and a white "fig" with a flat app slice
   (browser with fare list, routines with toggles, notebook, group channel).
7. **Also row**: a tilted pixel phone plus a big sentence plus a row of app-icon tiles that tilt on hover.
8. **Where**: 3 picture cards. Each has a sky picture, a clipped app panel in the corner, and a status dot (awake / asleep / setting up).
9. **Bring your own AI**: h2 plus a **lilac tape rotated −2°** running a marquee of model logos, then 3 fact columns.
10. **Free**: "for personal use, dusk bot is", then a giant pixel word masked out of a meadow image, then 3 green-square bullets.
11. **Pricing**: split head (h2 + monthly/yearly segmented control with a sliding indicator), then 3 wash
    plan cards (art banner on top, 56px price). A sleeping pixel cat sits on top of the first card, with "z z z".
12. **Terrace strip**: full-bleed pixel terraces with pixel-torn edges. Four bots stand on the steps,
    each with a white task chip.
13. **How it works**: 4 pastel stepped-corner cards (`clip-path` pixel corners + colored under-lip).
14. **Every computer**: a scene with CSS-drawn cream laptop, monitor, and pink phone on grass, each showing the app.
15. **FAQ**: left intro plus a big bot "listener". Right side is wash accordions (radius 28, + icon rotates 45°).
16. **Ending**: a sky-gradient strip, white mega h2 "meet your first bot.", dark and light buttons, and bots bobbing in the sea that dive when clicked.
17. **Footer**: brand blurb plus 5 link columns with mono 12.5px headers, and a mono fine-print line.

Rhythm: `--gap: 150px` between sections (104 ≤980px, 84 ≤760px), `.wrap` max 1208px, gutter 16px.

## Tokens

```css
--bg:#fff; --wash:#f5f5f3; --line:#e9e9e6; --ink:#131316; --ink-2:#44444d; --ink-3:#55555f; --text:#4b4b55;
--blue:#2f7bf2; --orange:#ff7d1f; --purple:#8d5cf0; --pink:#ff5c9d; --green:#1fb866; --yellow:#f8c623; --red:#ef4a41; --teal:#17b3a6;
--t-sky:#e2f3ff; --t-lime:#eef8c6; --t-pink:#ffe7ef; --t-lemon:#fff5bf; --lilac:#cdbcff;   /* pastel tints */
--r-xl:28px; --r-l:20px; --r-m:12px;                                                      /* the only 3 radii */
--focus: color-mix(in oklab, var(--ink) 10%, transparent);                                 /* focus = darker tint, never a ring */
```

Bot colors (one per bot, set with `color`): blue `#286ef9`, sky `#04a2ed`, cyan `#1cb7d8`,
violet `#894ef0`, pink `#f12b93`, coral `#f75e51`, tangerine `#fb7c01`, sun `#e5a915`,
lime `#7ac70f`, mint `#26cb96`, emerald `#10a760`, indigo `#4744e2`.

App-slice colors (inside mocks only): message bubble `#126fd4`, surface `#fcfcfc`, sidebar `#f3f3f2`.

## Typography

Fonts (all self-hosted woff2): **General Sans** 200–700 (Fontshare), **Pixelify Sans** 500–700
(pixel accents), **Geist Mono** (meta, chips, fine print). Body is `500 16px/1.55 General Sans`,
and the homepage body runs at **450**.

| Role | Size | Line height | Tracking | Weight |
|---|---|---|---|---|
| Hero h1 | `clamp(48px, 7.4vw, 106px)` | .95 | `-.055em` | 450 |
| Mega (ending) | `clamp(44px, 7.4vw, 104px)` | .96 | `-.055em` | 500 |
| Section h2 | `clamp(32px, 4.3vw, 56px)` | 1.03 | `-.045em` | 500 |
| Statement | `clamp(28px, 4.3vw, 56px)` | 1.12 | `-.04em` | 500 |
| h3 | 22px | 1.2 | `-.03em` | 550 |
| Head sub / lede | 19px (hero 17.5px / 1.85) | 1.5 | `-.012em` | 450 |
| Plan price | 56px | 1 | `-.05em` | 500, tabular-nums |
| Step numeral | Pixelify 64px (px-how cards: General Sans 46px) | .9 | — | 600 |
| Hint / meta | Geist Mono 12.5px | 1.5 | `-.01em` | 500 |

## Components

- **Buttons**: `min-height: 48px`, `padding: 0 24px`, 16px/500, radius 999, **flat, no border,
  no shadow**. Default `#efefed`, dark = `--ink` → hover `#2a2a30`, light = `#fff`. Press `scale(.97)`.
  Split button: main half `999px 0 0 999px` plus a chevron half with an `inset 1px 0 0 rgba(255,255,255,.16)` divider.
  The menu is a white radius-18 popover with a soft shadow, 0.18s scale-in.
- **Wash card**: `--wash` bg, radius 28, padding 30. It holds a white "fig" (radius 20, padding 16).
  There are no borders anywhere. Separation comes from wash versus white.
- **Model chip** (inline in lede): 25px tall, radius 7, logo 15px + name 550,
  `background: color-mix(in oklab, var(--wash) 95%, var(--t))` where `--t` is the brand tint.
- **Segmented control**: wash track radius 999, padding 4, buttons 44px. A white indicator slides with a
  spring (`clip-path` transition). The "2 months free" badge is a mono chip on `--t-sky`.
- **Pixel step card** (`.px-card`): `clip-path: var(--step2)` (10px stair corners), `--wash` fill,
  `box-shadow: inset 0 -8px 0 var(--u)` pastel under-lip. Chips and buttons use the 5px `--step` version.
- **Pixel-torn strip edge**: `::before`/`::after` in page color, masked with a repeating
  scatter-pixel PNG (`/art/scatter-edge.png`), flipped on top. Use it between chapters.
- **Tape marquee**: `background: var(--lilac); rotate: -2deg; margin-inline: -4vw`, items
  `clamp(18px,1.9vw,26px)/550/-.04em` with 1.24em white logo squares, plus a "pause the tape" mono link.
- **Masked word**: `mask: url(word.svg)` over a landscape image placed so the horizon falls
  under the letters' middle bars.
- **FAQ**: wash `details` radius 28, summary 68px min, 19px/550, + icon in a 36px white-75% circle that rotates 45°.
- **Toggle**: 38×22, `#d6d6d1` off and `--blue` on, white 18px knob slides 16px.

## Pixel bots

16×16 grid shapes drawn as `<path>` rects inside `viewBox="0 0 100 100"` at
`translate(10 10) scale(5)` with `shape-rendering="crispEdges"`. The body is `currentColor`, the eyes are
`.px-e` (white). See [bots.html](bots.html). On the live site `mascot.js` redraws them on a
canvas with spring physics (`k`, damping 2√k). Eyes track the pointer, and there are blinks plus moods (`love` with heart eyes and
hops, `surprised` with big eyes and a kick, `sad`, `error` with x-eyes and a shake, `sleeping` with closed eyes, `dizzy`). A click
makes the bot hop. Keep at least: **eyes follow the cursor, click → hop with squash, idle blink**.
Rule of thumb: one bot per idea, never more than ~6 in a viewport, always one flat color.

## Motion (motion-kit.css)

- Reveal: `[data-mk-reveal]` fades in and rises 24px. Variants `clip` (wipe up with image settling from
  1.14 scale), `scale`, `words`, `lines`, `fade`. Stagger 70ms (32ms for words).
- Springs as CSS `linear()` easings: `--mk-ease-spring-ui` (550ms), `--mk-ease-spring` (600ms),
  `--mk-ease-spring-soft` (800ms). Out ease `cubic-bezier(.23,1,.32,1)`, pop `cubic-bezier(.3,1.6,.5,1)`.
- Ambient: clouds drift (90–120s linear), sea bots bob with `steps(3)` (pixel-honest motion),
  phone rings on hover, app tiles tilt ±5° on hover, the cat sleeps with "z z z".
- `prefers-reduced-motion`: every animation and transition is off, and clouds and z's are hidden.

## Adapting to another product

Keep the strict white grid, the lowercase voice, General Sans tight headlines, flat pills, the
three radii, and the wash cards. Replace the art with **your own pixel-art world** (one palette:
saturated sky `#29a9f2` / `#01c0fe`, lime grass, cream sand, pastel clouds) and **your own
mascot** drawn on a 16×16 grid in a single color. Put product truth in flat HTML "slices" of
your app (chat, list, toggle rows), never screenshots.

## Before finishing, verify

- [ ] All copy is lowercase, and headlines end with a period
- [ ] Headlines use General Sans with very tight tracking (−.045 to −.055em), weight 450–500
- [ ] Buttons and cards have no borders or shadows (except the poster's white card `--lift`)
- [ ] Only radii 28 / 20 / 12 / 999 are used
- [ ] Pixel art uses `image-rendering: pixelated`, and bots use `crispEdges`
- [ ] At least one bot sits inline in the hero headline and reacts to the pointer
- [ ] Focus states are a 10% ink tint, not outlines
