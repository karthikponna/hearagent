// CoolDock motion, rewritten readably from the production bundle (app.js).
// Pairs with components.css. Add class "cd-js" to <html> before paint so intro states start hidden.

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

// --- hero intro: one class flips every staged animation in components.css
//     (header drops from -53px, heading at .3s, description + desktop mock at 1s,
//      CTA / trust row / rocks / eyebrow letters at 1.5s; letters stagger 50ms with a blur-in)
export function initHeroIntro() {
  const hero = document.querySelector("[data-cd-hero]");
  const header = document.querySelector("[data-cd-site-header]");
  if (!hero) return;
  // keyboard users skip the choreography the moment they tab into it
  document.addEventListener("focusin", (e) => {
    if (e.target instanceof Element && e.target.matches(":focus-visible"))
      e.target.closest("[data-cd-hero-intro], [data-cd-site-header]")?.classList.add("cd-intro-is-skipped");
  });
  requestAnimationFrame(() => {
    hero.classList.add("cd-hero-is-ready");
    header?.classList.add("cd-header-is-ready");
  });
}

// --- section reveal: [data-cd-reveal] blurs 7px → 0, rises 22px, scales .985 → 1 (0.65–0.76s)
export function initReveal() {
  const els = document.querySelectorAll("[data-cd-reveal]");
  if (reduced || !("IntersectionObserver" in window)) {
    els.forEach((el) => el.classList.add("cd-is-visible"));
    return;
  }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("cd-is-visible");
      io.unobserve(entry.target);
    }
  });
  els.forEach((el) => io.observe(el));
}

// --- closing CTA: a sticky wall of widget tiles zooms out (2× → 1×) and rises 490px → 0 over the
//     first 79% of the section's scroll, then fades and shrinks to .1 over the last 21%, while the app
//     icon scales 1.5 → 1 and rises 300px → 0 as the text frame scrolls in. The section is ~3900px
//     tall (sticky wall + a 2000px spacer + a 720px text frame) on a black background.
export function initCtaWall() {
  const section = document.querySelector("[data-cd-cta]");
  const textFrame = section?.querySelector(".cd-call-to-action__text-frame");
  if (!section || !textFrame) return;
  if (reduced) {
    section.dataset.cdCtaMode = "static";
    return;
  }
  section.dataset.cdCtaMode = "motion";
  let queued = false;
  const update = () => {
    queued = false;
    const rect = section.getBoundingClientRect();
    const p = clamp01((innerHeight - rect.top) / Math.max(section.offsetHeight, 1));
    const textP = clamp01((innerHeight - rect.top) / Math.max(textFrame.offsetHeight, 1));
    const zoomIn = clamp01(p / 0.79);
    const exit = clamp01((p - 0.79) / 0.21);
    const opacity = exit > 0 ? 1 - exit : zoomIn;
    const scale = exit > 0 ? 1 - 0.9 * exit : 2 - zoomIn;
    const translate = exit > 0 ? 0 : 490 * (1 - zoomIn);
    const s = section.style;
    s.setProperty("--cd-cta-wall-opacity", opacity.toFixed(4));
    s.setProperty("--cd-cta-wall-scale", scale.toFixed(4));
    s.setProperty("--cd-cta-wall-translate", `${translate.toFixed(2)}px`);
    s.setProperty("--cd-cta-icon-opacity", textP.toFixed(4));
    s.setProperty("--cd-cta-icon-scale", (1.5 - 0.5 * textP).toFixed(4));
    s.setProperty("--cd-cta-icon-translate", `${(300 * (1 - textP)).toFixed(2)}px`);
  };
  const onScroll = () => {
    if (!queued) { queued = true; requestAnimationFrame(update); }
  };
  // only listen while the section is near the viewport
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) {
      addEventListener("scroll", onScroll, { passive: true });
      addEventListener("resize", onScroll, { passive: true });
      onScroll();
    } else {
      removeEventListener("scroll", onScroll);
      removeEventListener("resize", onScroll);
    }
  }, { rootMargin: "200px 0px" }).observe(section);
}

export function initCoolDock() {
  initHeroIntro();
  initReveal();
  initCtaWall();
}
