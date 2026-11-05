import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../../config.js';
import { one } from '../../db/pool.js';

// XFR-02 / BE-90.2: share links. The app registers these as universal /
// app links, so when Keys is installed the OS opens the app directly. When
// it is not, this page sends the visitor to the right store, and its meta
// tags give other apps a link preview.
const TYPES = ['c', 'profile', 'post', 'poll', 'update', 'event', 'ticket', 'club', 'board', 'club-invite'] as const;

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

export function shareLink(type: (typeof TYPES)[number], id: string) {
  return `${config.linkBaseUrl}/${type}/${id}`;
}

export async function linkRoutes(app: FastifyInstance) {
  app.get('/l/:type/:id', async (req, reply) => {
    const { type, id } = z.object({ type: z.enum(TYPES), id: z.string().max(64) }).parse(req.params);
    let title = 'Keys';
    let description = 'Unlock your community.';
    if (type === 'c') {
      const c = await one<{ name: string }>('select name from communities where code = $1', [id.toUpperCase()]);
      if (c) { title = `Join ${c.name} on Keys`; description = "I'm using the Keys app to stay connected to our community."; }
    }
    const ua = String(req.headers['user-agent'] ?? '');
    const store = /android/i.test(ua) ? config.playStoreUrl : config.appStoreUrl;
    reply.type('text/html').send(`<!doctype html><html><head><meta charset="utf-8">
<title>${esc(title)}</title>
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${config.linkBaseUrl}/static/share.png">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="0;url=${esc(store)}"></head>
<body><a href="${esc(store)}">Get Keys</a></body></html>`);
  });

  // Associated domain files for iOS universal links and Android app links.
  app.get('/.well-known/apple-app-site-association', async () => ({
    applinks: { details: [{ appIDs: [process.env.IOS_APP_ID ?? 'TEAMID.app.keys'], components: TYPES.map((t) => ({ '/': `/${t}/*` })) }] },
  }));
  app.get('/.well-known/assetlinks.json', async () => [{
    relation: ['delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name: 'app.keys', sha256_cert_fingerprints: (process.env.ANDROID_CERT_SHA256 ?? '').split(',').filter(Boolean) },
  }]);
}
