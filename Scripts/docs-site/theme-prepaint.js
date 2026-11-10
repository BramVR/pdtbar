(function () {
  let stored = null;
  try {
    stored = localStorage.getItem("theme");
  } catch {}
  const osDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  document.documentElement.dataset.theme = stored === "dark" || stored === "light" ? stored : osDark ? "dark" : "light";
})();
