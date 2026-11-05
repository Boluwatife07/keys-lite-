import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';

export interface LinkPreview { url: string; title: string; description?: string; image?: string; site?: string }

// Blocks requests to private and local addresses (server-side request forgery).
function isPrivate(ip: string) {
  if (ip.includes(':')) return ip === '::1' || /^f[cd]/i.test(ip) || /^fe80/i.test(ip) || ip.startsWith('::ffff:127.') || ip.startsWith('::ffff:10.');
  const [a, b] = ip.split('.').map(Number);
  return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127);
}

const meta = (html: string, key: string) => {
  const re = new RegExp(`<meta[^>]+(?:property|name)=["']${key}["'][^>]*content=["']([^"']*)["']|<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${key}["']`, 'i');
  const m = html.match(re);
  return (m?.[1] ?? m?.[2])?.trim() || undefined;
};
const decode = (s?: string) => s?.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');

/** FED-04.5: fetch title and image for a pasted link (server side). */
export async function linkPreview(raw: string): Promise<LinkPreview> {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error('invalid url');
  }
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('invalid url');
  if (process.env.LINK_PREVIEW_ALLOW_PRIVATE !== '1') {
    const host = url.hostname.replace(/^\[|\]$/g, '');
    const ips = isIP(host) ? [host] : (await lookup(host, { all: true })).map((a) => a.address);
    if (ips.some(isPrivate)) throw new Error('blocked host');
  }
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 4000);
  try {
    const res = await fetch(url, { signal: ctl.signal, redirect: 'follow', headers: { 'user-agent': 'KeysLinkPreview/1.0', accept: 'text/html' } });
    const html = (await res.text()).slice(0, 300_000);
    const title = decode(meta(html, 'og:title') ?? html.match(/<title[^>]*>([^<]*)<\/title>/i)?.[1]?.trim()) || url.hostname;
    let image = meta(html, 'og:image');
    if (image) image = new URL(image, url).toString();
    return { url: url.toString(), title, description: decode(meta(html, 'og:description') ?? meta(html, 'description')), image, site: url.hostname.replace(/^www\./, '') };
  } finally {
    clearTimeout(t);
  }
}
