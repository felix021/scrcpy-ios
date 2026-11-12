(() => {
  const preferenceKey = "scrcpy-site-language";
  const supported = ["zh-CN", "en"];
  const normalize = (value) => {
    if (/^zh(?:-|$)/i.test(value)) return "zh-CN";
    if (/^en(?:-|$)/i.test(value)) return "en";
    return null;
  };
  const browserLanguages = navigator.languages?.length
    ? navigator.languages
    : [navigator.language || "en"];
  let language = browserLanguages.map(normalize).find(Boolean) || "en";
  try {
    // Preserve a language explicitly chosen on the previous privacy page.
    const saved = localStorage.getItem(preferenceKey)
      || localStorage.getItem("scrcpy-privacy-language");
    if (supported.includes(saved)) language = saved;
  } catch {
    // Language detection and switching also work without local storage.
  }

  // Run before CSS loads to avoid a flash of the other language.
  document.documentElement.lang = language;
  document.documentElement.classList.add("has-language-switch");

  function showLanguage(selected) {
    document.documentElement.lang = selected;
    const suffix = selected === "zh-CN" ? "Zh" : "En";
    document.querySelectorAll("[data-text-en]").forEach((node) => {
      node.textContent = node.dataset[`text${suffix}`];
    });
    document.querySelectorAll("[data-content-en]").forEach((node) => {
      node.content = node.dataset[`content${suffix}`];
    });
    document.querySelectorAll("[data-label-en]").forEach((node) => {
      node.setAttribute("aria-label", node.dataset[`label${suffix}`]);
    });
  }

  showLanguage(language);
  document.addEventListener("DOMContentLoaded", () => {
    showLanguage(language);
    document.querySelectorAll("[data-toggle-language]").forEach((button) => {
      button.addEventListener("click", () => {
        language = document.documentElement.lang === "zh-CN" ? "en" : "zh-CN";
        showLanguage(language);
        try {
          localStorage.setItem(preferenceKey, language);
        } catch {
          // Keep the current page usable even when persistence is blocked.
        }
      });
    });
  });
})();
