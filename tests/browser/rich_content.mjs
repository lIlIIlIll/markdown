// Consume HTML emitted by the real Cangjie consumer; no engine mocks/downloads.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) { assert(i + 1 < process.argv.length); args.set(process.argv[i], process.argv[i + 1]); }
for (const key of ['--fixture', '--runtime-root', '--output', '--allow-no-sandbox']) assert(args.has(key), `missing ${key}`);
assert(['true', 'false'].includes(args.get('--allow-no-sandbox')));
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const runtime = resolve(args.get('--runtime-root'));
const output = resolve(args.get('--output'));
await mkdir(output, {recursive: true, mode: 0o700});
const fixture = await readFile(resolve(args.get('--fixture')), 'utf8');
const script = await readFile(resolve(root, 'assets/code-groups.js'), 'utf8');
const css = await readFile(resolve(root, 'assets/code-groups.css'), 'utf8');
const require = createRequire(resolve(runtime, 'package.json'));
const puppeteer = require('puppeteer');
const browser = await puppeteer.launch({executablePath: resolve(runtime, 'chrome/chrome'), headless: true, pipe: true,
  args: [...(args.get('--allow-no-sandbox') === 'true' ? ['--no-sandbox', '--disable-setuid-sandbox'] : []), '--disable-dev-shm-usage', '--disable-background-networking']});
const origin = 'https://example.test';
const html = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rich content gate</title><link rel="stylesheet" href="/assets/code-groups.css"><style>body{font:16px system-ui;margin:24px;max-width:900px}img{max-width:100%;height:auto}math{font-size:1.4em}</style><body>${fixture}</body></html>`;
const errors = [], unexpected = [];
let report;
try {
  const context = await browser.createBrowserContext();
  await context.overridePermissions(origin, ['clipboard-read', 'clipboard-sanitized-write']);
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  await page.setViewport({width: 1000, height: 700, deviceScaleFactor: 1});
  await page.setRequestInterception(true);
  page.on('request', request => {
    const url = request.url();
    if (url === `${origin}/`) return request.respond({status: 200, contentType: 'text/html; charset=utf-8', body: html});
    if (url === `${origin}/assets/code-groups.js`) return request.respond({status: 200, contentType: 'text/javascript; charset=utf-8', body: script});
    if (url === `${origin}/assets/code-groups.css`) return request.respond({status: 200, contentType: 'text/css; charset=utf-8', body: css});
    if (url === `${origin}/favicon.ico`) return request.respond({status: 204, body: ''});
    if (request.resourceType() === 'image' && url.startsWith('data:image/png;base64,')) return request.continue();
    unexpected.push(url); return request.abort();
  });
  await page.goto(`${origin}/`, {waitUntil: 'load'});
  assert.equal(await page.$$eval('figure.code-group-item', nodes => nodes.filter(node => !node.hidden).length), 2);
  const math = await page.$eval('math', node => ({width: node.getBoundingClientRect().width, height: node.getBoundingClientRect().height,
    fractions: node.querySelectorAll('mfrac').length, roots: node.querySelectorAll('msqrt').length}));
  assert(math.width > 20 && math.height > 20 && math.fractions === 1 && math.roots === 1);
  const image = await page.$eval('img.diagram', node => {
    const canvas = document.createElement('canvas'); canvas.width = node.naturalWidth; canvas.height = node.naturalHeight;
    const context = canvas.getContext('2d'); context.drawImage(node, 0, 0);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    const colors = new Set();
    for (let i = 0; i < pixels.length; i += 4) colors.add(`${pixels[i]},${pixels[i + 1]},${pixels[i + 2]},${pixels[i + 3]}`);
    return {width: node.naturalWidth, height: node.naturalHeight, colors: colors.size, alt: node.alt};
  });
  assert(image.width > 100 && image.height > 50 && image.colors > 4 && image.alt);
  assert.equal(await page.$eval('.code-group-item code', node => node.textContent), '\ufeffconst x = 1;\n中😀\n');
  assert(await page.$$eval('.code-group-item code span[style]', nodes => nodes.some(node => node.style.color)));
  assert.equal(await page.$$eval('.code-group-item code mark', nodes => nodes.length), 1);
  const client = await page.createCDPSession();
  const ax = await client.send('Accessibility.getFullAXTree');
  const mathRoles = ax.nodes.filter(node => /math/i.test(node.role?.value ?? '')).length;
  assert(mathRoles > 0);
  await page.evaluate(async () => { const module = await import('/assets/code-groups.js'); module.enhanceCodeGroups(); });
  await page.bringToFront();
  await page.click('.code-copy');
  await page.waitForFunction(() => document.querySelector('.code-group-status').textContent.includes('Copied'));
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), '\ufeffconst x = 1;\r\n中😀\r\n');
  await page.screenshot({path: resolve(output, 'rich-content.png'), fullPage: true});
  assert.deepEqual(errors, []); assert.deepEqual(unexpected, []);

  // Exercise the exact production request guard against owned outside content
  // and an external origin. Upstream readers must never receive either request.
  const {guardedBrowser} = await import(pathToFileURL(resolve(runtime, 'boundary.mjs')));
  const guarded = await guardedBrowser(browser, runtime, 4194304);
  const boundaryPage = await guarded.newPage();
  let upstreamCalls = 0;
  boundaryPage.on('request', request => { upstreamCalls++; return request.respond({status: 200, body: 'unexpected'}); });
  const outside = `https://mermaid-cli-intercept.invalid${pathToFileURL(resolve(args.get('--fixture'))).pathname}`;
  for (const url of [outside, 'https://example.test/blocked']) {
    await boundaryPage.evaluate(async value => { try { await fetch(value); } catch {} }, url);
    assert(guarded.blocked.has(url));
  }
  assert.equal(upstreamCalls, 0);
  await boundaryPage.close();
  report = {status: 'PASS', node: process.version, browser: await browser.version(), nativeMath: math, mathAccessibilityRoles: mathRoles,
    image, highlightedTextExact: true, rawClipboardExact: true, unexpectedPageRequests: 0, blockedBoundaryRequests: guarded.blocked.size,
    upstreamOutsideReads: upstreamCalls, fixtureSha256: createHash('sha256').update(fixture).digest('hex')};
  await writeFile(resolve(output, 'result.json'), JSON.stringify(report, null, 2) + '\n');
} finally { await browser.close(); }
console.log(JSON.stringify(report));
