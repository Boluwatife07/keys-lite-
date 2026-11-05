import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../../config.js';
import { requireUser } from '../../lib/auth.js';
import { notFound } from '../../lib/errors.js';

// Muted basemap to match the Figma map (light greys, no business pins).
const STYLE = [
  'feature:poi|visibility:off',
  'feature:transit|visibility:off',
  'element:labels.icon|visibility:off',
  'feature:landscape|color:0xf3f3f3',
  'feature:road|element:geometry|color:0xffffff',
  'feature:road|element:geometry.stroke|color:0xe0e0e0',
  'feature:water|color:0xdbe3e8',
  'element:labels.text.fill|color:0x8f8f8f',
];

// A static map image for the development shaping screen. The app draws its
// own pins on top, so the zoom and centre here must match its projection.
export async function mapRoutes(app: FastifyInstance) {
  app.get('/maps/static', async (req, reply) => {
    requireUser(req);
    const p = z.object({
      lat: z.coerce.number().min(-85).max(85),
      lng: z.coerce.number().min(-180).max(180),
      zoom: z.coerce.number().int().min(3).max(20),
      w: z.coerce.number().int().min(50).max(640),
      h: z.coerce.number().int().min(50).max(640),
    }).parse(req.query);
    if (config.mocks.places || !config.googlePlacesKey) throw notFound('Map images need a Google Maps key.');
    const qs = new URLSearchParams({
      center: `${p.lat},${p.lng}`,
      zoom: String(p.zoom),
      size: `${p.w}x${p.h}`,
      scale: '2',
      key: config.googlePlacesKey,
    });
    for (const s of STYLE) qs.append('style', s);
    const res = await fetch(`https://maps.googleapis.com/maps/api/staticmap?${qs}`);
    if (!res.ok) throw notFound('The map could not be loaded.');
    reply.header('content-type', res.headers.get('content-type') ?? 'image/png');
    reply.header('cache-control', 'private, max-age=86400');
    return reply.send(Buffer.from(await res.arrayBuffer()));
  });
}
