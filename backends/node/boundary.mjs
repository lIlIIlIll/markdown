import {readFile, realpath} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Limited} from './protocol.mjs';

function inside(base, candidate) {
  const relative = path.relative(base, candidate);
  return relative !== '' && relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

// This is a browser resource boundary for trusted pinned engines, not an OS sandbox.
export async function guardedBrowser(browser, runtime, pixels) {
  const modules = await realpath(path.join(runtime, 'node_modules'));
  const index = await realpath(path.join(modules, '@mermaid-js/mermaid-cli/dist/index.html'));
  const fontFiles = new Set(await Promise.all(['font.css', 'NotoSansCJKsc-Regular.otf'].map(name => realpath(path.join(runtime, 'fonts', name)))));
  const pinnedFont = await realpath(path.join(runtime, 'fonts/NotoSansCJKsc-Regular.otf'));
  const fontBytes = await readFile(pinnedFont);
  const blocked = new Set();
  const dimension = Math.min(2048, Math.max(1, Math.floor(Math.sqrt(pixels))));
  async function allowed(request) {
    try {
      const url = new URL(request.url());
      if (url.protocol === 'file:') return request.resourceType() === 'document' && await realpath(fileURLToPath(url)) === index;
      if (url.origin !== 'https://mermaid-cli-intercept.invalid') return false;
      const candidate = await realpath(fileURLToPath(new URL(`file://${url.pathname}`)));
      if (fontFiles.has(candidate)) return ['stylesheet', 'font'].includes(request.resourceType());
      if (!inside(modules, candidate)) return false;
      const type = request.resourceType();
      return (type === 'script' && /\.(?:m?js)$/.test(candidate)) ||
        (type === 'stylesheet' && candidate.endsWith('.css')) ||
        (type === 'font' && /\.(?:woff2?|ttf|otf)$/.test(candidate));
    } catch { return false; }
  }
  async function reject(request) {
    blocked.add(request.url());
    if (!request.isInterceptResolutionHandled()) await request.abort(undefined, 1000);
  }
  async function ownedFont(request) {
    try {
      const url = new URL(request.url());
      return request.resourceType() === 'font' && url.origin === 'https://mermaid-cli-intercept.invalid' &&
        await realpath(fileURLToPath(new URL(`file://${url.pathname}`))) === pinnedFont;
    } catch { return false; }
  }
  async function newPage() {
    const page = await browser.newPage();
    const on = page.on.bind(page);
    on('request', async request => {
      if (!await allowed(request)) return reject(request);
      if (request.url().startsWith('file:')) return request.continue(undefined, 1000);
      if (await ownedFont(request)) return request.respond({status: 200, contentType: 'font/otf',
        headers: {'access-control-allow-origin': '*'}, body: fontBytes}, 1000);
    });
    // Upstream installs its reader later. Never invoke it for a rejected URL,
    // even when another request handler resolves asynchronously.
    page.on = (event, listener) => event === 'request'
      ? on(event, async request => !await allowed(request) ? reject(request) : await ownedFont(request) ? undefined : listener(request))
      : on(event, listener);
    const setViewport = page.setViewport.bind(page);
    page.setViewport = async viewport => {
      if (viewport.deviceScaleFactor !== undefined && viewport.deviceScaleFactor !== 1) throw new Limited();
      for (const size of [viewport.width, viewport.height]) if (!Number.isInteger(size) || size < 1 || size > dimension + 32) throw new Limited();
      return setViewport(viewport);
    };
    const screenshot = page.screenshot.bind(page);
    page.screenshot = async options => {
      const clip = options.clip;
      if (!clip || ![clip.x, clip.y, clip.width, clip.height].every(Number.isFinite) || clip.x < 0 || clip.y < 0 ||
          clip.width < 1 || clip.height < 1 || clip.width > dimension || clip.height > dimension || clip.width * clip.height > pixels) throw new Limited();
      return screenshot({...options, type: 'png'});
    };
    await page.setRequestInterception(true);
    return page;
  }
  return {newPage, blocked, dimension};
}
