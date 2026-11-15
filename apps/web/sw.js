// WalletWeather service worker (#41), served from /sw.js so it covers the
// whole site. It keeps only the page shell (the page, its icons and the
// manifest) so the installed app opens offline to a "You're offline"
// notice. No balances or transactions are ever stored: /api/* and /auth/*
// (and anything else not listed below) go straight to the network untouched.
//
// Network first: online, every open fetches the page from the server, so a
// new release shows up on the next open; the cache is only the fallback.
//
// Cloudflare Access: when its session has expired, the server's answer is a
// redirect to the Cloudflare sign-in page. That response is passed through
// (so the sign-in page opens) and never cached, so an expired session can't
// leave a broken page in the cache.
//
// Bump CACHE when the SHELL list changes; old caches are deleted on activate.
const CACHE = 'ww-shell-v1';
const SHELL = [
  '/',
  '/manifest.webmanifest',
  '/static/favicon.svg',
  '/static/icons/icon-192.png',
  '/static/icons/icon-512.png',
  '/static/icons/icon-maskable-512.png',
  '/static/icons/apple-touch-icon.png',
];

// Only a plain, successful, same-origin answer that wasn't redirected.
function cacheable(res) {
  return !!res && res.ok && res.type === 'basic' && !res.redirected;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.all(SHELL.map(async (url) => {
      try {
        const res = await fetch(url, { cache: 'no-cache', credentials: 'include', redirect: 'manual' });
        if (cacheable(res)) await cache.put(url, res);
      } catch { /* offline or blocked: filled on the next successful open */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  let key;
  if (req.mode === 'navigate') {
    if (url.pathname !== '/') return;  // only the app's own page
    key = '/';
  } else if (SHELL.includes(url.pathname)) {
    key = url.pathname;
  } else {
    return;
  }
  event.respondWith((async () => {
    try {
      const res = await fetch(req);
      if (cacheable(res)) {
        const cache = await caches.open(CACHE);
        await cache.put(key, res.clone());
      }
      return res;
    } catch (err) {
      const hit = await caches.match(key);
      if (hit) return hit;
      throw err;
    }
  })());
});
