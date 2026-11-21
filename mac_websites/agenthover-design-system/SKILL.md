---
name: agenthover-design-system
description: Build a Mac-app marketing site in the Agent Hover (agenthover.app) visual language — warm off-white #fafaf9 Apple-calm canvas, Inter Variable with a medium-weight headline whose second line is italic, a single teal accent (#12a394 → #0b8a7d gradient pill button), a floating frosted pill nav with an active dot, a big screenshot carousel with thumbnails, and a 3×N grid of grey tiles that each hold a tiny hand-built UI mockup (notch, ⌘ keys, permission prompt, meters, kanban). Light/dark themes. Use when the user wants an Agent Hover-style page, a quiet native-Mac / developer-tool landing page, "mini UI mockup" feature tiles, or to match agenthover.app colors, type, or layout.
disable-model-invocation: true
---

# Agent Hover Design System

Reverse-engineered from the live agenthover.app (Astro, a single page, about 25 KB of CSS).
The look comes from restraint: one font, one accent, hairline borders, generous space, and
product UI drawn small in HTML instead of pictures.

## Files

| File | What it is |
|---|---|
| [site.css](site.css) | The production stylesheet, de-minified. Tokens, light/dark, every component |
| [markup.html](markup.html) | Live page markup (scripts stripped, slider trimmed to 2 slides). Class names match `site.css` |
| [behavior.js](behavior.js) | Theme toggle, screenshot slider, scroll reveal, plan switch, rewritten readably |
| `reference/*.jpg` | Hero, feature tiles, pricing, and full-page captures |

Start from `site.css` + `markup.html`. Don't re-derive values. Swap the copy, keep the system.

## Page anatomy (top → bottom)

1. **Floating pill nav**: sticky at `top: 14px`, centered, *content-width* (not full-width).
   Brand (22px rounded icon + bold name), 4 anchor links, a 28px round theme toggle.
2. **Hero**: badge with laurel SVGs → h1 → lede → 2 pill CTAs → fine print.
   A soft teal radial glow (`--hero-glow`) sits behind it (`.hero:before`, 620px tall).
3. **Screenshot slider**: 16:10 stage, radius 18, `--hero-shadow`. Round white arrows, a
   "Pause" pill, a caption (`<b>Title</b> sub`), and a scrolling thumbnail strip with edge mask.
4. **Highlights**: 3 centered columns (icon, bold label, faint 2-line sub).
5. **"Works with" strip**: uppercase faint label + chip list (`--bg-2`, hairline border).
6. **Feature tiles**: section head (h2 with italic second line) + 3-col grid of 12 tiles.
7. **Pricing**: one rounded panel (`--bg-2` + top teal glow), perks list left, price card right.
8. **FAQ**: 560px column of `<details>`, chevron rotates 90° on open.
9. **Final CTA**: 84px app icon with teal glow shadow, "Ready to …?" h2, CTA row.
10. **Footer**: one centered row of faint 12px links.

Section rhythm: `120–160px` between sections (`100px` on mobile). Content max `1000px`.

## Colors

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#fafaf9` | `#121212` | Page (warm, never pure white) |
| `--bg-2` | `#f3f3f1` | `#171717` | Chips, pricing panel, slider stage |
| `--card` | `#fff` | `#1b1b1b` | Ghost button, mini-UI cards, kbd |
| `--tile` | `#f1f1ef` | `#181818` | Feature tiles |
| `--line` / `--line-2` | `#00000012` / `#0000001c` | `#ffffff12` / `#ffffff1f` | Hairlines (7% / 11%) |
| `--text` | `#151515` | `#ededed` | Headings, body |
| `--muted` | `#6a6a6a` | `#8b8b8b` | Lede, tile body, nav links |
| `--faint` | `#9a9a97` | `#5c5c5c` | Fine print, eyebrow, footer |
| `--accent-hi` → `--accent` | `#12a394` → `#0b8a7d` | `#16b3a3` → `#0f9a8c` | Primary button gradient, checks, meters |
| `--accent-glow` | `#12a39452` | `#16b3a359` | Button and icon glow |

Status colors used only inside mini-UIs: deny `#e5484d`, always `#d6a234`, allow/live
`#2f9e5b`, working `#4b8df8`, needs-you/warn `#e58a3a`, notch badge `#ff5f57`.
Agent chips use brand dots: Claude `#d97757`, Codex `#6b7cff`, Gemini `#4b8df8`.

## Typography

One family: **Inter Variable** (`@fontsource-variable/inter`), fallback SF Pro. Body 15px/1.5,
antialiased. Monospace for mini-UI code: `ui-monospace, SF Mono, Menlo` at 10.5–11.5px.

| Role | Size | Weight | Tracking | Notes |
|---|---|---|---|---|
| Hero h1 | `clamp(40px, 7vw, 64px)` / 1.06 | 500 | `-.035em` | Line 2 in `<em>`: italic 500, `-.04em` |
| Section h2 | `clamp(30px, 4.6vw, 44px)` / 1.1 | 500 | `-.03em` | Same italic second line |
| Pricing h2 / final h2 | `clamp(28–30px … 40–44px)` | 500 | `-.03em` | |
| FAQ h2 | 30px | 500 | `-.02em` | |
| Lede | 16px / 1.6 | 400 | — | `--muted`, hard `<br>` between 2 short lines (removed ≤760px) |
| Tile h3 | 16px | 500 | `-.01em` | Tile p 13.5px / 1.55 `--muted` |
| Nav / badge | 13px | 400 (brand 600) | — | |
| Fine print / eyebrow | 12px | 400 | eyebrow uppercase `.08em` | `--faint` |
| Price | 44px / 1.1 | 500 | `-.03em` | |

Headlines are **weight 500, never bold**. The italic second line is the signature move.

## Components

- **Nav pill**: `--nav-bg` (white 75%) + `backdrop-filter: blur(18px) saturate(1.4)`, 1px
  `--line-2` border, radius 999, `padding: 5px 6px`, `--nav-shadow`. Active link is
  `--text` with a 3px dot centered under it (`.nav-link.is-active:after`).
- **Buttons**: 40px tall, radius 999, `0 20px`, 14px/500, `gap: 8px`, `:active scale(.98)`.
  Primary = vertical teal gradient + `inset 0 1px 0 #ffffff38` top highlight +
  `0 6px 22px -6px var(--accent-glow)`. Ghost = `--card` + `--line-2` border.
- **Feature tile**: `--tile` bg, 1px `--line`, radius 16, `16px 18px 20px` padding. Top is a
  176px `.art` area (grid center) holding one mini-UI. Then h3 + p. Grid gap only `10px`.
  Columns 3 → 2 (≤900px) → 1 (≤560px). Reveal stagger: 0 / 60ms / 120ms per column.
- **Mini-UI card (`.ui`)**: `--card`, 1px `--line`, radius 12, 12px padding, 11.5px text,
  `0 6px 20px -8px #00000024`. Build product moments from divs: meters (5px track,
  `--accent-hi` fill), bar charts (last bar full opacity, others .35), kanban columns,
  chat bubble plus pill input with a round `--text` send button, server rows with red stop squares.
- **Notch mock**: `#0d0d0d` bar, `150×34`, radius `0 0 18px 18px`, 3 dots (first is Claude
  orange), and a red badge with a 2.4s `pulse` ring.
- **Keycap (`kbd`)**: 60×60, radius 14, `--card`, `0 2px 0 var(--line-2)` bottom edge + soft drop.
- **Price card**: `--card-2`, radius 18, 22px padding. Segmented plan switch: `--line` track,
  radius 11, 3px padding; the checked option gets `--card` + tiny shadow + weight 500.
- **FAQ**: `details` with bottom hairline, summary 15px/500, `13px 0` padding, chevron rotates 90°.

## Motion

- `.reveal`: `opacity 0 → 1`, `translateY(18px) → 0`, `.7s cubic-bezier(.2,.7,.2,1)`, set by an
  IntersectionObserver (`threshold .08`, `rootMargin 0 0 -8% 0`), once.
- Slider stage enters with `rise` (1s, from `translateY(30px) scale(.985)`, 0.1s delay).
  Slides move with `transform .7s cubic-bezier(.65,0,.25,1)`, autoplay every 5s.
- Hover is limited to color changes, a thumbnail lifting 2px, and arrows scaling to 1.06. No parallax.
- `prefers-reduced-motion`: reveals are shown immediately, the slider doesn't autoplay, the badge doesn't pulse.

## Adapting to another product

Keep: the canvas colors, Inter 500 headlines with italic line 2, hairlines, tile grid, pill nav.
Swap: the accent pair (`--accent`, `--accent-hi`, `--accent-glow`, `--hero-glow`, all from one
hue), the mini-UIs (draw *your* product's 12 moments small), the slider screenshots. Keep
copy terse. Use one-line tile descriptions and a two-line lede.

## Before finishing, verify

- [ ] Background is `#fafaf9`, not `#fff`. Cards are white on top of it
- [ ] Headlines are weight 500 with negative tracking, and line 2 is italic
- [ ] Exactly one accent hue. Everything else is grayscale (status colors only inside mini-UIs)
- [ ] Nav is a floating content-width pill with a blur, not a full-width bar
- [ ] Feature tiles show HTML mini-UIs, not screenshots
- [ ] Dark theme works via `data-theme="dark"` and is applied before paint
