'use strict';

const CACHE = 'gymmane-trial';
const PRECACHE = [];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await cache.addAll(PRECACHE);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('gymmane-trial-') && key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
    // Older installed shells have no update listener. An explicit refresh link
    // opts those clients into reloading only after the new cache is complete.
    for (const client of await self.clients.matchAll({ type: 'window' })) {
      const url = new URL(client.url);
      if (url.searchParams.get('update') !== '1') continue;
      url.searchParams.delete('update');
      // Do not await navigation inside activation: its fetch must wait until
      // this activation finishes, which otherwise deadlocks in WebKit.
      client.navigate(url.href).catch(console.error);
    }
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (event.request.mode === 'navigate') {
      return (await cache.match('index.html')) || fetch(event.request);
    }
    return (await cache.match(event.request)) || fetch(event.request);
  })());
});
