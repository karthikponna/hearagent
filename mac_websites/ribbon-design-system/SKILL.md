---
name: ribbon-design-system
description: Build a Mac-app marketing site in the Ribbon (meetribbon.app) visual language — a full-bleed pixel-art illustrated hero (blue sky, clouds, sunflowers) with a huge white system-serif headline that italicizes one word, a liquid-glass pill button (SVG turbulence displacement + inset rim shadows), a white pill nav that docks into a notch-shaped tab on scroll, then a calm zinc/white Instrument Sans body with sky-blue eyebrows, white rounded-3xl bento cards containing tiny macOS windows, an interactive fake desktop demo, a handwritten Caveat callout, and a single centered pricing card. Use when the user wants a Ribbon-style page, a playful illustrated hero over a clean product page, a liquid-glass button, a nav that becomes a notch, or to match meetribbon.app colors, fonts, or layout.
disable-model-invocation: true
---

# Ribbon Design System

Reverse-engineered from meetribbon.app (Next.js, Tailwind v4, shadcn tokens). The page is two
moods glued together. First comes a **storybook hero**: an illustrated scene with white serif type.
Then a **quiet Apple-docs body**: zinc on `#f4f4f5`, sky-blue accents, white cards.

## Files

| File | What it is |
|---|---|
| [tokens.css](tokens.css) | Plain-CSS tokens + every signature component (`rb-*` classes), incl. liquid-glass SVG filter |
| `reference/hero.jpg` | Hero at 1440×900 |
| `reference/nav-scrolled-demo.jpg` | Docked nav + interactive desktop demo + mascot |
| `reference/how-it-works-bento.jpg` | Bento grid, guides list |
| `reference/pricing-faq.jpg` | Pricing card + FAQ |
| `reference/full-page.jpg` | Whole page, scaled down |

## Page anatomy (top → bottom)

1. **Promo bar** (optional, dismissible): thin white strip, a green pill label ("BLACK FRIDAY"),
   and a black "Buy now ~~$17~~ $12" pill on the right. It pushes the nav down via `--promo-banner-h`.
2. **Nav**: fixed, centered white pill (`rounded-full p-2`, hairline ring). Brand mark plus
   bold "Ribbon", six 12px/500 neutral-500 links, and a sky-600 "Download" pill with an inset bevel.
   **On scroll it docks**: `mt-0`, `rounded-b-[22px]` with a square top, bigger shadow. It looks
   like a tab hanging from the top edge, the way the notch does.
3. **Hero** (`min-h-screen`, pulled up under the nav with `-mt-20`): full-bleed illustration
   (`object-cover`), headline, lede, and a CTA row with the glass "Download for Mac" pill and a white round
   play button. Under that, a tiny trust line with a shield icon ("Notarized by Apple · Developer ID signed…").
4. **Demo video**: eyebrow, serif h2 ("What is Ribbon?"), tabs with a sky-500 underline,
   and a 16:9 video in `rounded-[1.75rem]` with a white play disc, all on `bg-zinc-950`.
5. **Interactive demo**: a fake macOS desktop (frosted menu bar, wallpaper, draggable windows,
   dock). A handwritten "turn ribbon on" callout with a drawn arrow points at the menu-bar icon,
   which has a dashed pulsing ring.
6. **How it works**: left-aligned head plus a **6-col bento** (rows of 3+3, then 2+2+2, then 3+3).
7. **Learn**: 2/5 intro column plus a 3/5 `divide-y` link list (bold title, grey sub, chevron).
8. **Pricing**: `max-w-xl` centered single card.
9. **FAQ**: 2/5 intro (with "Ask AI about Ribbon" round logo buttons) plus a 3/5 accordion.
10. **Get started**: full-bleed photo with a `zinc-950/50 → /30 → /60` gradient, white
    centered h2, and the same glass button.
11. **Footer**: white, brand blurb, auto-scrolling "featured on" badge marquee, and link columns.
12. **Floating mascot**: a bottom-right frosted rounded-square button with the brand creature. It bobs.

Main container `max-w-6xl px-6` (demo and video go wider: `max-w-[1400px]`), sections separated by
`space-y-16`.

## Colors

| Token | Value | Use |
|---|---|---|
| `--rb-page` | `#f4f4f5` | Body background |
| `--rb-card` | `#fff` | Bento cards, pricing, nav, footer |
| `--rb-sky` | `#5bb2ff` | Hero fallback (matches the sky in the art) |
| `--rb-ink` | zinc-950 | Headings, dark buttons |
| `--rb-ink-2` | zinc-600 | Body copy |
| `--rb-ink-3` | zinc-400 | Fine print, struck-through price |
| `--rb-accent` | sky-600 `oklch(58.8% .158 242)` | Nav Download pill |
| `--rb-accent-hover` | sky-700 | Eyebrows, links, card kickers |
| `--rb-accent-ring` | sky-500 | Focused mini-window border, active tab underline |
| `--rb-bento-art` | `linear-gradient(#f8fafc, #e8f3ff)` | Art area of every bento card |
| `--rb-sale` | emerald-500 | Coupon copy button, sale badge (`emerald-50` + `emerald-700`) |

Cards use a **ring, not a border**: `shadow-sm ring-1 ring-zinc-900/10`. Below the hero, sky
is the only hue. Pastel pinks and lilacs appear only inside the bento art (via a soft abstract
image at 18% opacity).

## Typography

| Role | Font | Size | Weight | Notes |
|---|---|---|---|---|
| Hero h1 | system `serif` | 48 → 72 → 88px (lg, `leading-[1.1]`) → 112px (2xl) | 400 | white, `tracking-tight`, `text-wrap: balance`, one word in *italic* |
| Feature h2 ("What is Ribbon?") | `serif` | 30 → 36px | 600 | the only other serif |
| Section h2 | Instrument Sans | 30 → 36px | 600 | `tracking-tight`, balanced |
| Eyebrow | Instrument Sans | 12px | 600 | uppercase, `tracking-[0.14em]`, sky-700 |
| Card kicker | Instrument Sans | 11px | 600 | uppercase, `tracking-[0.16em]` |
| Card title | Instrument Sans | 20px | 600 | `tracking-tight` |
| Body | Instrument Sans | 16px / 1.75 (cards 14px / 24px) | 400 | zinc-600 |
| Nav links | Instrument Sans | 12px | 500 | neutral-500 → neutral-900 |
| Callout | Caveat | 36–42px | 700 | rotated −7°, paired with a hand-drawn SVG arrow |
| Price | Instrument Sans | 48px | 600 | old price 18px zinc-400 line-through |

## Signature components

- **Liquid-glass button**: transparent pill, 48px tall. Two absolute layers: a rim layer built
  from a stack of inset dark shadows plus a faint white outer glow, and a refraction layer with
  `backdrop-filter: url(#ribbon-liquid-glass)` (feTurbulence → feDisplacementMap scale 70 → blur 4).
  Hover `scale(1.05)` over 300ms. It only reads as glass **over a busy image**, so use it on the hero and the final CTA only.
  Chromium-only refraction; elsewhere it degrades to the rim shadow (still looks fine).
- **Bevel pill**: sky-600 or emerald fill with `inset 0 2px 0 rgba(255,255,255,.2), inset 0 -2px 0 rgba(0,0,0,.2)`. Press `scale(.96)`.
- **Bento card**: white, `rounded-3xl`, ring. A 224px art area on top (gradient + mini windows),
  then `border-t` body with kicker / title / text. Copy embeds round keycaps (`⌃ ⌥ R`).
- **Mini macOS window**: `rounded-xl` white, 24px title bar with 6px traffic lights and 10px
  title. The focused window gets a sky-500 border plus a 2px sky ring. App icons are centered in the body.
- **Fake desktop demo**: `rounded-[22px]` frame `#1d1d1f`, 28px menu bar `bg-white/60 backdrop-blur-xl`
  12px/510 text, wallpaper photo, frosted dock. The menu-bar target gets a dashed 2.5px pulsing ring.
- **Pricing card**: `rounded-[28px]` white, a segmented "1 Mac / 3 Macs / 5 Macs" control
  (zinc-100 track, white selected chip), a big price, a dashed-emerald coupon chip, check list, and full-width dark
  "Buy" plus outline "Download" buttons, both `h-12 rounded-full`.
- **FAQ "Ask AI" row**: 36px round white logo buttons (ChatGPT, Claude, Grok, Perplexity, Gemini)
  that deep-link a pre-filled prompt, then a divider and "Copy as Markdown". Nice for AI-native products.

## Motion

- Hero h1 `hero-rise` (0.9s, from translateY 18px). Lede and CTAs `hero-fade-rise` (0.8s, delays
  .25s / .4s). Ease `cubic-bezier(.16,1,.3,1)`.
- Nav dock transition: 300ms `cubic-bezier(.22,1,.36,1)` on radius / padding / gap / shadow / margin.
- Callout arrow draws in via `stroke-dasharray: 180` (1.1s).
- Footer badges marquee: 50s linear, duplicated set, pauses on hover/focus/button, edge mask 28px.
- Mascot bobs (`translateY` a few px). Everything turns off under `prefers-reduced-motion`.

## Adapting to another product

The hero illustration is Ribbon's own art. **Commission or generate your own** scene in a matching
style (pixel art, sky-dominant, warm subject matter in the lower third, clear sky behind the
headline). Set `--rb-sky` to the sky color sampled from it. Keep the serif white headline with
one italic word, the glass CTA, and the docking nav. Recolor the accent from sky to your brand,
but keep it a single hue.

## Before finishing, verify

- [ ] Hero headline is white **system serif**, weight 400, one italic word, balanced wrap
- [ ] Glass button sits over the illustration, and the SVG filter is in the DOM
- [ ] Nav is a floating pill at the top and docks to a square-top / round-bottom tab on scroll
- [ ] Body switches to Instrument Sans on `#f4f4f5`, cards use ring-1 zinc-900/10 (not borders)
- [ ] Eyebrows are 12px uppercase sky-700 with `0.14em` tracking
- [ ] Only one accent hue below the hero, and pastels appear only inside the bento art
