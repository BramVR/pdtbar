(function () {
  const root = document.documentElement;
  const toggle = document.querySelector("[data-theme-toggle]");
  const osDark = window.matchMedia("(prefers-color-scheme: dark)");

  function storedTheme() {
    try {
      return localStorage.getItem("theme");
    } catch {
      return null;
    }
  }

  function applyTheme(theme) {
    root.dataset.theme = theme;
    toggle.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
  }

  applyTheme(root.dataset.theme === "dark" ? "dark" : "light");

  toggle.addEventListener("click", () => {
    const next = root.dataset.theme === "dark" ? "light" : "dark";
    applyTheme(next);
    try {
      localStorage.setItem("theme", next);
    } catch {}
  });

  osDark.addEventListener("change", (event) => {
    if (!storedTheme()) applyTheme(event.matches ? "dark" : "light");
  });

  const headings = [...document.querySelectorAll(".doc .prose > h2[id]")];
  const railLinks = [...document.querySelectorAll(".rail a[href^='#']")];

  function markCurrentSection() {
    const readingLine = window.innerHeight * 0.3;
    let current = headings[0];
    for (const heading of headings) {
      if (heading.getBoundingClientRect().top <= readingLine) current = heading;
    }
    for (const link of railLinks) {
      if (link.getAttribute("href") === `#${current.id}`) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
  }

  if (headings.length && railLinks.length) {
    markCurrentSection();
    window.addEventListener("scroll", markCurrentSection, { passive: true });
    window.addEventListener("resize", markCurrentSection);
  }
})();
