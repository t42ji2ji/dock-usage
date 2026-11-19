(function () {
  var root = document.documentElement;
  var stage = document.querySelector(".stage");
  var video = stage.querySelector("video");
  var EN = "assets/intro.mp4", ZH = "assets/intro-zh.mp4";

  // 中文用 intro-zh.mp4；還沒有那支就退回英文版
  function setVideo(lang) {
    var want = lang === "zh" ? ZH : EN;
    if (video.getAttribute("src") === want) return;
    video.setAttribute("src", want);
    video.load();
  }
  video.addEventListener("error", function () {
    if (video.getAttribute("src") === ZH) { video.setAttribute("src", EN); video.load(); }
  });

  var titles = { en: "Dock Usage — your Dock, alive", zh: "Dock Usage — 讓 Dock 活起來" };
  function setLang(lang, remember) {
    root.setAttribute("data-lang", lang);
    root.lang = lang === "zh" ? "zh-Hant-TW" : "en";
    document.title = titles[lang];
    setVideo(lang);
    document.querySelectorAll("[data-set-lang]").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.getAttribute("data-set-lang") === lang));
    });
    if (remember) { try { localStorage.setItem("dock-usage-lang", lang); } catch (e) {} }
  }
  setLang(root.getAttribute("data-lang") || "en", false);
  document.querySelectorAll("[data-set-lang]").forEach(function (b) {
    b.addEventListener("click", function () { setLang(b.getAttribute("data-set-lang"), true); });
  });

  // Hero: the Dock shows until the intro video can actually play
  function show() { stage.classList.add("has-video"); }
  if (video.readyState >= 2) show(); else video.addEventListener("loadeddata", show);
})();
