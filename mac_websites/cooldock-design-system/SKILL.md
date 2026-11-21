---
name: cooldock-design-system
description: Build a premium Mac-utility marketing site in the CoolDock (cooldock.app, CSS Design Awards winner) visual language — warm grey #edeceb canvas, Inter Display 700 headlines with very tight tracking (80px/-4px hero, 60px/-3px sections), a frosted 610px pill nav, a hero with a photographic landscape video, a glassy macOS desktop mock holding a black widget dock, and photoreal 3D rocks framing the edges (WebGL fluid reveal on hover). Below come #f7f7f7 radius-30 cards, a grid of real black widget tiles, video panels, a two-column testimonial wall, an auto-scrolling screenshot marquee, three pricing cards flanked by rocks, and a pinned black CTA where a wall of widgets zooms out on scroll into the app icon. Use when the user wants a CoolDock-style page, an award-style product site with a 3D-object hero, a scroll-zoom widget wall, a widget/dock showcase, or to match cooldock.app colors, type, or layout.
disable-model-invocation: true
---

# CoolDock Design System

Reverse-engineered from cooldock.app (Laravel + Vite, BEM `cd-*` classes). Neutral and photographic,
with one loud accent. Most of the drama comes from **real-looking objects** (3D rocks, product
widgets) and **choreographed motion**. The UI chrome stays plain.

## Files

| File | What it is |
|---|---|
| [components.css](components.css) | De-minified production CSS for every `cd-*` block (tokens, nav, hero, widgets, testimonials, marquee, pricing, FAQ, CTA, footer), media queries included |
| [motion.js](motion.js) | Hero intro trigger, blur-rise reveal, and the scroll-driven CTA widget wall (exact math from the bundle) |
| `reference/hero.jpg` | Standard hero (landscape, desktop mock, rocks) |
| `reference/hero-black-friday-variant.jpg` | Seasonal hero takeover (stroked display type + hands holding 3D icons) |
| `reference/features-awards.jpg`, `widget-categories.jpg`, `testimonials.jpg`, `marquee-pricing.jpg` | Sections |
| `reference/cta-wall-start.jpg` → `cta-wall-mid.jpg` → `cta-wall-end.jpg` | The CTA scroll sequence |

## Page anatomy

1. **Nav**: fixed `top: 20px`, centered **610px** frosted bar (`#fffc` + `blur(10px)`, radius 18,
   `inset 1px 1px 1px #fff` top-left highlight, 52.8px tall). Grid layout: 30px brand icon +
   name, links, and a small black "Download" (radius 8, 32.8px tall) on the right.
2. **Hero** (1326px tall, `max-width: 1800px`):
   - background **landscape video** (misty hills) with 454px top / 350px bottom fades into the canvas
   - eyebrow ` Your smart second Dock · by [logo] AppitStudio` (20px/600)
   - h1 **80px / 80px, −4px, 700**, two lines; description 20/28 `#5f6062`; CTA pill (radius 20, 52px)
   - trust row of 12px grey items
   - **desktop mock** 948×533: translucent glass (`#fff3`, blur, inset white highlights,
     radius 30), white menubar, black **notch** (200×40, radius `0 0 20px 20px`), and a black
     **dock** (869×100, `#000000e6`, radius 30) of widgets (time, weather, apps, progress ring, music)
   - two **3D rocks** (500px PNGs) overlapping the mock bottom corners. Hovering one starts a WebGL
     fluid-distortion reveal (`cd-rock-fluid` canvas)
3. **Features**: four circular CSSDA award badges (90px) above the h2 "Everything useful, one
   Dock away", a description, a wrapped row of 12px `#f7f7f7` chips (one per capability), and a
   1280:830 product video panel (radius 30).
4. **Featured testimonial**: stars, quote, avatar. Centered and small.
5. **Widget categories**: centered h2 + 2-col grid of `#f7f7f7` radius-30 cards (488px tall,
   padding 40). Each has a 30px title, a paragraph, "Includes: …", and a flex-wrap of **real widget tiles**
   (black rounded rectangles at half scale).
6. **Customization**: a small pill badge (partner logo), h2, description, and a 1120:730 black video panel.
7. **Testimonials**: "Loved by Mac Users", then 2 columns of `#f7f7f7` radius-30 cards (padding 40,
   italic 16px quote at 60% opacity, X logo top-right, 60px round avatar, optional screenshot).
8. **CTA widget wall** (`#widgets`, black, about 3900px of scroll): see Motion.
9. **Screenshot marquee**: 400px-tall desktop screenshots, 20px gap, 40s linear loop.
10. **Pricing**: "Pricing" h2 + "One-time payment. No subscription.", then 3 cards with rocks behind the
    outer two. The middle card is featured: white, taller (620 vs 540), with a device segmented control.
11. **FAQ**: "Frequently Asked Questions" h2, then a 1000px 2-column grid (gap 20) of `#f7f7f7`
    radius-20 items, + icon on the left.
12. **Closing badge marquee** (featured-on logos, edge fades) and **footer** (2fr + 5 columns,
    with a background image fading into the canvas at the bottom).

Shell width 1200px, side padding 40px (20px mobile). Section padding is usually `100px 40px 200px`.

## Colors

| Token | Value | Use |
|---|---|---|
| `--cd-canvas` | `#edeceb` | Page (warm grey; every fade targets it) |
| `--cd-surface` | `#f7f7f7` | Cards, chips, FAQ items, testimonials |
| `--cd-white` | `#fff` | Featured pricing card, nav fill (80%) |
| `--cd-ink` | `#000` | Headings, primary button, dock, CTA section |
| `--cd-muted` | `#65666a` | Secondary text (hero description `#5f6062`, trust `#7b7c7b`) |
| `--cd-line` | `#00000014` | Hairlines |
| `--cd-brand` | `#006fff` | Links, tag chips (`#006fff1a` bg) |
| Sale accent | `#cf0` (lime) | Sale CTAs only: `color #121212`, `box-shadow 0 10px 28px #ccff0059` |
| Widget glass | `#ffffff1a` + `inset 0 0 0 1px #ffffff1a` | Tiles inside the black dock |

Keep the page grayscale. The only saturated color comes from **product widgets** (system-color
icons, rings `#34c759`-style green, blue `#0a84ff`) and the one lime sale button.

## Typography

**Inter Display** (700/800) for everything display, **Inter** for small text. Tracking is set in
**px and scales with size**, roughly −5% of the font size.

| Role | Desktop | Tablet | Mobile | Weight |
|---|---|---|---|---|
| Hero h1 | 80/80, −4px | — | — | 700 |
| Section h2 | 60/60, −3px | 48/48, −2.4px | 38/38, −1.9px | 700 |
| Card title | 30/30, −1.5px | — | 19/19, −.95px | 700 |
| Pricing name | 25/1.2, −1px | | | 650 |
| Lead / description | 20/28, −.2px | 18/25.2 | 16/22.4 | 400 |
| Body / quote | 16/22.4, −.16px | | | 400 (quotes italic, 60% opacity) |
| Chip / meta | 12/19.2 | | | 500 |

## Components

- **Buttons** (`.cd-button`): 48px, radius 13, 0.92rem/700, `transition .18s cubic-bezier(.2,.7,.2,1)`.
  Primary is black with `0 10px 28px #0000002b`. Secondary is `#ffffff8c` with a hairline. Hero and CTA buttons are 52.4px,
  radius 20, 16px/600. **On `:active` the radius jumps to 40px** (a squish-to-pill press).
- **Card** (`.cd-widget-category`, `.cd-testimonial`): `#f7f7f7`, radius 30, padding 40, no border,
  no shadow. Radius scale: 10 / 20 / 30 / 40.
- **Widget tile**: black or `#ffffff1a` on black, radius about 20 at full size, 80px tall in the
  dock. Rendered as real product PNGs scaled with `--cd-widget-media-scale` (.5 desktop).
- **Pricing card**: `#f7f7f7`, 1px `#fffc` border, radius 32, padding `32 28 28`,
  `0 12px 36px #1a1e230a`. Featured: white, `0 20px 50px #1a1e231a`. The badge pill straddles the top edge
  (`translate(-50%,-50%)`). Check icons at 40% opacity. Full-width button radius 20.
- **FAQ item**: `#f7f7f7`, radius 20, summary padding `20px 0 20px 40px`, icon absolutely placed at left.
- **Awards row**: 90px circular badges, gap 10, centered, above the section heading.

## Motion

- **Hero intro** (one `cd-hero-is-ready` class): the scene video scales 1.04 → 1. The heading rises at
  .3s. The description and desktop mock come in at 1s (the menubar fades, the progress ring draws). The CTA, trust row, rocks,
  and header (dropping from −53px) arrive at 1.5s. The eyebrow letters blur in one by one (10px blur, +10px,
  50ms apart). Ease is a spring-like `linear(0, .081, .242, … 1)`. Any keyboard focus skips it.
- **Reveal** (`[data-cd-reveal]`): `blur(7px) translateY(22px) scale(.985)` → none, .65–.76s.
- **CTA widget wall**: a sticky wall of 75 widget tiles (gap 20) starts at **scale 2, 490px low, transparent**.
  Over the first 79% of the section it settles to scale 1 and full opacity. Over the last 21% it shrinks to
  0.1 and fades, while the 120px app icon scales 1.5 → 1 and rises 300px. Then come the white 60px h2, a 60%
  white description, and the CTA. The layout is the sticky wall frame, a 2000px spacer, and a 720px text frame. The exact
  math is in `motion.js`.
- **Marquees**: screenshots 40s linear, closing badges 40s with 48px edge gradients.
- **Rocks**: on pointer hover a WebGL fluid sim distorts and reveals the rock texture (lazy-loaded,
  disabled on touch and reduced motion). A static PNG is the fallback.
- Reduced motion: the intro is skipped, reveals show immediately, the CTA becomes static (no spacer), and the marquees stop.

## Adapting to another product

Keep the canvas, Inter Display tracking scale, radius-30 surface cards, frosted 610px nav, and
the staged hero intro. Replace the rocks with **your own hero object(s)** (3D renders of something
tactile that relates to the product), the dock with **your product's signature UI strip**,
and the widget wall with **a dense grid of your real UI states**. The scroll zoom-out works for
any "look how much it does" moment. Use a lime-style accent only for a sale. Otherwise stay black.

## Before finishing, verify

- [ ] Canvas is `#edeceb` and every image or video edge fades into it (no hard edges)
- [ ] Headlines are Inter Display 700 with px tracking about −5% of the size
- [ ] Cards are `#f7f7f7` radius 30 with no borders or shadows (pricing cards are the exception)
- [ ] The hero has a real-object layer (3D renders) overlapping the product mock
- [ ] The CTA wall zooms 2× → 1× on scroll and hands off to the icon + headline on black
- [ ] Buttons squish to radius 40 on press
- [ ] Reduced motion leaves a fully static, readable page
