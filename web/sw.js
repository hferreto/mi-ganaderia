/* Mi Ganado · service worker: guarda la app para usarla sin internet */
const VERSION = 'mi-ganado-v5-2';
const ARCHIVOS = ['./', 'index.html', 'supabase.js', 'manifest.webmanifest',
  'icon-192.png', 'icon-512.png', 'icon-maskable-512.png', 'apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(ARCHIVOS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
/* Solo archivos de la propia app; las llamadas a Supabase van directo a internet */
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== self.location.origin) return;
  const pagina = e.request.mode === 'navigate';
  e.respondWith((async () => {
    const cache = await caches.open(VERSION);
    try {
      const r = await fetch(e.request);           // con señal: versión más reciente
      if (r.ok) cache.put(pagina ? 'index.html' : e.request, r.clone());
      return r;
    } catch {                                      // sin señal: copia guardada
      return (await cache.match(pagina ? 'index.html' : e.request)) || (await cache.match('./')) || Response.error();
    }
  })());
});
