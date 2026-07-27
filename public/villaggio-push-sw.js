self.addEventListener("push", (event) => {
  let payload = {};

  try {
    payload = event.data ? event.data.json() : {};
  } catch (error) {
    payload = {};
  }

  const title = payload.title || "Villaggio Girotto";
  const options = {
    body: payload.body || "Você tem uma mensagem pendente.",
    tag: payload.tag || "villaggio-whatsapp-task",
    renotify: true,
    data: {
      url: payload.url || "/admin/mensagens_whatsapp"
    }
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const targetUrl = event.notification.data?.url || "/admin/mensagens_whatsapp";

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      const matchingClient = clientList.find((client) => client.url.includes(targetUrl) && "focus" in client);

      if (matchingClient) return matchingClient.focus();
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
