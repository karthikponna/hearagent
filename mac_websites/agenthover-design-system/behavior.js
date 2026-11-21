// Agent Hover page behavior, rewritten readably from the live inline scripts.
// Put the theme snippet in <head> (before CSS paints); run the rest after DOM load.

// --- <head>: apply a saved dark choice before first paint (light is the default)
try {
  if (localStorage.getItem("theme") === "dark") document.documentElement.dataset.theme = "dark";
} catch {}

// --- theme toggle
document.querySelectorAll(".theme-toggle").forEach((btn) => {
  btn.addEventListener("click", () => {
    const root = document.documentElement;
    const next = root.dataset.theme === "dark" ? "light" : "dark";
    if (next === "dark") root.dataset.theme = "dark";
    else delete root.dataset.theme;
    try { localStorage.setItem("theme", next); } catch {}
  });
});

// --- screenshot slider: 5s autoplay, pauses off-screen / hidden tab / reduced motion,
//     arrows, thumbs, ←/→ keys, 40px horizontal swipe, caption = <b>title</b> + sub
document.querySelectorAll("[data-slider]").forEach((slider) => {
  const track = slider.querySelector("[data-track]");
  const slides = [...track.children];
  const thumbs = [...slider.querySelectorAll("[data-thumb]")];
  const thumbRow = slider.querySelector("[data-thumbs]");
  const caption = slider.querySelector("[data-caption]");
  const playBtn = slider.querySelector("[data-play]");
  const playLabel = slider.querySelector("[data-play-label]");
  const stage = track.parentElement;
  let index = 0;
  let timer = 0;
  let paused = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let onScreen = true;

  const go = (i) => {
    index = (i + slides.length) % slides.length;
    track.style.transform = `translateX(-${index * 100}%)`;
    slides.forEach((s, n) => s.setAttribute("aria-hidden", String(n !== index)));
    thumbs.forEach((t, n) => t.setAttribute("aria-current", String(n === index)));
    const t = thumbs[index];
    const b = document.createElement("b");
    b.textContent = t.dataset.title;
    caption.replaceChildren(b, ` ${t.dataset.sub}`);
    [index, (index + 1) % slides.length].forEach((n) =>
      slides[n].querySelectorAll("img").forEach((img) => (img.loading = "eager")),
    );
    thumbRow.scrollLeft = t.offsetLeft - thumbRow.clientWidth / 2 + t.offsetWidth / 2;
    schedule();
  };
  const schedule = () => {
    clearTimeout(timer);
    if (!paused && onScreen && !document.hidden) timer = setTimeout(() => go(index + 1), 5000);
  };
  const setPaused = (p) => {
    paused = p;
    slider.classList.toggle("is-paused", p);
    playLabel.textContent = p ? "Play" : "Pause";
    playBtn.setAttribute("aria-label", p ? "Play slideshow" : "Pause slideshow");
    schedule();
  };

  slider.querySelector("[data-prev]").addEventListener("click", () => go(index - 1));
  slider.querySelector("[data-next]").addEventListener("click", () => go(index + 1));
  thumbs.forEach((t, n) => t.addEventListener("click", () => go(n)));
  playBtn.addEventListener("click", () => setPaused(!paused));
  slider.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft") go(index - 1);
    else if (e.key === "ArrowRight") go(index + 1);
    else return;
    e.preventDefault();
  });
  let x0 = 0, y0 = 0;
  stage.addEventListener("touchstart", (e) => { x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; }, { passive: true });
  stage.addEventListener("touchend", (e) => {
    const dx = e.changedTouches[0].clientX - x0;
    const dy = e.changedTouches[0].clientY - y0;
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) go(index + (dx < 0 ? 1 : -1));
  });
  new IntersectionObserver(([entry]) => { onScreen = entry.isIntersecting; schedule(); }).observe(stage);
  document.addEventListener("visibilitychange", schedule);
  setPaused(paused);
});

// --- scroll reveal: .reveal → .is-in once, 8% threshold, bottom margin -8%
const revealer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      revealer.unobserve(entry.target);
    }
  },
  { rootMargin: "0px 0px -8% 0px", threshold: 0.08 },
);
document.querySelectorAll(".reveal").forEach((el) => revealer.observe(el));

// --- pricing plan switch (radiogroup, ←/→ keys). data-plans='[{"macs":1,"price":9,"url":"…"}, …]'
document.querySelectorAll(".price-card[data-plans]").forEach((card) => {
  const plans = JSON.parse(card.dataset.plans);
  const buttons = card.querySelectorAll("[data-plan]");
  const select = (i) => {
    const plan = plans[i];
    buttons.forEach((b, n) => b.setAttribute("aria-checked", String(i === n)));
    card.querySelectorAll("[data-plan-price]").forEach((el) => (el.textContent = String(plan.price)));
    card.querySelector("[data-plan-macs]").textContent = `${plan.macs} Mac${plan.macs === 1 ? "" : "s"}`;
    card.querySelector("[data-plan-buy]").href = plan.url;
  };
  buttons.forEach((b, n) => {
    b.addEventListener("click", () => select(n));
    b.addEventListener("keydown", (e) => {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      e.preventDefault();
      const next = (n + (e.key === "ArrowRight" ? 1 : -1) + buttons.length) % buttons.length;
      select(next);
      buttons[next].focus();
    });
  });
});
