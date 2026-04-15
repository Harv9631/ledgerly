// Walify Service Worker
// Only caches static assets (CSS, icons, manifest).
// app.html is NEVER cached — it's dynamic (server injects Supabase config).

const CACHE = 'walify-v3';

// ── PUSH NOTIFICATIONS ────────────────────────────────────────────────────────
self.addEventListener('push', event => {
  if (!event.data) return;
  let data = {};
  try { data = event.data.json(); } catch { data = { title: 'Walify Alert', body: event.data.text() }; }
  event.waitUntil(
    self.registration.showNotification(data.title || 'Walify', {
      body: data.body || '',
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      tag: 'walify-alert',
      renotify: true,
      data: { url: '/app.html' }
    })
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cls => {
      const url = (event.notification.data || {}).url || '/app.html';
      const existing = cls.find(c => c.url.includes('/app.html'));
      if (existing) return existing.focus();
      return clients.openWindow(url);
    })
  );
});
const STATIC = [
  '/style.css',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(STATIC))
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Never intercept: API, auth, HTML pages, non-GET
  if (url.pathname.startsWith('/api/') ||
      url.pathname.endsWith('.html') ||
      url.pathname === '/' ||
      url.pathname.startsWith('/login') ||
      url.pathname.startsWith('/upgrade') ||
      url.pathname.startsWith('/privacy') ||
      url.pathname.startsWith('/terms') ||
      event.request.method !== 'GET') {
    return;
  }

  // Static assets: cache-first
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        if (response && response.status === 200 && response.type === 'basic') {
          const clone = response.clone();
          caches.open(CACHE).then(cache => cache.put(event.request, clone));
        }
        return response;
      });
    })
  );
});
