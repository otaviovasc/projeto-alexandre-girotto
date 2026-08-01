function base64UrlToUint8Array(base64Url) {
  const padding = "=".repeat((4 - (base64Url.length % 4)) % 4);
  const base64 = (base64Url + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = window.atob(base64);
  return Uint8Array.from([...rawData].map((char) => char.charCodeAt(0)));
}

function setPushStatus(message) {
  document.querySelectorAll("[data-web-push-status]").forEach((element) => {
    element.textContent = message;
  });
}

function setPushButtonsState({ disabled = false, text = null } = {}) {
  document.querySelectorAll("[data-web-push-enable]").forEach((button) => {
    button.disabled = disabled;
    if (text) button.textContent = text;
  });
}

function isIosDevice() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
}

function isStandaloneApp() {
  return window.navigator.standalone === true ||
    window.matchMedia("(display-mode: standalone)").matches;
}

function requestNotificationPermission() {
  return new Promise((resolve) => {
    const result = Notification.requestPermission(resolve);
    if (result && typeof result.then === "function") result.then(resolve);
  });
}

async function registerWebPush() {
  const publicKey = document.querySelector("meta[name='villaggio-web-push-public-key']")?.content;
  const registerPath = document.querySelector("meta[name='villaggio-web-push-register-path']")?.content;
  const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;

  if (!publicKey || !registerPath || !csrfToken) {
    setPushStatus("Notificações ainda não configuradas para este acesso.");
    return false;
  }

  if (!window.isSecureContext) {
    setPushStatus("Notificações só funcionam em conexão segura.");
    return false;
  }

  if (!("Notification" in window) || !("serviceWorker" in navigator) || !("PushManager" in window)) {
    if (isIosDevice() && !isStandaloneApp()) {
      setPushStatus("No iPhone, abra pelo aplicativo instalado na Tela de Início para ativar notificações.");
      return false;
    }

    setPushStatus("Este aparelho/navegador não suporta notificações.");
    return false;
  }

  if (Notification.permission === "denied") {
    setPushStatus("Notificações bloqueadas neste aparelho.");
    return false;
  }

  if (Notification.permission !== "granted") {
    const permission = await requestNotificationPermission();
    if (permission !== "granted") {
      setPushStatus("Permissão de notificação não ativada.");
      return false;
    }
  }

  const registration = await navigator.serviceWorker.register("/villaggio-push-sw.js");
  const existingSubscription = await registration.pushManager.getSubscription();
  const subscription = existingSubscription || await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: base64UrlToUint8Array(publicKey)
  });

  const response = await fetch(registerPath, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken,
      "Accept": "application/json"
    },
    body: JSON.stringify({ subscription: subscription.toJSON() })
  });

  if (!response.ok) throw new Error("Falha ao salvar aparelho");

  setPushStatus("Notificações ativadas neste aparelho.");
  return true;
}

function setupWebPushButtons() {
  if (!("Notification" in window)) {
    setPushStatus("Este aparelho/navegador não suporta notificações.");
  } else if (Notification.permission === "granted") {
    setPushStatus("Notificações já liberadas neste aparelho. Toque para confirmar o cadastro.");
  } else if (Notification.permission === "denied") {
    setPushStatus("Notificações bloqueadas neste aparelho.");
  }

  document.querySelectorAll("[data-web-push-enable]").forEach((button) => {
    if (button.dataset.pushBound === "true") return;
    button.dataset.pushBound = "true";

    button.addEventListener("click", () => {
      setPushStatus("Ativando notificações...");
      setPushButtonsState({ disabled: true, text: "Ativando..." });

      registerWebPush().then((activated) => {
        if (activated) {
          setPushButtonsState({ disabled: false, text: "Notificações ativadas" });
        } else {
          setPushButtonsState({ disabled: false, text: "Ativar notificações neste aparelho" });
        }
      }).catch((error) => {
        console.warn(error);
        setPushStatus("Não foi possível ativar as notificações neste aparelho.");
        setPushButtonsState({ disabled: false, text: "Tentar ativar novamente" });
      });
    });
  });
}

document.addEventListener("turbo:load", setupWebPushButtons);
document.addEventListener("DOMContentLoaded", setupWebPushButtons);

if (document.readyState !== "loading") setupWebPushButtons();
