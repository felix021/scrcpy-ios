(() => {
  const preferenceKey = "scrcpy-privacy-language";
  const supported = ["zh-CN", "en"];
  let language = (navigator.language || "en").toLowerCase().startsWith("zh")
    ? "zh-CN"
    : "en";
  try {
    const saved = localStorage.getItem(preferenceKey);
    if (supported.includes(saved)) language = saved;
  } catch {
    // Browser language still works when local storage is unavailable.
  }
  // Set this before the stylesheet loads so the other translation never flashes.
  document.documentElement.lang = language;

  document.addEventListener("DOMContentLoaded", () => {
    function showLanguage(selected) {
      document.documentElement.lang = selected;
      const chinese = selected === "zh-CN";
      document.title = `${chinese ? "隐私政策" : "Privacy Policy"} — Remote · scrcpy`;
      const description = chinese
        ? "远控 · scrcpy 隐私政策"
        : "Privacy policy for Remote · scrcpy";
      document.querySelector('meta[name="description"]').content = description;
      document.querySelector('meta[property="og:title"]').content = document.title;
      document.querySelector('meta[property="og:description"]').content = description;
      document.querySelector("nav").setAttribute("aria-label", chinese ? "主导航" : "Main navigation");
      document.querySelector(".policy-languages").setAttribute("aria-label", chinese ? "页面语言" : "Page language");
      document.querySelector("#home-link").href = chinese ? "./" : "en/";
      document.querySelectorAll("[data-set-language]").forEach((button) => {
        button.setAttribute("aria-pressed", String(button.dataset.setLanguage === selected));
      });
    }

    showLanguage(language);
    document.querySelectorAll("[data-set-language]").forEach((button) => {
      button.addEventListener("click", () => {
        const selected = button.dataset.setLanguage;
        showLanguage(selected);
        try {
          localStorage.setItem(preferenceKey, selected);
        } catch {
          // Switching remains available for this visit without persistence.
        }
      });
    });
  });
})();
