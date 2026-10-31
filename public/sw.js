// Supply ERP · service worker de avisos (v1.65). No guarda nada en cache: solo recibe y abre avisos.
// v1.58: avisos mas llamativos. Vibracion con patron, botones (Abrir / Mas tarde), logo de la empresa si esta cargado,
// y los importantes (cierre por aprobar, alerta de calidad, OC nueva) se quedan en pantalla hasta que alguien los toque.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

const IMPORTANTES = ['cierre', 'calidad', 'oc', 'vehiculo'];
const VIBRA_FUERTE = [400, 150, 400, 150, 800];
const VIBRA_NORMAL = [250, 120, 250];
const ICONO_TIPO = { cierre: '🔒', calidad: '⚠', oc: '📩', orden: '🏭', sugerencia: '💡', prueba: '🔔', vehiculo: '🚚', inventario: '📦' };

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { titulo: 'Supply ERP', cuerpo: e.data ? e.data.text() : '' }; }
  const tipo = d.tipo || String(d.tag || '').split(':')[0] || '';
  const importante = IMPORTANTES.includes(tipo);
  const marca = ICONO_TIPO[tipo];
  let titulo = d.titulo || 'Supply ERP';
  if (marca && !titulo.startsWith(marca)) titulo = marca + ' ' + titulo;
  e.waitUntil(self.registration.showNotification(titulo, {
    body: d.cuerpo || '',
    icon: d.icon || '/icon-192.png',
    badge: '/icon-192.png',
    tag: d.tag || undefined,
    renotify: !!d.tag,
    requireInteraction: importante,
    vibrate: importante ? VIBRA_FUERTE : VIBRA_NORMAL,
    silent: false,
    timestamp: Date.now(),
    actions: [
      { action: 'abrir', title: importante ? 'Revisar ahora' : 'Abrir' },
      { action: 'luego', title: 'Más tarde' },
    ],
    data: { url: d.url || '/tablero' },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  if (e.action === 'luego') return;
  const url = new URL((e.notification.data && e.notification.data.url) || '/tablero', self.location.origin).href;
  e.waitUntil((async () => {
    const lista = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of lista) {
      if (c.url.startsWith(self.location.origin)) {
        try { await c.focus(); await c.navigate(url); return; } catch { /* sigue y abre una ventana nueva */ }
      }
    }
    await self.clients.openWindow(url);
  })());
});
