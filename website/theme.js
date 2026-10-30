(() => {
  const key = "phone-check-theme";
  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
  let preference = "system";
  try {
    const saved = localStorage.getItem(key);
    if (saved === "light" || saved === "dark") preference = saved;
  } catch {}

  function apply() {
    const root = document.documentElement;
    if (preference === "system") root.removeAttribute("data-theme");
    else root.dataset.theme = preference;
    const dark =
      preference === "dark" || (preference === "system" && systemTheme.matches);
    document
      .querySelector('meta[name="theme-color"]')
      .setAttribute("content", dark ? "#111111" : "#ffffff");
  }
  apply();
  systemTheme.addEventListener("change", apply);
  document.addEventListener("DOMContentLoaded", () => {
    const select = document.querySelector("#theme-select");
    select.value = preference;
    select.addEventListener("change", () => {
      preference = select.value;
      apply();
      try {
        if (preference === "system") localStorage.removeItem(key);
        else localStorage.setItem(key, preference);
      } catch {}
    });
  });
})();
