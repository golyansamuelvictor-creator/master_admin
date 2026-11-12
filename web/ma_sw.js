// Master Admin service worker: uses less data and opens without a connection.
//
// · App files (index, scripts, engine): from the network first, so an update
//   is always picked up; the saved copy is used only when there is no
//   connection (the app still opens offline).
// · Pictures, sounds, fonts, the Bible text and media from Supabase storage:
//   kept on the device after the first download and not downloaded again
//   (storage links are matched without their one-time key).
// · Database data is never kept here (it is always live; forms keep their own
//   offline copy inside the app).
const SHELL = 'ma-shell-v1';
const MEDIA = 'ma-media-v1';
const MEDIA_MAX = 400;                    // files kept at most
const MEDIA_DAYS = 14;                    // then downloaded again

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(['./', 'index.html', 'manifest.json', 'splash/logo.webp']).catch(() => {})));
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) {
      if (![SHELL, MEDIA].includes(k)) await caches.delete(k); // old Flutter caches
    }
    await self.clients.claim();
  })());
});

function isMedia(url) {
  if (url.hostname === 'fonts.gstatic.com' || url.hostname === 'fonts.googleapis.com') return true;
  if (url.pathname.includes('/storage/v1/object/') || url.pathname.includes('/storage/v1/render/')) return true;
  if (url.origin === self.location.origin) {
    return url.pathname.includes('/assets/assets/') || url.pathname.includes('/assets/fonts/') ||
           url.pathname.includes('/assets/packages/') || url.pathname.includes('/icons/') ||
           /\.(png|jpe?g|webp|gif|svg|mp3|wav|ogg|ttf|otf|woff2?)$/i.test(url.pathname);
  }
  return false;
}

// storage links carry a one-time key (?token=…): the same file is the same entry
function mediaKey(url) {
  const u = new URL(url.href);
  u.searchParams.delete('token');
  return u.href;
}

async function fromMedia(req, url) {
  const cache = await caches.open(MEDIA);
  const key = mediaKey(url);
  const hit = await cache.match(key);
  if (hit) {
    const at = Number(hit.headers.get('x-ma-at') || 0);
    if (Date.now() - at < MEDIA_DAYS * 86400000) return hit;
  }
  try {
    const res = await fetch(req);
    // only whole, readable files (not video ranges or errors)
    if (res.ok && res.status === 200 && res.type !== 'opaque' && !req.headers.has('range')) {
      const len = Number(res.headers.get('content-length') || 0);
      if (!len || len < 15 * 1024 * 1024) {
        const body = await res.clone().blob();
        const headers = new Headers(res.headers);
        headers.set('x-ma-at', String(Date.now()));
        await cache.put(key, new Response(body, { status: 200, headers }));
        trim(cache);
      }
    }
    return res;
  } catch (err) {
    if (hit) return hit; // offline: the older copy
    throw err;
  }
}

async function trim(cache) {
  const keys = await cache.keys();
  for (let i = 0; i < keys.length - MEDIA_MAX; i++) await cache.delete(keys[i]);
}

async function networkFirst(req) {
  const cache = await caches.open(SHELL);
  try {
    const res = await fetch(req);
    if (res.ok && res.status === 200 && res.type === 'basic') cache.put(req, res.clone());
    return res;
  } catch (err) {
    const hit = await cache.match(req, { ignoreSearch: true }) ||
                (req.mode === 'navigate' ? await cache.match('index.html') : null);
    if (hit) return hit;
    throw err;
  }
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
  // live data and sign-in: never from here
  if (url.pathname.includes('/rest/v1/') || url.pathname.includes('/auth/v1/') ||
      url.pathname.includes('/functions/v1/') || url.pathname.includes('/realtime/')) return;
  if (isMedia(url)) {
    e.respondWith(fromMedia(req, url));
    return;
  }
  if (url.origin === self.location.origin) e.respondWith(networkFirst(req));
});
