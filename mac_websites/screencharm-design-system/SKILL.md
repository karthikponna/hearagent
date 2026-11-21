---
name: screencharm-design-system
description: Build a dark Mac-app marketing site in the Screen Charm (screencharm.com) visual language — near-black #161616 page, Geist 700 headlines with tight tracking, one word wrapped in a light-blue "highlighter" pill (#a9d1ff bg / #0b63d6 text), Apple-blue gradient pill buttons (#3d95ff → #0f6cf0) with an inset top highlight, a frosted dark pill nav, small bordered "section badge" pills above every centered heading, #1f1f1f radius-28 surface cards with 6% white hairlines, an autoplaying product video in a thick black bezel frame, alternating 50/50 feature rows (copy + looping video), an icon-list + sticky editor screenshot, a masonry X-testimonial wall with highlighted phrases, and two pricing cards where the featured one glows blue. Use when the user wants a Screen Charm-style page, a dark Apple-like SaaS/video-tool landing page, a highlighted-word headline, or to match screencharm.com colors, type, or layout.
disable-model-invocation: true
---

# Screen Charm Design System

Reverse-engineered from screencharm.com (Next.js, Tailwind v4, Geist). It's a **dark, quiet,
Apple-keynote** page. Everything is grayscale `#161616`–`#2a2a2a` except one Apple blue, and the
product **videos** carry the color. The pattern is deliberately repetitive: badge, then centered h2, then
grey sub, then content. That rhythm is what makes it feel polished.

## Files

| File | What it is |
|---|---|
| [site.css](site.css) | `--site-*` tokens plus every custom class (`apple-nav`, `apple-btn-*`, `section-badge`, `section-title`, `hero-highlight`, `apple-card*`, `apple-hero-*`, shadows, edge fades) and the macOS-card keyframes |
| [markup.html](markup.html) | Full homepage markup (scripts removed, icons collapsed). Tailwind utility strings are intact, so copy them |
| `reference/hero.jpg` | Hero at 1440×900 |
| `reference/audience-cards.jpg`, `feature-rows.jpg`, `editor-list.jpg`, `mac-card-showcase.jpg`, `testimonials.jpg`, `pricing.jpg`, `faq-founder.jpg`, `download-footer.jpg` | Sections |

With Tailwind v4, map the tokens in `@theme`: `--color-surface: var(--site-surface)`,
`--color-brand: var(--site-brand)`, `--color-accent: var(--site-accent)`, `--color-secondary: var(--site-text-secondary)`, `--color-tertiary: var(--site-text-tertiary)`.
Fonts: `npm i geist` and load `GeistSans` + `GeistMono` (Next: `geist/font/sans`).

## Page anatomy

1. **Nav** (`fixed top-3 sm:top-4`, centered, `max-w-[47rem]`): `apple-nav` pill, `#282828c7` +
   `blur(20px) saturate(180%)`, 1px 8%-white border, `0 10px 36px #00000059`, padding `6 6 6 12`.
   From left to right: logo plus "Screen Charm", ghost links (14px, white 82%, hover pill `#ffffff14`), "Help ▾",
   an outlined "Account" pill, a dark "Buy now", and a blue "Download app" (36px small buttons).
2. **Hero** (`pt-32 sm:pt-40`, centered, `max-w-5xl`), all on top of `apple-hero-glow` (three faint blue radial washes):
   - release badge: `section-badge` with a `section-badge-chip` "1.12.0" + "Added webcam background removal →"
   - h1 `apple-hero-title`: 64px / 1.06 / −.04em / 700, white, max 47rem. Line 2 starts with
     **`<span class="hero-highlight">Cinematic</span>`**: a light-blue pill around one word
   - lede `apple-hero-subtitle`: 19px / 1.55, `#a3a3a3`, max 34rem
   - CTAs: primary "Download app" (48px, Apple logo) + secondary "See how it works ›"
   - social proof: 5 overlapping 32px avatars + "Loved by founders, developers and SaaS teams" (14px secondary)
   - **video frame**: `max-w-6xl mt-20`. Outer `rounded-[34px] border-white/10 bg-[#0f0f0f] p-2.5 apple-shadow-media`,
     inner `rounded-[26px] overflow-hidden`, then an autoplaying muted `aspect-video` product demo
3. **Featured quote**: badge "What people say", a 36px `section-title` quote in curly quotes, then a 72px avatar + name / role.
4. **Who it's for**: 3 cards (`rounded-[28px] border-white/[0.06] bg-surface p-8`). Each has a 48px icon tile
   (`rounded-2xl bg-brand/15 text-accent`), a 12px uppercase `tracking-widest` accent eyebrow, a 20px/600 title, and a 16px secondary body.
5. **Features ("Built for creators")**: stacked `space-y-10` rows (`rounded-[28px] bg-surface`, `md:flex-row`,
   alternating `md:flex-row-reverse`). Half of each row is copy (`p-10 md:p-20`, h3 `section-title` 41.6px, 20px secondary body),
   and the other half is a 4:3 looping muted video that bleeds to the card edge.
6. **Editor ("One editor, full control")**: a left list of items (40px `rounded-xl bg-brand/15` icon, 20px/600
   title, 16px body, `py-7 border-b border-white/[0.08]`, icon brightens on hover) next to a **sticky** editor
   screenshot (rounded-28). Then a centered CTA: "Download app" + "No sign-up or credit card required".
7. **Designed for macOS**: a big `rounded-[2rem]` card with a corner blue radial plus a diagonal white sheen gradient,
   copy + 3 chip tiles (`rounded-2xl bg-white/[0.035] px-4 py-3`) on the left, and on the right a glass mini-window holding the
   app icon, with a blurred blue glow orb pulsing (`screencharm-glow 7s`), a float, and a sheen sweep.
8. **Showcase ("Made with Screen Charm")**: a swipeable snap-scroll row (`flex snap-x snap-mandatory
   overflow-x-auto`, hidden scrollbar, `[&>*]:snap-center`) of 680px `apple-card-subtle rounded-2xl` video
   cards with edge fades (`apple-gradient-edge-*`). Each card footer has an avatar + name/handle + "𝕏 View post" pill.
9. **Testimonials ("Our happy users")**: a 3-column masonry of `rounded-[20px] bg-surface p-5` cards linking to X.
   Each has a 36px avatar, name/handle, an X glyph, 5 amber stars, and 16px `text-white/80` copy with **the key
   phrase highlighted** (`<strong class="font-medium text-white bg-white/[0.16] rounded-[4px] px-1">`).
   A "Show more ▾" ghost pill sits at the end.
10. **Pricing ("Simple pricing")**: 2 cards in `max-w-[56rem]`, `rounded-[32px] p-9`. Monthly is plain surface with a secondary
    button. **Yearly is featured**: `border-brand/40`, a top-down `rgba(20,120,242,.12)` wash, and a
    `0 20px 60px -30px rgba(20,120,242,.6)` blue glow, plus an emerald "Save 61%" chip. Under that come a 72px price + "/year",
    a full-width 52px button, and a 2-col check list. Then the avatar row "Trusted by creators and teams".
11. **FAQ**: left founder card (`apple-card-subtle p-8`: avatar, name, a personal note with a bolded
    closing line) and right `details` accordions (`apple-card-subtle`, radius 20, summary `px-6 py-5`).
12. **Download**: badge, h2 "Download Screen Charm", sub, and a large blue "Download for Apple Silicon" button + OS note.
13. **Footer**: hairline top. Logo + a small "0.1% to Stripe Climate" card, then 6 dense link columns (14px tertiary
    links, white 14/600 heads), heavy on SEO (free tools, use cases, alternatives, comparisons).

Section rhythm: `px-6 py-16 sm:py-24`. Content `max-w-6xl` (1152px). Head block: badge, then
`mt-5` h2, then `mt-4` sub (`max-w-xl text-lg leading-relaxed text-secondary`), then `mt-14` content.

## Colors

| Token | Value | Use |
|---|---|---|
| `--site-bg` | `#161616` | Page |
| `--site-bg-secondary` | `#1c1c1c` | Alt bands |
| `--site-surface` | `#1f1f1f` | Every card |
| `--site-surface-raised` | `#2a2a2a` | Secondary button, nav fallback |
| `--site-border` / `-strong` | `#ffffff14` / `#ffffff1f` | Hairlines (cards use `white/[0.06]`) |
| `--site-fg` | `#f5f5f5` | Body text. Headings are pure `#fff` |
| `--site-text-secondary` | `#a3a3a3` | Ledes, card bodies |
| `--site-text-tertiary` | `#8a8a8a` | Handles, footer links, eyebrows |
| `--site-brand` | `#1677f5` | Focus, borders, icon tiles at 15% |
| `--site-brand-gradient` | `#3d95ff → #0f6cf0` (hover `#52a1ff → #1f78f5`) | Primary buttons |
| `--site-brand-glow` | `#1677f559` | Primary hover shadow |
| `--site-highlight-bg` / `-fg` | `#a9d1ff` / `#0b63d6` | Hero word pill, release chip |
| `--site-accent` | `#4a9dff` | Eyebrows, icons, links |
| Save chip | emerald-400 at 10% bg, emerald-300 text | Pricing discount only |

## Typography

**Geist** for everything (variable 100–900), Geist Mono available. Headings 700, body 400, UI 500.

| Role | Size | Line height | Tracking | Notes |
|---|---|---|---|---|
| Hero h1 (`apple-hero-title`) | `clamp(2.5rem, 5vw + .75rem, 4rem)` → 64px | 1.06 | −.04em | white, one `hero-highlight` word |
| Section h2 (`section-title`) | 36 → 48 → 60px | 1.05 (60/60) | −.035em | balanced |
| Feature row h3 | 36 → 41.6px | ~1.1 | −.035em | `section-title` too |
| Quote | 24 → 30 → 36px | snug | −.035em | `section-title` |
| Lede | 19px | 1.55 | — | `#a3a3a3` |
| Card title | 20px | 28px | — | 600 |
| Eyebrow | 12px | — | `tracking-widest`, uppercase | 600, `--site-accent` |
| Section badge | 13px | — | — | 500, white 85% |
| Nav / buttons | 14 / 16px | — | — | 400 / 500 |

`.apple-hero-charm` (Cormorant Garamond italic 500 at 1.18em) exists for an optional serif accent word.
It isn't used on the current homepage.

## Components

- **Primary button** (`apple-btn-primary`): `border-radius: 980px`, min 44px (sm 36, hero 48, pricing 52),
  blue gradient, `inset 0 1px 0 #ffffff40, 0 1px 2px #0000004d`. Hover: lighter gradient + `0 8px 28px` brand glow
  + `translateY(-1px)`. Focus: 2px brand/60% outline, offset 2.
- **Secondary button**: `#2a2a2a` + `inset 0 0 0 1px` border. Hover mixes in 14% white.
- **Section badge**: pill, `#ffffff0a` fill, 1px border, `5px 14px`, 13px/500. Above *every* h2.
- **Hero highlight**: `display: inline-block; border-radius: 9999px; padding: 0 .32em .04em; line-height: 1.12`.
- **Surface card**: `rounded-[28px] border border-white/[0.06] bg-surface`. Subtle variant radius 20 with a hover tint
  `#ffffff12` / border `#ffffff24`.
- **Icon tile**: 48px `rounded-2xl` (list: 40px `rounded-xl`), `bg-brand/15 text-accent`, lucide icons.
- **Media frame**: thick near-black bezel (`p-1.5 sm:p-2.5`, `#0f0f0f`, outer radius 34 / inner 26),
  `apple-shadow-media` (`0 20px 60px #00000052`). Use it for the hero video and big screenshots.
- **Avatar stack**: 32px circles with a 2px page-colored border (`border-2 border-dark-bg`), packed
  tight, then 2 lines of 14px secondary text.

## Motion

Restrained. Buttons lift 1px on hover over 300ms `cubic-bezier(.4,0,.2,1)`. Cards change border color on hover.
Feature videos autoplay muted on loop when visible. The showcase row is user-swiped (snap), not auto-scrolled. The only ambient animation is the
macOS card (glow 7s, float, aura, sheen). Release-badge and account tab enter with `translateY(6px) → 0`.
Everything respects `prefers-reduced-motion`.

## Adapting to another product

Keep the dark grayscale, Geist, the badge → h2 → sub rhythm, surface cards, and the bezel video frame.
Change `--site-brand*`, `--site-accent`, and `--site-highlight-*` to one hue family (highlight =
a very light tint + a deep shade of the same hue). Pick **one word** of your hero headline for the
highlight pill. Fill feature rows with short looping product videos (4:3), not static images. Rebuild
the X testimonial wall from real posts, highlighting one phrase in each.

## Before finishing, verify

- [ ] Page is `#161616`, cards are `#1f1f1f` with 6% white hairlines, and there are no other surface colors
- [ ] Every section heading has a small bordered badge above it and is centered
- [ ] Hero headline is Geist 700 at −.04em with exactly one highlighted word
- [ ] Primary buttons use the vertical blue gradient with an inset top highlight, and the radius is pill
- [ ] Hero video sits in a thick dark bezel with a large soft shadow
- [ ] Only one featured pricing card glows blue
- [ ] Media autoplays muted and pauses under reduced motion
