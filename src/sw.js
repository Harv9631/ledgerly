// Ledgerly Service Worker — offline shell caching
// Caches the app shell for fast load; API calls always go to network.

const CACHE = 'ledgerly-v1';
const SHELL = [
  '/app.html',
  '/style.css',
  '/manifest.json'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(SHELL))
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

  // Always fetch API calls and auth from network — never serve stale data
  if (url.pathname.startsWith('/api/') ||
      url.pathname.startsWith('/auth/') ||
      url.pathname.startsWith('/login') ||
      url.pathname.startsWith('/upgrade') ||
      event.request.method !== 'GET') {
    return;
  }

  // Shell pages: cache-first with network fallback
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        // Only cache successful same-origin responses
        if (response && response.status === 200 && response.type === 'basic') {
          const clone = response.clone();
          caches.open(CACHE).then(cache => cache.put(event.request, clone));
        }
        return response;
      });
    }).catch(() => caches.match('/app.html'))
  );
});
