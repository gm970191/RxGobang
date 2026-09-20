const DISMISS_KEY = "rxgobang-pwa-dismiss";

function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches
    || window.navigator.standalone === true;
}

function isAppleMobile() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent)
    || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
}

function isMobile() {
  return isAppleMobile() || /android|mobile/i.test(navigator.userAgent);
}

const banner = document.getElementById("pwa-banner");
const bannerText = document.getElementById("pwa-banner-text");
const btnInstall = document.getElementById("btn-install");
const btnClose = document.getElementById("btn-pwa-close");

let deferredPrompt = null;

function hideBanner() {
  if (banner) banner.classList.add("is-hidden");
}

function showBanner(text, installable) {
  if (!banner || !bannerText || isStandalone()) return;
  if (localStorage.getItem(DISMISS_KEY) === "1") return;
  bannerText.textContent = text;
  if (btnInstall) btnInstall.classList.toggle("is-hidden", !installable);
  banner.classList.remove("is-hidden");
}

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  });
}

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredPrompt = event;
  showBanner("安装到主屏幕，可像应用一样离线对弈", true);
});

if (btnInstall) {
  btnInstall.addEventListener("click", async () => {
    if (!deferredPrompt) return;
    deferredPrompt.prompt();
    await deferredPrompt.userChoice.catch(() => {});
    deferredPrompt = null;
    hideBanner();
  });
}

if (btnClose) {
  btnClose.addEventListener("click", () => {
    localStorage.setItem(DISMISS_KEY, "1");
    hideBanner();
  });
}

if (!isStandalone() && !window.matchMedia("(display-mode: standalone)").matches) {
  if (isAppleMobile()) {
    showBanner("用 Safari 点底部分享，再选“添加到主屏幕”", false);
  } else if (isMobile()) {
    showBanner("可在浏览器菜单里选择“添加到主屏幕”", false);
  }
}
